import Foundation
import Network
import Combine

public enum SyncConnectionStatus: String, Sendable {
    case disconnected = "Offline"
    case connecting = "Connecting..."
    case connected = "Synced & Ready"
    case error = "Sync Unavailable"
    case disabled = "Disabled"
    
    public var iconName: String {
        switch self {
        case .disconnected: return "circle"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .connected: return "checkmark.circle.fill"
        case .error: return "exclamationmark.circle.fill"
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
    
    // MARK: - Server Configuration from Environment
    
    public var serverHost: String {
        if let custom = settings.customHost, !custom.isEmpty { return custom }
        if let host = ProcessInfo.processInfo.environment["REDIS_HOST"], !host.isEmpty {
            return host
        }
        return loadDotEnv()["REDIS_HOST"] ?? "127.0.0.1"
    }
    
    public var serverPort: Int {
        if let custom = settings.customPort, custom > 0 { return custom }
        if let portStr = ProcessInfo.processInfo.environment["REDIS_PORT"], let p = Int(portStr) {
            return p
        }
        if let dotP = loadDotEnv()["REDIS_PORT"], let p = Int(dotP) {
            return p
        }
        return 6379
    }
    
    public var serverPassword: String {
        if let custom = settings.customPassword { return custom }
        if let pass = ProcessInfo.processInfo.environment["REDIS_PASSWORD"] {
            return pass
        }
        return loadDotEnv()["REDIS_PASSWORD"] ?? ""
    }
    
    public var serverUseTLS: Bool {
        if let custom = settings.customUseTLS { return custom }
        if let tlsStr = ProcessInfo.processInfo.environment["REDIS_TLS"] {
            return tlsStr == "1" || tlsStr.lowercased() == "true"
        }
        if let dotTls = loadDotEnv()["REDIS_TLS"] {
            return dotTls == "1" || dotTls.lowercased() == "true"
        }
        return false
    }
    
    private init() {
        // Load device ID
        if let savedId = UserDefaults.standard.string(forKey: deviceIdKey) {
            self.deviceId = savedId
        } else {
            let newId = UUID().uuidString
            UserDefaults.standard.set(newId, forKey: deviceIdKey)
            self.deviceId = newId
        }
        
        // Load user settings
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
        let emailChanged = settings.email != newSettings.email
        
        self.settings = newSettings
        if let encoded = try? JSONEncoder().encode(newSettings) {
            UserDefaults.standard.set(encoded, forKey: settingsKey)
        }
        
        if !newSettings.isEnabled {
            disconnectSubscriber()
            status = .disabled
            addLog("Cloud sync turned off", success: true)
        } else if !wasEnabled || emailChanged || !isSubscribed {
            reconnect()
        }
    }
    
    // MARK: - Logging
    
    private func addLog(_ message: String, success: Bool = true) {
        let entry = SyncLogEntry(message: message, isSuccess: success)
        syncLogs.insert(entry, at: 0)
        if syncLogs.count > 30 {
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
        guard settings.isEnabled, !settings.email.trimmingCharacters(in: .whitespaces).isEmpty else {
            status = .disabled
            return
        }
        
        status = .connecting
        addLog("Connecting cloud sync...", success: true)
        
        let hostStr = serverHost
        let portInt = serverPort
        let useTLS = serverUseTLS
        
        let params: NWParameters = useTLS ? .tls : .tcp
        let host = NWEndpoint.Host(hostStr)
        let port = NWEndpoint.Port(rawValue: UInt16(portInt)) ?? 6379
        
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
                    self.addLog("Sync paused: \(error.localizedDescription)", success: false)
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
        let password = serverPassword
        if !password.isEmpty {
            let authCmd = Self.makeRespCommand(["AUTH", password])
            conn.send(content: authCmd, completion: .contentProcessed { [weak self] error in
                Task { @MainActor in
                    if let error = error {
                        self?.status = .error
                        self?.addLog("Auth check failed: \(error.localizedDescription)", success: false)
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
                    self.addLog("Subscription failed: \(error.localizedDescription)", success: false)
                    self.scheduleReconnect()
                    return
                }
                
                self.isSubscribed = true
                self.status = .connected
                self.lastSyncDate = Date()
                self.addLog("Connected to cloud sync", success: true)
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
                    self.addLog("Connection dropped: \(error.localizedDescription)", success: false)
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
        
        // RESP message format: *3\r\n$7\r\nmessage\r\n$<len>\r\n<channel>\r\n$<len>\r\n<payload>\r\n
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
        // Prevent loopbacks
        if message.senderDeviceId == self.deviceId {
            return
        }
        
        lastSyncDate = Date()
        let store = AlarmStore.shared
        
        switch message.action {
        case .syncAll:
            if let incomingAlarms = message.alarms {
                store.alarms = incomingAlarms
                addLog("Synced \(incomingAlarms.count) alarms from your other device", success: true)
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
                addLog("Remote alarm triggered: \(incoming.title)", success: true)
                store.triggerAlarm(incoming)
            }
        case .remoteDismiss:
            addLog("Alarm dismissed from other device", success: true)
            store.dismissCurrentlyRinging()
        case .remoteSnooze:
            addLog("Alarm snoozed from other device", success: true)
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
        
        let hostStr = serverHost
        let portInt = serverPort
        let password = serverPassword
        let useTLS = serverUseTLS
        
        sendPublish(
            host: hostStr,
            port: portInt,
            password: password,
            useTLS: useTLS,
            channel: settings.activeChannel,
            message: jsonString
        ) { [weak self] success, err in
            Task { @MainActor in
                if success {
                    self?.lastSyncDate = Date()
                } else if let err = err {
                    self?.addLog("Sync push issue: \(err)", success: false)
                }
            }
        }
    }
    
    private func sendPublish(host: String, port: Int, password: String, useTLS: Bool, channel: String, message: String, completion: @escaping @Sendable (Bool, String?) -> Void) {
        let params: NWParameters = useTLS ? .tls : .tcp
        let endpointHost = NWEndpoint.Host(host)
        let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) ?? 6379
        
        let pubConn = NWConnection(host: endpointHost, port: endpointPort, using: params)
        
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
    
    // MARK: - .env Loader
    
    private func loadDotEnv() -> [String: String] {
        var result: [String: String] = [:]
        
        // Search paths
        let paths = [
            FileManager.default.currentDirectoryPath + "/.env",
            (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("com.alarm.macapp/.env").path) ?? "",
            Bundle.main.resourcePath.map { $0 + "/.env" } ?? ""
        ]
        
        for p in paths where !p.isEmpty {
            if FileManager.default.fileExists(atPath: p), let content = try? String(contentsOfFile: p, encoding: .utf8) {
                let lines = content.components(separatedBy: .newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.hasPrefix("#") && trimmed.contains("=") else { continue }
                    let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
                    if parts.count == 2 {
                        let key = parts[0].trimmingCharacters(in: .whitespaces)
                        let val = parts[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                        result[key] = val
                    }
                }
                break
            }
        }
        
        return result
    }
    
    // MARK: - RESP Helper
    
    nonisolated public static func makeRespCommand(_ args: [String]) -> Data {
        var str = "*\(args.count)\r\n"
        for arg in args {
            let count = arg.utf8.count
            str += "$\(count)\r\n\(arg)\r\n"
        }
        return str.data(using: .utf8) ?? Data()
    }
}
