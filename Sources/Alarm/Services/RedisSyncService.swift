import Foundation
import Network
import Combine

public enum SyncConnectionStatus: String, Sendable {
    case disconnected = "Offline"
    case connecting = "Connecting..."
    case connected = "Synced & Ready"
    case error = "Sync Paused"
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
    @Published public var isSyncing: Bool = false
    
    public let deviceId: String
    private let settingsKey = "com.alarm.syncSettings"
    private let deviceIdKey = "com.alarm.syncDeviceId"
    
    private var subscriberConnection: NWConnection?
    private var isSubscribed: Bool = false
    private var reconnectTimer: Timer?
    private var autoSyncTimer: Timer?
    private var incomingBuffer = Data()
    
    // Auto-sync & Backoff state (10-15s standard interval, exponential backoff on failure)
    private var currentSyncInterval: TimeInterval = 12.0
    private var consecutiveFailures: Int = 0
    private var isPullingInProgress: Bool = false
    private var isPushingInProgress: Bool = false
    
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
            startAutoSyncLoop()
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
            stopAutoSyncLoop()
            status = .disabled
            addLog("Cloud sync turned off", success: true)
        } else if !wasEnabled || emailChanged || !isSubscribed {
            reconnect()
            startAutoSyncLoop()
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
    
    // MARK: - Subscriber Connection (Real-time Pub/Sub)
    
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
                    self.handleSubscriberFailure(error)
                case .cancelled:
                    self.isSubscribed = false
                case .waiting(let error):
                    self.handleSubscriberFailure(error)
                default:
                    break
                }
            }
        }
        
        conn.start(queue: .global(qos: .userInitiated))
    }
    
    private func handleSubscriberFailure(_ error: Error) {
        self.status = .disconnected
        self.isSubscribed = false
        self.scheduleSubscriberReconnect()
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
                    self.status = .disconnected
                    self.addLog("Subscription disconnected: \(error.localizedDescription)", success: false)
                    self.scheduleSubscriberReconnect()
                    return
                }
                
                self.isSubscribed = true
                self.status = .connected
                self.lastSyncDate = Date()
                self.consecutiveFailures = 0
                self.addLog("Connected to cloud sync", success: true)
                self.listenForMessages(conn)
                
                // On subscriber connection, immediately pull latest persistent state!
                self.pullLatestFromRedis()
            }
        })
    }
    
    private func listenForMessages(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, context, isComplete, error in
            Task { @MainActor in
                guard let self = self else { return }
                if let error = error {
                    self.isSubscribed = false
                    self.addLog("Cloud stream paused: \(error.localizedDescription)", success: false)
                    self.scheduleSubscriberReconnect()
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
    
    private func scheduleSubscriberReconnect() {
        reconnectTimer?.invalidate()
        let delay = min(5.0 * pow(1.5, Double(consecutiveFailures)), 60.0)
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                if self?.settings.isEnabled == true {
                    self?.connectSubscriber()
                }
            }
        }
    }
    
    // MARK: - Incoming Real-Time Messages
    
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
                store.mergeRemoteAlarms(incomingAlarms, remoteLastUpdated: Date(timeIntervalSince1970: message.timestamp), remoteDeviceId: message.senderDeviceId)
                addLog("Synced \(incomingAlarms.count) alarms from remote", success: true)
            }
        case .upsertAlarm:
            if let incoming = message.alarm {
                if let idx = store.alarms.firstIndex(where: { $0.id == incoming.id }) {
                    store.alarms[idx] = incoming
                    store.sortAlarms()
                    store.saveAlarms()
                    addLog("Updated alarm '\(incoming.title)' from remote", success: true)
                } else {
                    store.alarms.append(incoming)
                    store.sortAlarms()
                    store.saveAlarms()
                    addLog("Added new alarm '\(incoming.title)' from remote", success: true)
                }
            }
        case .deleteAlarm:
            if let incoming = message.alarm {
                store.deleteAlarm(id: incoming.id)
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
    
    // MARK: - Automatic Polling & Exponential Backoff Loop
    
    public func startAutoSyncLoop() {
        stopAutoSyncLoop()
        guard settings.isEnabled, !settings.email.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        scheduleNextAutoSync(interval: currentSyncInterval)
    }
    
    public func stopAutoSyncLoop() {
        autoSyncTimer?.invalidate()
        autoSyncTimer = nil
    }
    
    private func scheduleNextAutoSync(interval: TimeInterval) {
        autoSyncTimer?.invalidate()
        autoSyncTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.settings.isEnabled else { return }
                self.pullLatestFromRedis()
            }
        }
    }
    
    private func handleSyncFailure(_ error: Error?) {
        consecutiveFailures += 1
        
        // Exponential backoff: 15s * 1.5^failures capped at 120s
        let backoff = min(15.0 * pow(1.5, Double(consecutiveFailures)), 120.0)
        currentSyncInterval = backoff
        
        self.status = .disconnected
        scheduleNextAutoSync(interval: backoff)
        
        if consecutiveFailures <= 3 {
            addLog("Cloud unreachable, retrying in \(Int(backoff))s", success: false)
        }
    }
    
    private func handleSyncSuccess() {
        consecutiveFailures = 0
        currentSyncInterval = 12.0 // Standard 10-15s interval
        self.status = .connected
        self.lastSyncDate = Date()
        scheduleNextAutoSync(interval: 12.0)
    }
    
    // MARK: - Manual Immediate Sync
    
    public func syncNow() {
        consecutiveFailures = 0
        currentSyncInterval = 12.0
        pullLatestFromRedis { [weak self] _ in
            Task { @MainActor in
                self?.pushAlarmsToRedis(AlarmStore.shared.alarms, action: .syncAll)
            }
        }
    }
    
    // MARK: - Persistent Key-Value Push (SET + PUBLISH)
    
    public func pushAlarmsToRedis(
        _ alarms: [AlarmItem],
        action: SyncAction = .syncAll,
        triggeredAlarm: AlarmItem? = nil,
        completion: (@Sendable (Bool) -> Void)? = nil
    ) {
        guard settings.isEnabled, !settings.email.isEmpty else {
            completion?(true)
            return
        }
        
        let container = RemoteSyncContainer(
            lastUpdated: Date(),
            deviceId: self.deviceId,
            email: settings.email,
            alarms: alarms,
            deletedAlarmIds: AlarmStore.shared.deletedAlarmIds
        )
        
        guard let containerData = try? JSONEncoder().encode(container),
              let containerJson = String(data: containerData, encoding: .utf8) else {
            completion?(false)
            return
        }
        
        let syncMsg = SyncMessage(
            senderDeviceId: self.deviceId,
            email: settings.email,
            action: action,
            alarm: triggeredAlarm,
            alarms: alarms
        )
        
        let msgJson: String
        if let msgData = try? JSONEncoder().encode(syncMsg), let str = String(data: msgData, encoding: .utf8) {
            msgJson = str
        } else {
            msgJson = "{}"
        }
        
        let hostStr = serverHost
        let portInt = serverPort
        let password = serverPassword
        let useTLS = serverUseTLS
        let dataKey = settings.activeDataKey
        let channel = settings.activeChannel
        
        sendSetAndPublish(
            host: hostStr,
            port: portInt,
            password: password,
            useTLS: useTLS,
            dataKey: dataKey,
            containerJson: containerJson,
            channel: channel,
            msgJson: msgJson
        ) { [weak self] success, err in
            Task { @MainActor in
                guard let self = self else { return }
                if success {
                    self.handleSyncSuccess()
                    completion?(true)
                } else {
                    if let err = err {
                        self.handleSyncFailure(NSError(domain: "RedisSync", code: -1, userInfo: [NSLocalizedDescriptionKey: err]))
                    }
                    completion?(false)
                }
            }
        }
    }
    
    // Backward compatibility alias
    public func publishAlarmChange(action: SyncAction, alarm: AlarmItem? = nil, allAlarms: [AlarmItem]? = nil) {
        pushAlarmsToRedis(allAlarms ?? AlarmStore.shared.alarms, action: action, triggeredAlarm: alarm)
    }
    
    private func sendSetAndPublish(
        host: String,
        port: Int,
        password: String,
        useTLS: Bool,
        dataKey: String,
        containerJson: String,
        channel: String,
        msgJson: String,
        completion: @escaping @Sendable (Bool, String?) -> Void
    ) {
        let params: NWParameters = useTLS ? .tls : .tcp
        let endpointHost = NWEndpoint.Host(host)
        let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) ?? 6379
        
        let conn = NWConnection(host: endpointHost, port: endpointPort, using: params)
        let flag = AtomicFlag()
        
        let finishOnce: @Sendable (Bool, String?) -> Void = { success, msg in
            flag.executeOnce {
                conn.cancel()
                completion(success, msg)
            }
        }
        
        // 6 second timeout
        DispatchQueue.global().asyncAfter(deadline: .now() + 6.0) {
            finishOnce(false, "Push connection timed out")
        }
        
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if !password.isEmpty {
                    let authCmd = Self.makeRespCommand(["AUTH", password])
                    conn.send(content: authCmd, completion: .contentProcessed { authErr in
                        if let authErr = authErr {
                            finishOnce(false, authErr.localizedDescription)
                            return
                        }
                        Self.sendSetAndPublishPayload(conn: conn, dataKey: dataKey, containerJson: containerJson, channel: channel, msgJson: msgJson, finish: finishOnce)
                    })
                } else {
                    Self.sendSetAndPublishPayload(conn: conn, dataKey: dataKey, containerJson: containerJson, channel: channel, msgJson: msgJson, finish: finishOnce)
                }
            case .failed(let error):
                finishOnce(false, error.localizedDescription)
            default:
                break
            }
        }
        
        conn.start(queue: .global(qos: .userInitiated))
    }
    
    nonisolated private static func sendSetAndPublishPayload(
        conn: NWConnection,
        dataKey: String,
        containerJson: String,
        channel: String,
        msgJson: String,
        finish: @escaping @Sendable (Bool, String?) -> Void
    ) {
        var combined = Data()
        combined.append(makeRespCommand(["SET", dataKey, containerJson]))
        combined.append(makeRespCommand(["PUBLISH", channel, msgJson]))
        
        conn.send(content: combined, completion: .contentProcessed { error in
            if let error = error {
                finish(false, error.localizedDescription)
            } else {
                finish(true, nil)
            }
        })
    }
    
    // MARK: - Persistent Key-Value Pull (GET)
    
    public func pullLatestFromRedis(completion: (@Sendable (Bool) -> Void)? = nil) {
        guard settings.isEnabled, !settings.email.isEmpty else {
            completion?(false)
            return
        }
        guard !isPullingInProgress else {
            completion?(false)
            return
        }
        
        isPullingInProgress = true
        isSyncing = true
        
        let hostStr = serverHost
        let portInt = serverPort
        let password = serverPassword
        let useTLS = serverUseTLS
        let dataKey = settings.activeDataKey
        
        fetchRedisBulkString(
            host: hostStr,
            port: portInt,
            password: password,
            useTLS: useTLS,
            key: dataKey
        ) { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }
                self.isPullingInProgress = false
                self.isSyncing = false
                
                switch result {
                case .success(let payloadData):
                    if let data = payloadData {
                        // Decode RemoteSyncContainer or fallback [AlarmItem]
                        if let container = try? JSONDecoder().decode(RemoteSyncContainer.self, from: data) {
                            AlarmStore.shared.mergeRemoteAlarms(
                                container.alarms,
                                remoteLastUpdated: container.lastUpdated,
                                remoteDeviceId: container.deviceId,
                                remoteDeletedIds: container.deletedAlarmIds
                            )
                        } else if let legacyAlarms = try? JSONDecoder().decode([AlarmItem].self, from: data) {
                            AlarmStore.shared.mergeRemoteAlarms(legacyAlarms)
                        }
                    } else {
                        // Key does not exist in Redis yet: seed Redis with local alarms
                        if !AlarmStore.shared.alarms.isEmpty {
                            self.pushAlarmsToRedis(AlarmStore.shared.alarms, action: .syncAll)
                        }
                    }
                    
                    self.handleSyncSuccess()
                    completion?(true)
                    
                case .failure(let error):
                    self.handleSyncFailure(error)
                    completion?(false)
                }
            }
        }
    }
    
    private func fetchRedisBulkString(
        host: String,
        port: Int,
        password: String,
        useTLS: Bool,
        key: String,
        completion: @escaping @Sendable (Result<Data?, Error>) -> Void
    ) {
        let params: NWParameters = useTLS ? .tls : .tcp
        let endpointHost = NWEndpoint.Host(host)
        let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) ?? 6379
        
        let conn = NWConnection(host: endpointHost, port: endpointPort, using: params)
        let flag = AtomicFlag()
        
        let finishOnce: @Sendable (Result<Data?, Error>) -> Void = { result in
            flag.executeOnce {
                conn.cancel()
                completion(result)
            }
        }
        
        // 6-second timeout so app is 99% offline and non-blocking
        DispatchQueue.global().asyncAfter(deadline: .now() + 6.0) {
            finishOnce(.failure(NSError(domain: "RedisSync", code: -1, userInfo: [NSLocalizedDescriptionKey: "Sync request timed out"])))
        }
        
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if !password.isEmpty {
                    let authCmd = Self.makeRespCommand(["AUTH", password])
                    conn.send(content: authCmd, completion: .contentProcessed { authErr in
                        if let authErr = authErr {
                            finishOnce(.failure(authErr))
                            return
                        }
                        // Send GET
                        Self.sendGetAndReadBulkString(conn: conn, key: key, finish: finishOnce)
                    })
                } else {
                    Self.sendGetAndReadBulkString(conn: conn, key: key, finish: finishOnce)
                }
            case .failed(let error):
                finishOnce(.failure(error))
            default:
                break
            }
        }
        
        conn.start(queue: .global(qos: .userInitiated))
    }
    
    nonisolated private static func sendGetAndReadBulkString(
        conn: NWConnection,
        key: String,
        finish: @escaping @Sendable (Result<Data?, Error>) -> Void
    ) {
        let getCmd = makeRespCommand(["GET", key])
        conn.send(content: getCmd, completion: .contentProcessed { sendErr in
            if let sendErr = sendErr {
                finish(.failure(sendErr))
                return
            }
            
            // Read bulk string response
            let bufferBox = ResponseBufferBox()
            receiveRemainingBulkString(conn: conn, bufferBox: bufferBox, finish: finish)
        })
    }
    
    nonisolated private static func receiveRemainingBulkString(
        conn: NWConnection,
        bufferBox: ResponseBufferBox,
        finish: @escaping @Sendable (Result<Data?, Error>) -> Void
    ) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, context, isComplete, error in
            if let error = error {
                finish(.failure(error))
                return
            }
            
            if let chunk = data {
                bufferBox.append(chunk)
            }
            
            let buffer = bufferBox.snapshot()
            let crlf = Data([0x0D, 0x0A])
            
            // 1. Check for error starting with '-'
            if buffer.starts(with: [0x2D]) {
                if let crlfRange = buffer.range(of: crlf) {
                    let errStr = String(data: buffer.subdata(in: 1..<crlfRange.lowerBound), encoding: .utf8) ?? "Unknown Redis Error"
                    finish(.failure(NSError(domain: "Redis", code: -1, userInfo: [NSLocalizedDescriptionKey: errStr])))
                    return
                }
            }
            
            // 2. Check for bulk string starting with '$'
            if buffer.starts(with: [0x24]) {
                if let crlfRange = buffer.range(of: crlf) {
                    let lenData = buffer.subdata(in: 1..<crlfRange.lowerBound)
                    if let lenStr = String(data: lenData, encoding: .utf8), let length = Int(lenStr) {
                        // Key not found in Redis
                        if length == -1 {
                            finish(.success(nil))
                            return
                        }
                        
                        let dataStart = crlfRange.upperBound
                        let dataEnd = dataStart + length
                        if buffer.count >= dataEnd {
                            let payload = buffer.subdata(in: dataStart..<dataEnd)
                            finish(.success(payload))
                            return
                        }
                    }
                }
            }
            
            if isComplete {
                finish(.failure(NSError(domain: "Redis", code: -1, userInfo: [NSLocalizedDescriptionKey: "Incomplete Redis response"])))
            } else {
                receiveRemainingBulkString(conn: conn, bufferBox: bufferBox, finish: finish)
            }
        }
    }
    
    // MARK: - .env Loader
    
    private func loadDotEnv() -> [String: String] {
        var result: [String: String] = [:]
        
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

final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    
    func executeOnce(_ action: () -> Void) {
        lock.lock()
        if !flag {
            flag = true
            lock.unlock()
            action()
        } else {
            lock.unlock()
        }
    }
}

final class ResponseBufferBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    
    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }
    
    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
