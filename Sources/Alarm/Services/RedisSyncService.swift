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
    
    // MARK: - Server Configuration from Environment / URL
    
    public struct RedisConnectionConfig {
        public let host: String
        public let port: Int
        public let password: String
        public let useTLS: Bool
    }
    
    public var connectionConfig: RedisConnectionConfig {
        let env = ProcessInfo.processInfo.environment
        let dot = loadDotEnv()
        
        // 1. Check for REDIS_URL first (from environment or .env)
        let rawUrl = env["REDIS_URL"] ?? dot["REDIS_URL"]
        if let rawUrl = rawUrl, !rawUrl.trimmingCharacters(in: .whitespaces).isEmpty,
           let components = URLComponents(string: rawUrl.trimmingCharacters(in: .whitespaces)) {
            let scheme = components.scheme?.lowercased() ?? "redis"
            let useTLS = (scheme == "rediss")
            let host = components.host ?? "127.0.0.1"
            let port = components.port ?? (useTLS ? 6380 : 6379)
            var password = components.password ?? ""
            if password.isEmpty, let user = components.user, !user.isEmpty {
                password = user
            }
            return RedisConnectionConfig(host: host, port: port, password: password, useTLS: useTLS)
        }
        
        // 2. Fall back to individual components (with custom settings overrides if present)
        let host = settings.customHost ?? env["REDIS_HOST"] ?? dot["REDIS_HOST"] ?? "127.0.0.1"
        
        let portInt: Int
        if let custom = settings.customPort, custom > 0 {
            portInt = custom
        } else if let pStr = env["REDIS_PORT"], let p = Int(pStr) {
            portInt = p
        } else if let pStr = dot["REDIS_PORT"], let p = Int(pStr) {
            portInt = p
        } else {
            portInt = 6379
        }
        
        let password = settings.customPassword ?? env["REDIS_PASSWORD"] ?? dot["REDIS_PASSWORD"] ?? ""
        
        let useTLS: Bool
        if let custom = settings.customUseTLS {
            useTLS = custom
        } else if let tlsStr = env["REDIS_TLS"] {
            useTLS = (tlsStr == "1" || tlsStr.lowercased() == "true")
        } else if let tlsStr = dot["REDIS_TLS"] {
            useTLS = (tlsStr == "1" || tlsStr.lowercased() == "true")
        } else {
            useTLS = false
        }
        
        return RedisConnectionConfig(host: host, port: portInt, password: password, useTLS: useTLS)
    }
    
    public var serverHost: String { connectionConfig.host }
    public var serverPort: Int { connectionConfig.port }
    public var serverPassword: String { connectionConfig.password }
    public var serverUseTLS: Bool { connectionConfig.useTLS }
    
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
        
        // Comprehensive search paths for .env across bundle resources, current dir, home, and app support
        var paths: [String] = []
        if let resPath = Bundle.main.resourcePath {
            paths.append(resPath + "/.env")
        }
        paths.append(Bundle.main.bundlePath + "/Contents/Resources/.env")
        paths.append(Bundle.main.bundlePath + "/.env")
        paths.append(FileManager.default.currentDirectoryPath + "/.env")
        paths.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".macalarm.env").path)
        paths.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".env").path)
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            paths.append(appSupport.appendingPathComponent("MacAlarm Now/.env").path)
            paths.append(appSupport.appendingPathComponent("com.alarm.macapp/.env").path)
        }
        paths.append("/Users/emmsdan/Repo/hexify/alarm/.env")
        
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
                        if result[key] == nil {
                            result[key] = val
                        }
                    }
                }
                if !result.isEmpty {
                    break
                }
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
