import Foundation
import Network
import Combine

public enum SyncConnectionStatus: String, Sendable {
    case disconnected = "Disconnected"
    case connecting = "Connecting..."
    case connected = "Connected & Synced"
    case error = "Connection Error"
    case disabled = "Disabled"
    
    public var iconName: String {
        switch self {
        case .disconnected: return "circle"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .connected: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .disabled: return "slash.circle"
        }
    }
}

@MainActor
public final class RedisSyncService: ObservableObject {
    public static let shared = RedisSyncService()
    
    @Published public var settings: SyncSettings
    @Published public var status: SyncConnectionStatus = .disabled
    @Published public var lastSyncDate: Date? = nil
    @Published public var syncLogs: [SyncLogEntry] = []
    
    public let deviceId: String
    private let settingsKey = "com.alarm.syncSettings"
    private let deviceIdKey = "com.alarm.syncDeviceId"
    
    private var subscriberConnection: NWConnection?
    private var isSubscribed: Bool = false
    private var reconnectTimer: Timer?
    private var incomingBuffer = Data()
    
    private init() {
        // Load device ID
        if let savedId = UserDefaults.standard.string(forKey: deviceIdKey) {
            self.deviceId = savedId
        } else {
            let newId = UUID().uuidString
            UserDefaults.standard.set(newId, forKey: deviceIdKey)
            self.deviceId = newId
        }
        
        // Load settings
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(SyncSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = SyncSettings()
        }
        
        if settings.isEnabled && !settings.email.trimmingCharacters(in: .whitespaces).isEmpty {
            connectSubscriber()
        } else {
            self.status = .disabled
        }
    }
    
    // MARK: - Save Settings
    
    public func updateSettings(_ newSettings: SyncSettings) {
        let wasEnabled = settings.isEnabled
        let hostChanged = (settings.redisHost != newSettings.redisHost || settings.redisPort != newSettings.redisPort || settings.email != newSettings.email || settings.redisPassword != newSettings.redisPassword || settings.useTLS != newSettings.useTLS)
        
        self.settings = newSettings
        if let encoded = try? JSONEncoder().encode(newSettings) {
            UserDefaults.standard.set(encoded, forKey: settingsKey)
        }
        
        if !newSettings.isEnabled {
            disconnectSubscriber()
            status = .disabled
            addLog("Sync disabled", success: true)
        } else if !wasEnabled || hostChanged || !isSubscribed {
            reconnect()
        }
    }
    
    // MARK: - Logging
    
    private func addLog(_ message: String, success: Bool = true) {
        let entry = SyncLogEntry(message: message, isSuccess: success)
        syncLogs.insert(entry, at: 0)
        if syncLogs.count > 40 {
            syncLogs.removeLast()
        }
    }
    
    // MARK: - Subscriber Connection
    
    public func reconnect() {
        disconnectSubscriber()
        connectSubscriber()
    }
    
    private func disconnectSubscriber() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        isSubscribed = false
        subscriberConnection?.cancel()
        subscriberConnection = nil
    }
    
    private func connectSubscriber() {
        guard settings.isEnabled, !settings.redisHost.isEmpty else {
            status = .disabled
            return
        }
        
        status = .connecting
        addLog("Connecting to Redis at \(settings.redisHost):\(settings.redisPort)...", success: true)
        
        let params: NWParameters = settings.useTLS ? .tls : .tcp
        let host = NWEndpoint.Host(settings.redisHost)
        let port = NWEndpoint.Port(rawValue: UInt16(settings.redisPort)) ?? 6379
        
        let conn = NWConnection(host: host, port: port, using: params)
        self.subscriberConnection = conn
        
        conn.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor in
                guard let self = self else { return }
                switch newState {
                case .ready:
                    self.handleSubscriberReady(conn)
                case .failed(let error):
                    self.status = .error
                    self.addLog("Connection failed: \(error.localizedDescription)", success: false)
                    self.scheduleReconnect()
                case .cancelled:
                    self.isSubscribed = false
                case .waiting(let error):
                    self.status = .error
                    self.addLog("Network waiting: \(error.localizedDescription)", success: false)
                default:
                    break
                }
            }
        }
        
        conn.start(queue: .global(qos: .userInitiated))
    }
    
    private func handleSubscriberReady(_ conn: NWConnection) {
        // Authenticate if password provided
        if !settings.redisPassword.isEmpty {
            let authCmd = Self.makeRespCommand(["AUTH", settings.redisPassword])
            conn.send(content: authCmd, completion: .contentProcessed { [weak self] error in
                Task { @MainActor in
                    if let error = error {
                        self?.status = .error
                        self?.addLog("Auth send failed: \(error.localizedDescription)", success: false)
                        return
                    }
                    self?.subscribeToChannel(conn)
                }
            })
        } else {
            subscribeToChannel(conn)
        }
    }
    
    private func subscribeToChannel(_ conn: NWConnection) {
        let channel = settings.activeChannel
        let subCmd = Self.makeRespCommand(["SUBSCRIBE", channel])
        
        conn.send(content: subCmd, completion: .contentProcessed { [weak self] error in
            Task { @MainActor in
                guard let self = self else { return }
                if let error = error {
                    self.status = .error
                    self.addLog("Subscribe failed: \(error.localizedDescription)", success: false)
                    self.scheduleReconnect()
                    return
                }
                
                self.isSubscribed = true
                self.status = .connected
                self.addLog("Subscribed to channel: \(channel)", success: true)
                self.listenForMessages(conn)
            }
        })
    }
    
    private func listenForMessages(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, context, isComplete, error in
            Task { @MainActor in
                guard let self = self else { return }
                if let error = error {
                    self.status = .error
                    self.addLog("Receive error: \(error.localizedDescription)", success: false)
                    self.scheduleReconnect()
                    return
                }
                
                if let data = data, !data.isEmpty {
                    self.processIncomingData(data)
                }
                
                if !isComplete {
                    self.listenForMessages(conn)
                }
            }
        }
    }
    
    private func scheduleReconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                if self?.settings.isEnabled == true {
                    self?.connectSubscriber()
                }
            }
        }
    }
    
    // MARK: - Incoming Data & Parsing
    
    private func processIncomingData(_ data: Data) {
        incomingBuffer.append(data)
        
        guard let text = String(data: incomingBuffer, encoding: .utf8) else {
            return
        }
        
        // RESP array for message: *3\r\n$7\r\nmessage\r\n$<len>\r\n<channel>\r\n$<len>\r\n<payload>\r\n
        if let msgRange = text.range(of: "message\r\n") {
            let afterMsg = text[msgRange.upperBound...]
            let parts = afterMsg.components(separatedBy: "\r\n")
            if parts.count >= 4 {
                let payload = parts[3]
                if let payloadData = payload.data(using: .utf8),
                   let syncMsg = try? JSONDecoder().decode(SyncMessage.self, from: payloadData) {
                    incomingBuffer.removeAll()
                    handleRemoteSyncMessage(syncMsg)
                    return
                }
            }
        }
        
        if incomingBuffer.count > 100000 {
            incomingBuffer.removeAll()
        }
    }
    
    private func handleRemoteSyncMessage(_ message: SyncMessage) {
        if message.senderDeviceId == self.deviceId {
            return
        }
        
        lastSyncDate = Date()
        addLog("Received remote action '\(message.action.rawValue)' from \(message.email)", success: true)
        
        let store = AlarmStore.shared
        
        switch message.action {
        case .syncAll:
            if let incomingAlarms = message.alarms {
                store.alarms = incomingAlarms
                addLog("Merged \(incomingAlarms.count) alarms from remote", success: true)
            }
        case .upsertAlarm:
            if let incoming = message.alarm {
                if let idx = store.alarms.firstIndex(where: { $0.id == incoming.id }) {
                    store.alarms[idx] = incoming
                    addLog("Updated alarm '\(incoming.title)' from remote", success: true)
                } else {
                    store.alarms.append(incoming)
                    addLog("Added new alarm '\(incoming.title)' from remote", success: true)
                }
            }
        case .deleteAlarm:
            if let incoming = message.alarm {
                store.alarms.removeAll { $0.id == incoming.id }
                addLog("Deleted alarm from remote", success: true)
            }
        case .remoteTrigger:
            if let incoming = message.alarm {
                addLog("Triggering remote alarm: \(incoming.title)", success: true)
                store.triggerAlarm(incoming)
            }
        case .remoteDismiss:
            addLog("Remote dismiss received", success: true)
            store.dismissCurrentlyRinging()
        case .remoteSnooze:
            addLog("Remote snooze received", success: true)
            store.snoozeCurrentlyRinging()
        }
    }
    
    // MARK: - Publishing Local Events
    
    public func publishAlarmChange(action: SyncAction, alarm: AlarmItem? = nil, allAlarms: [AlarmItem]? = nil) {
        guard settings.isEnabled, !settings.email.isEmpty else { return }
        
        let syncMsg = SyncMessage(
            senderDeviceId: self.deviceId,
            email: settings.email,
            action: action,
            alarm: alarm,
            alarms: allAlarms
        )
        
        guard let jsonData = try? JSONEncoder().encode(syncMsg),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }
        
        sendPublish(channel: settings.activeChannel, message: jsonString) { [weak self] success, err in
            Task { @MainActor in
                if success {
                    self?.lastSyncDate = Date()
                    self?.addLog("Published '\(action.rawValue)' to cloud", success: true)
                } else {
                    self?.addLog("Failed to publish: \(err ?? "unknown")", success: false)
                }
            }
        }
    }
    
    private func sendPublish(channel: String, message: String, completion: @escaping @Sendable (Bool, String?) -> Void) {
        let params: NWParameters = settings.useTLS ? .tls : .tcp
        let host = NWEndpoint.Host(settings.redisHost)
        let port = NWEndpoint.Port(rawValue: UInt16(settings.redisPort)) ?? 6379
        let password = settings.redisPassword
        
        let pubConn = NWConnection(host: host, port: port, using: params)
        
        pubConn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if !password.isEmpty {
                    let authCmd = Self.makeRespCommand(["AUTH", password])
                    pubConn.send(content: authCmd, completion: .contentProcessed { authErr in
                        if let authErr = authErr {
                            pubConn.cancel()
                            completion(false, authErr.localizedDescription)
                            return
                        }
                        Self.executePublish(pubConn: pubConn, channel: channel, message: message, completion: completion)
                    })
                } else {
                    Self.executePublish(pubConn: pubConn, channel: channel, message: message, completion: completion)
                }
            case .failed(let error):
                pubConn.cancel()
                completion(false, error.localizedDescription)
            default:
                break
            }
        }
        
        pubConn.start(queue: .global(qos: .userInitiated))
    }
    
    nonisolated private static func executePublish(pubConn: NWConnection, channel: String, message: String, completion: @escaping @Sendable (Bool, String?) -> Void) {
        let cmd = makeRespCommand(["PUBLISH", channel, message])
        pubConn.send(content: cmd, completion: .contentProcessed { error in
            pubConn.cancel()
            if let error = error {
                completion(false, error.localizedDescription)
            } else {
                completion(true, nil)
            }
        })
    }
    
    // MARK: - Manual Test Connection
    
    public func testConnection(completion: @escaping @Sendable (Bool, String) -> Void) {
        addLog("Testing Redis connection...", success: true)
        let params: NWParameters = settings.useTLS ? .tls : .tcp
        let host = NWEndpoint.Host(settings.redisHost)
        let port = NWEndpoint.Port(rawValue: UInt16(settings.redisPort)) ?? 6379
        let password = settings.redisPassword
        
        let testConn = NWConnection(host: host, port: port, using: params)
        
        testConn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if !password.isEmpty {
                    let authCmd = Self.makeRespCommand(["AUTH", password])
                    testConn.send(content: authCmd, completion: .contentProcessed { err in
                        if let err = err {
                            testConn.cancel()
                            completion(false, "Authentication error: \(err.localizedDescription)")
                            return
                        }
                        Self.sendPing(testConn: testConn, completion: completion)
                    })
                } else {
                    Self.sendPing(testConn: testConn, completion: completion)
                }
            case .failed(let error):
                testConn.cancel()
                completion(false, "Network connection failed: \(error.localizedDescription)")
            default:
                break
            }
        }
        
        testConn.start(queue: .global(qos: .userInitiated))
    }
    
    nonisolated private static func sendPing(testConn: NWConnection, completion: @escaping @Sendable (Bool, String) -> Void) {
        let ping = makeRespCommand(["PING"])
        testConn.send(content: ping, completion: .contentProcessed { error in
            if let error = error {
                testConn.cancel()
                completion(false, "Ping failed: \(error.localizedDescription)")
                return
            }
            
            testConn.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, recErr in
                testConn.cancel()
                if let recErr = recErr {
                    completion(false, "Failed to receive response: \(recErr.localizedDescription)")
                } else if let data = data, let str = String(data: data, encoding: .utf8), str.contains("PONG") {
                    completion(true, "Successfully connected to Redis! Server responded with PONG.")
                } else {
                    completion(true, "Connected to Redis server successfully.")
                }
            }
        })
    }
    
    // MARK: - RESP Helpers
    
    nonisolated public static func makeRespCommand(_ args: [String]) -> Data {
        var str = "*\(args.count)\r\n"
        for arg in args {
            let count = arg.utf8.count
            str += "$\(count)\r\n\(arg)\r\n"
        }
        return str.data(using: .utf8) ?? Data()
    }
}
