import Foundation
import CocoaMQTT

/// MQTT Manager for realtime data synchronization
internal class MqttManager: NSObject {
    private let config: RiviumSyncConfig
    private let apiClient: ApiClient
    private var mqtt: CocoaMQTT?
    private var mqtt5: CocoaMQTT5?
    private var mqttToken: String?
    /// Maps topic -> [handleId -> callback]
    private var subscriptions: [String: [UUID: (String) -> Void]] = [:]
    private let subscriptionsQueue = DispatchQueue(label: "co.rivium.subscriptions")
    /// Stable clientId per instance — prevents orphaned EMQX sessions on reconnect
    private let clientId: String = "rivium_sync_\(UUID().uuidString.prefix(8))"
    /// Guard against concurrent connect() calls
    private var isConnecting = false

    weak var delegate: MqttManagerDelegate?

    /// Callback for connection state changes
    var onConnectionStateChanged: ((Bool) -> Void)?

    protocol MqttManagerDelegate: AnyObject {
        func mqttManagerDidConnect(_ manager: MqttManager)
        func mqttManager(_ manager: MqttManager, didDisconnectWithError error: Error?)
        func mqttManager(_ manager: MqttManager, didReceiveMessage message: String, topic: String)
    }

    init(config: RiviumSyncConfig, apiClient: ApiClient) {
        self.config = config
        self.apiClient = apiClient
        super.init()
    }

    var isConnected: Bool {
        if config.mqttUseTls {
            return mqtt5?.connState == .connected
        } else {
            return mqtt?.connState == .connected
        }
    }

    func connect(completion: @escaping (Result<Void, Error>) -> Void) {
        if isConnected {
            completion(.success(()))
            return
        }

        // Prevent concurrent connect() calls from creating duplicate MQTT clients
        if isConnecting {
            RiviumSyncLogger.d("Connect already in progress - skipping")
            return
        }
        isConnecting = true

        // Fetch MQTT token from API first
        Task {
            do {
                RiviumSyncLogger.d("Fetching MQTT token...")
                let tokenResponse = try await apiClient.fetchMqttToken()
                self.mqttToken = tokenResponse.token
                RiviumSyncLogger.d("MQTT token obtained")
                self.connectWithToken(token: tokenResponse.token, completion: completion)
            } catch {
                self.isConnecting = false
                RiviumSyncLogger.e("Failed to fetch MQTT token", error: error)
                completion(.failure(error))
            }
        }
    }

    private func connectWithToken(token: String, completion: @escaping (Result<Void, Error>) -> Void) {
        RiviumSyncLogger.d("MQTT connecting to \(config.mqttHost):\(config.mqttPort) (TLS: \(config.mqttUseTls))")

        // Close any existing client to prevent orphaned EMQX connections
        mqtt?.disconnect()
        mqtt = nil
        mqtt5?.disconnect()
        mqtt5 = nil

        if config.mqttUseTls {
            let client = CocoaMQTT5(clientID: clientId, host: config.mqttHost, port: UInt16(config.mqttPort))
            client.username = "jwt"
            client.password = token
            client.keepAlive = UInt16(config.keepAliveInterval)
            client.cleanSession = true  // Fresh session — resubscribeAll() handles topic restoration
            client.enableSSL = true
            client.allowUntrustCACertificate = true
            client.autoReconnect = config.autoReconnect
            client.delegate = self

            self.mqtt5 = client
            _ = client.connect()
        } else {
            let client = CocoaMQTT(clientID: clientId, host: config.mqttHost, port: UInt16(config.mqttPort))
            client.username = "jwt"
            client.password = token
            client.keepAlive = UInt16(config.keepAliveInterval)
            client.cleanSession = true  // Fresh session — resubscribeAll() handles topic restoration
            client.autoReconnect = config.autoReconnect
            client.delegate = self

            self.mqtt = client
            _ = client.connect()
        }

        // Store completion for callback on connect
        connectCompletion = completion
    }
    
    private var connectCompletion: ((Result<Void, Error>) -> Void)?
    
    func disconnect() {
        isConnecting = false
        mqtt?.disconnect()
        mqtt5?.disconnect()
        subscriptionsQueue.sync {
            subscriptions.removeAll()
        }
    }

    func subscribe(topic: String, callback: @escaping (String) -> Void) -> SubscriptionHandle {
        let handle = SubscriptionHandle(topic: topic, callback: callback, manager: self)
        RiviumSyncLogger.i("MqttManager.subscribe called for topic: \(topic), handleId: \(handle.id), isConnected: \(isConnected)")

        subscriptionsQueue.sync {
            if subscriptions[topic] == nil {
                subscriptions[topic] = [:]
            }
            subscriptions[topic]?[handle.id] = callback
            RiviumSyncLogger.i("MqttManager.subscribe: Added callback, now \(subscriptions[topic]?.count ?? 0) callbacks for topic")
        }

        if isConnected {
            if config.mqttUseTls {
                mqtt5?.subscribe(topic, qos: .qos1)
                RiviumSyncLogger.i("MqttManager.subscribe: Called mqtt5.subscribe for \(topic)")
            } else {
                mqtt?.subscribe(topic, qos: .qos1)
                RiviumSyncLogger.i("MqttManager.subscribe: Called mqtt.subscribe for \(topic)")
            }
            RiviumSyncLogger.d("Subscribed to MQTT topic: \(topic)")
        } else {
            RiviumSyncLogger.w("MqttManager.subscribe: Not connected, subscription will be pending")
        }

        return handle
    }

    func unsubscribe(handle: SubscriptionHandle) {
        RiviumSyncLogger.i("MqttManager.unsubscribe called for topic: \(handle.topic), handleId: \(handle.id)")
        subscriptionsQueue.sync {
            if var callbacks = subscriptions[handle.topic] {
                RiviumSyncLogger.i("MqttManager.unsubscribe: Found \(callbacks.count) callbacks for topic")
                callbacks.removeValue(forKey: handle.id)
                if callbacks.isEmpty {
                    subscriptions.removeValue(forKey: handle.topic)
                    if config.mqttUseTls {
                        mqtt5?.unsubscribe(handle.topic)
                        RiviumSyncLogger.i("MqttManager.unsubscribe: Called mqtt5.unsubscribe for \(handle.topic)")
                    } else {
                        mqtt?.unsubscribe(handle.topic)
                        RiviumSyncLogger.i("MqttManager.unsubscribe: Called mqtt.unsubscribe for \(handle.topic)")
                    }
                    RiviumSyncLogger.d("Unsubscribed from MQTT topic: \(handle.topic)")
                } else {
                    subscriptions[handle.topic] = callbacks
                    RiviumSyncLogger.i("MqttManager.unsubscribe: Still \(callbacks.count) callbacks remaining")
                }
            } else {
                RiviumSyncLogger.i("MqttManager.unsubscribe: No callbacks found for topic \(handle.topic)")
            }
        }
    }

    private func resubscribeAll() {
        subscriptionsQueue.sync {
            for topic in subscriptions.keys {
                if config.mqttUseTls {
                    mqtt5?.subscribe(topic, qos: .qos1)
                } else {
                    mqtt?.subscribe(topic, qos: .qos1)
                }
                RiviumSyncLogger.d("Resubscribed to topic: \(topic)")
            }
        }
    }
    
    func collectionTopic(databaseId: String, collectionId: String) -> String {
        return "rivium_sync/\(databaseId)/\(collectionId)/changes"
    }
    
    func documentTopic(databaseId: String, collectionId: String, documentId: String) -> String {
        return "rivium_sync/\(databaseId)/\(collectionId)/\(documentId)"
    }
    
    class SubscriptionHandle {
        let id: UUID
        let topic: String
        let callback: (String) -> Void
        weak var manager: MqttManager?

        init(topic: String, callback: @escaping (String) -> Void, manager: MqttManager) {
            self.id = UUID()
            self.topic = topic
            self.callback = callback
            self.manager = manager
        }
    }
}

// MARK: - CocoaMQTTDelegate
extension MqttManager: CocoaMQTTDelegate {
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        isConnecting = false
        if ack == .accept {
            RiviumSyncLogger.i("MQTT connected")
            onConnectionStateChanged?(true)
            delegate?.mqttManagerDidConnect(self)
            connectCompletion?(.success(()))
            connectCompletion = nil
            resubscribeAll()
        } else {
            let error = RiviumSyncError.connectionError("MQTT connection rejected: \(ack)", nil)
            connectCompletion?(.failure(error))
            connectCompletion = nil
        }
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didStateChangeTo state: CocoaMQTTConnState) {
        RiviumSyncLogger.d("MQTT state changed to: \(state)")
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {}
    
    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {}
    
    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
        let topic = message.topic
        guard let payload = message.string else { return }

        RiviumSyncLogger.d("MQTT message on \(topic): \(payload)")

        delegate?.mqttManager(self, didReceiveMessage: payload, topic: topic)

        subscriptionsQueue.sync {
            let callbackCount = subscriptions[topic]?.count ?? 0
            RiviumSyncLogger.i("MqttManager.didReceiveMessage: topic=\(topic), callbackCount=\(callbackCount)")
            if callbackCount == 0 {
                RiviumSyncLogger.w("MqttManager.didReceiveMessage: No callbacks for topic! Available topics: \(Array(subscriptions.keys))")
            }
            subscriptions[topic]?.values.forEach { callback in
                RiviumSyncLogger.i("MqttManager.didReceiveMessage: Invoking callback for topic \(topic)")
                callback(payload)
            }
        }
    }

    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {
        RiviumSyncLogger.d("Subscribed to topics: \(success.allKeys)")
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {
        RiviumSyncLogger.d("Unsubscribed from topics: \(topics)")
    }
    
    func mqttDidPing(_ mqtt: CocoaMQTT) {}
    
    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {}
    
    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        isConnecting = false
        RiviumSyncLogger.w("MQTT disconnected", error: err)
        onConnectionStateChanged?(false)
        delegate?.mqttManager(self, didDisconnectWithError: err)
    }
}

// MARK: - CocoaMQTT5Delegate
extension MqttManager: CocoaMQTT5Delegate {
    func mqtt5(_ mqtt5: CocoaMQTT5, didConnectAck ack: CocoaMQTTCONNACKReasonCode, connAckData: MqttDecodeConnAck?) {
        isConnecting = false
        if ack == .success {
            RiviumSyncLogger.i("MQTT5 connected")
            onConnectionStateChanged?(true)
            delegate?.mqttManagerDidConnect(self)
            connectCompletion?(.success(()))
            connectCompletion = nil
            resubscribeAll()
        } else {
            let error = RiviumSyncError.connectionError("MQTT5 connection rejected: \(ack)", nil)
            connectCompletion?(.failure(error))
            connectCompletion = nil
        }
    }
    
    func mqtt5(_ mqtt5: CocoaMQTT5, didStateChangeTo state: CocoaMQTTConnState) {
        RiviumSyncLogger.d("MQTT5 state changed to: \(state)")
    }
    
    func mqtt5(_ mqtt5: CocoaMQTT5, didPublishMessage message: CocoaMQTT5Message, id: UInt16) {}
    
    func mqtt5(_ mqtt5: CocoaMQTT5, didPublishAck id: UInt16, pubAckData: MqttDecodePubAck?) {}
    
    func mqtt5(_ mqtt5: CocoaMQTT5, didPublishRec id: UInt16, pubRecData: MqttDecodePubRec?) {}
    
    func mqtt5(_ mqtt5: CocoaMQTT5, didReceiveMessage message: CocoaMQTT5Message, id: UInt16, publishData: MqttDecodePublish?) {
        let topic = message.topic
        guard let payload = message.string else { return }

        RiviumSyncLogger.d("MQTT5 message on \(topic): \(payload)")

        delegate?.mqttManager(self, didReceiveMessage: payload, topic: topic)

        subscriptionsQueue.sync {
            subscriptions[topic]?.values.forEach { callback in
                callback(payload)
            }
        }
    }

    func mqtt5(_ mqtt5: CocoaMQTT5, didSubscribeTopics success: NSDictionary, failed: [String], subAckData: MqttDecodeSubAck?) {
        RiviumSyncLogger.d("MQTT5 subscribed to topics: \(success.allKeys)")
    }
    
    func mqtt5(_ mqtt5: CocoaMQTT5, didUnsubscribeTopics topics: [String], unsubAckData: MqttDecodeUnsubAck?) {
        RiviumSyncLogger.d("MQTT5 unsubscribed from topics: \(topics)")
    }
    
    func mqtt5DidPing(_ mqtt5: CocoaMQTT5) {}
    
    func mqtt5DidReceivePong(_ mqtt5: CocoaMQTT5) {}
    
    func mqtt5DidDisconnect(_ mqtt5: CocoaMQTT5, withError err: Error?) {
        isConnecting = false
        RiviumSyncLogger.w("MQTT5 disconnected", error: err)
        onConnectionStateChanged?(false)
        delegate?.mqttManager(self, didDisconnectWithError: err)
    }
    
    func mqtt5(_ mqtt5: CocoaMQTT5, didReceiveDisconnectReasonCode reasonCode: CocoaMQTTDISCONNECTReasonCode) {
        RiviumSyncLogger.w("MQTT5 disconnect reason: \(reasonCode)")
    }
    
    func mqtt5(_ mqtt5: CocoaMQTT5, didReceiveAuthReasonCode reasonCode: CocoaMQTTAUTHReasonCode) {
        RiviumSyncLogger.d("MQTT5 auth reason: \(reasonCode)")
    }
}
