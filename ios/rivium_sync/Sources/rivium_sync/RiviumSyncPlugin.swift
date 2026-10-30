import Flutter
import UIKit
import Combine
import RiviumSync

public class RiviumSyncPlugin: NSObject, FlutterPlugin {
    private var channel: FlutterMethodChannel?
    private var collectionEventChannel: FlutterEventChannel?
    private var documentEventChannel: FlutterEventChannel?
    private var queryEventChannel: FlutterEventChannel?

    private var listeners: [String: ListenerRegistration] = [:]
    /// Forwards the sync state and pending count to Dart (RiviumSync.onSyncState / onPendingCount).
    private var offlineStateObservers = Set<AnyCancellable>()

    // Event sinks for streaming updates to Flutter
    // One stream per event channel: Flutter keeps a single active stream per channel, so every listener of a kind
    // shares it and each event carries its listenerId (the Dart side hands it to the right listener).
    private var collectionEventSink: FlutterEventSink?
    private var documentEventSink: FlutterEventSink?
    private var queryEventSink: FlutterEventSink?

    // Stream handlers
    private var collectionStreamHandler: RiviumSyncStreamHandler?
    private var documentStreamHandler: RiviumSyncStreamHandler?
    private var queryStreamHandler: RiviumSyncStreamHandler?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "co.rivium.sync/rivium_sync", binaryMessenger: registrar.messenger())
        let instance = RiviumSyncPlugin()
        instance.channel = channel

        // Set up event channels
        instance.collectionEventChannel = FlutterEventChannel(name: "co.rivium.sync/collection_events", binaryMessenger: registrar.messenger())
        instance.documentEventChannel = FlutterEventChannel(name: "co.rivium.sync/document_events", binaryMessenger: registrar.messenger())
        instance.queryEventChannel = FlutterEventChannel(name: "co.rivium.sync/query_events", binaryMessenger: registrar.messenger())

        // Create stream handlers
        instance.collectionStreamHandler = RiviumSyncStreamHandler { instance.collectionEventSink = $0 }
        instance.documentStreamHandler = RiviumSyncStreamHandler { instance.documentEventSink = $0 }
        instance.queryStreamHandler = RiviumSyncStreamHandler { instance.queryEventSink = $0 }

        instance.collectionEventChannel?.setStreamHandler(instance.collectionStreamHandler)
        instance.documentEventChannel?.setStreamHandler(instance.documentStreamHandler)
        instance.queryEventChannel?.setStreamHandler(instance.queryStreamHandler)

        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "init":
            handleInit(call, result: result)
        case "connect":
            handleConnect(result: result)
        case "disconnect":
            RiviumSync.shared?.disconnect()
            result(nil)
        case "setUserToken":
            handleSetUserToken(call, result: result)
        case "isConnected":
            result(RiviumSync.shared?.isConnected ?? false)
        case "isAwaitingUserToken":
            result(RiviumSync.shared?.isAwaitingUserToken ?? false)

        // Database operations
        case "listDatabases":
            handleListDatabases(result: result)
        case "createDatabase":
            handleCreateDatabase(call, result: result)
        case "deleteDatabase":
            handleDeleteDatabase(call, result: result)

        // Collection operations
        case "listCollections":
            handleListCollections(call, result: result)
        case "createCollection":
            handleCreateCollection(call, result: result)
        case "deleteCollection":
            handleDeleteCollection(call, result: result)

        // Document operations
        case "addDocument":
            handleAddDocument(call, result: result)
        case "getDocument":
            handleGetDocument(call, result: result)
        case "getAllDocuments":
            handleGetAllDocuments(call, result: result)
        case "updateDocument":
            handleUpdateDocument(call, result: result)
        case "setDocument":
            handleSetDocument(call, result: result)
        case "deleteDocument":
            handleDeleteDocument(call, result: result)
        case "queryDocuments":
            handleQueryDocuments(call, result: result)

        // Listeners
        case "listenCollection":
            handleListenCollection(call, result: result)
        case "removeCollectionListener":
            handleRemoveListener(call, result: result)
        case "listenDocument":
            handleListenDocument(call, result: result)
        case "removeDocumentListener":
            handleRemoveListener(call, result: result)
        case "listenQuery":
            handleListenQuery(call, result: result)
        case "removeQueryListener":
            handleRemoveListener(call, result: result)

        // Batch operations
        case "executeBatch":
            handleExecuteBatch(call, result: result)

        // Offline persistence operations
        case "getSyncState":
            handleGetSyncState(result: result)
        case "getPendingCount":
            handleGetPendingCount(result: result)
        case "forceSyncNow":
            handleForceSyncNow(result: result)
        case "clearOfflineCache":
            handleClearOfflineCache(result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// Replace the signed user token. Dart fetches it from the app's own backend
    /// and pushes it down, which keeps the bridge one-way.
    private func handleSetUserToken(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let sync = RiviumSync.shared else {
            result(FlutterError(code: "notInitialized", message: "Call init before setUserToken", details: nil))
            return
        }
        let args = call.arguments as? [String: Any]
        sync.userTokens.set(args?["token"] as? String)
        result(nil)
    }

    private func handleInit(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let apiKey = args["apiKey"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "apiKey required", details: nil))
            return
        }

        // Parse conflict strategy
        var conflictStrategy: ConflictStrategy = .serverWins
        if let strategyString = args["conflictStrategy"] as? String {
            switch strategyString {
            case "clientWins": conflictStrategy = .clientWins
            case "merge": conflictStrategy = .merge
            case "manual": conflictStrategy = .manual
            default: conflictStrategy = .serverWins
            }
        }

        let builder = RiviumSyncConfigBuilder(apiKey: apiKey)
            .debugMode(args["debugMode"] as? Bool ?? false)
            .autoReconnect(args["autoReconnect"] as? Bool ?? true)
            .offlineEnabled(args["offlineEnabled"] as? Bool ?? false)
            .syncOnReconnect(args["syncOnReconnect"] as? Bool ?? true)
            .conflictStrategy(conflictStrategy)
            // Report this plugin (flutter/<version>) in the X-Rivium-SDK header.
            .wrapperSdk(name: args["wrapperSdkName"] as? String, version: args["wrapperSdkVersion"] as? String)
        // User identity for Security Rules (auth.uid). A signed token is trustworthy; the plain userId is not.
        if let userId = args["userId"] as? String { _ = builder.userId(userId) }
        if let userToken = args["userToken"] as? String { _ = builder.userToken(userToken) }
        if let sizeMb = args["offlineCacheSizeMb"] as? Int { _ = builder.offlineCacheSizeMb(sizeMb) }

        // A local Rivium Sync server (plain HTTP, realtime without TLS). Checked here too: the native builder
        // stops the app on a bad value.
        if let host = (args["emulatorHost"] as? String)?.trimmingCharacters(in: .whitespaces) {
            let port = args["emulatorPort"] as? Int ?? 3006
            guard !host.isEmpty, !host.contains("/"), !host.contains(":"), (1...65535).contains(port) else {
                result(FlutterError(code: "INVALID_ARGS", message: "emulatorHost is a host name or IP address, without scheme or port; emulatorPort 1-65535", details: nil))
                return
            }
            _ = builder.useEmulator(host: host, port: port)
        }

        let config = builder.build()

        RiviumSync.initialize(config: config)

        RiviumSync.shared?.delegate = self
        // Queued writes the server refuses (offline persistence only; without it nothing is queued).
        RiviumSync.shared?.removeSyncListener(self)
        RiviumSync.shared?.addSyncListener(self)
        // Sync state and pending count as they change (offline persistence only; no publishers otherwise).
        offlineStateObservers.removeAll()
        RiviumSync.shared?.syncStatePublisher?.receive(on: DispatchQueue.main).sink { [weak self] state in
            self?.channel?.invokeMethod("onSyncState", arguments: Self.syncStateName(state))
        }.store(in: &offlineStateObservers)
        RiviumSync.shared?.pendingCountPublisher?.receive(on: DispatchQueue.main).sink { [weak self] count in
            self?.channel?.invokeMethod("onPendingCount", arguments: count)
        }.store(in: &offlineStateObservers)
        // The project requires a user token and none is set yet: connect() is
        // parked, not failed. The SDK connects when setUserToken supplies one.
        RiviumSync.shared?.onAwaitingUserToken = { [weak self] in
            DispatchQueue.main.async {
                self?.channel?.invokeMethod("onAwaitingUserToken", arguments: nil)
            }
        }

        result(nil)
    }

    private func handleConnect(result: @escaping FlutterResult) {
        RiviumSync.shared?.connect { connectResult in
            switch connectResult {
            case .success:
                result(nil)
            case .failure(let error):
                result(Self.flutterError(error, code: "CONNECTION_ERROR"))
            }
        }
    }

    private func handleListDatabases(result: @escaping FlutterResult) {
        Task {
            do {
                let databases = try await RiviumSync.shared?.listDatabases() ?? []
                let data = databases.map { db in
                    return [
                        "id": db.id,
                        "name": db.name,
                        "createdAt": db.createdAt,
                        "updatedAt": db.updatedAt
                    ] as [String: Any]
                }
                DispatchQueue.main.async {
                    result(data)
                }
            } catch {
                DispatchQueue.main.async {
                    result(Self.flutterError(error, code: "DATABASE_ERROR"))
                }
            }
        }
    }

    private func handleCreateDatabase(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let name = args["name"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "name required", details: nil))
            return
        }

        Task {
            do {
                let db = try await RiviumSync.shared?.createDatabase(name: name)
                DispatchQueue.main.async {
                    result([
                        "id": db?.id ?? "",
                        "name": db?.name ?? ""
                    ])
                }
            } catch {
                DispatchQueue.main.async {
                    result(Self.flutterError(error, code: "DATABASE_ERROR"))
                }
            }
        }
    }

    private func handleDeleteDatabase(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let databaseId = args["databaseId"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "databaseId required", details: nil))
            return
        }

        Task {
            do {
                try await RiviumSync.shared?.deleteDatabase(databaseId: databaseId)
                DispatchQueue.main.async {
                    result(nil)
                }
            } catch {
                DispatchQueue.main.async {
                    result(Self.flutterError(error, code: "DATABASE_ERROR"))
                }
            }
        }
    }

    private func handleListCollections(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let databaseId = args["databaseId"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "databaseId required", details: nil))
            return
        }

        Task {
            do {
                let collections = try await RiviumSync.shared?.database(databaseId).listCollections() ?? []
                let data = collections.map { col in
                    return [
                        "id": col.id,
                        "name": col.name,
                        "databaseId": col.databaseId,
                        "documentCount": col.documentCount,
                        "createdAt": col.createdAt,
                        "updatedAt": col.updatedAt
                    ] as [String: Any]
                }
                DispatchQueue.main.async {
                    result(data)
                }
            } catch {
                DispatchQueue.main.async {
                    result(Self.flutterError(error, code: "COLLECTION_ERROR"))
                }
            }
        }
    }

    private func handleCreateCollection(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let databaseId = args["databaseId"] as? String,
              let name = args["name"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "databaseId and name required", details: nil))
            return
        }

        Task {
            do {
                let col = try await RiviumSync.shared?.database(databaseId).createCollection(name: name)
                DispatchQueue.main.async {
                    result([
                        "id": col?.id ?? "",
                        "name": col?.name ?? "",
                        "databaseId": databaseId
                    ])
                }
            } catch {
                DispatchQueue.main.async {
                    result(Self.flutterError(error, code: "COLLECTION_ERROR"))
                }
            }
        }
    }

    private func handleDeleteCollection(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let databaseId = args["databaseId"] as? String,
              let collectionId = args["collectionId"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "databaseId and collectionId required", details: nil))
            return
        }

        Task {
            do {
                try await RiviumSync.shared?.database(databaseId).deleteCollection(collectionId: collectionId)
                DispatchQueue.main.async {
                    result(nil)
                }
            } catch {
                DispatchQueue.main.async {
                    result(Self.flutterError(error, code: "COLLECTION_ERROR"))
                }
            }
        }
    }

    private func handleAddDocument(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let databaseId = args["databaseId"] as? String,
              let collectionId = args["collectionId"] as? String,
              let data = args["data"] as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGS", message: "databaseId, collectionId, data required", details: nil))
            return
        }

        Task {
            do {
                let doc = try await RiviumSync.shared?.database(databaseId).collection(collectionId).add(data: data)
                DispatchQueue.main.async {
                    result(doc?.toDict())
                }
            } catch {
                DispatchQueue.main.async {
                    result(Self.flutterError(error, code: "DOCUMENT_ERROR"))
                }
            }
        }
    }

    private func handleGetDocument(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let databaseId = args["databaseId"] as? String,
              let collectionId = args["collectionId"] as? String,
              let documentId = args["documentId"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "databaseId, collectionId, documentId required", details: nil))
            return
        }

        Task {
            do {
                let doc = try await RiviumSync.shared?.database(databaseId).collection(collectionId).get(documentId: documentId)
                DispatchQueue.main.async {
                    result(doc?.toDict())
                }
            } catch {
                DispatchQueue.main.async {
                    result(Self.flutterError(error, code: "DOCUMENT_ERROR"))
                }
            }
        }
    }

    private func handleGetAllDocuments(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let databaseId = args["databaseId"] as? String,
              let collectionId = args["collectionId"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "databaseId, collectionId required", details: nil))
            return
        }

        Task {
            do {
                let docs = try await RiviumSync.shared?.database(databaseId).collection(collectionId).getAll() ?? []
                DispatchQueue.main.async {
                    result(docs.map { $0.toDict() })
                }
            } catch {
                DispatchQueue.main.async {
                    result(Self.flutterError(error, code: "DOCUMENT_ERROR"))
                }
            }
        }
    }

    private func handleUpdateDocument(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let databaseId = args["databaseId"] as? String,
              let collectionId = args["collectionId"] as? String,
              let documentId = args["documentId"] as? String,
              let data = args["data"] as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGS", message: "databaseId, collectionId, documentId, data required", details: nil))
            return
        }

        Task {
            do {
                let doc = try await RiviumSync.shared?.database(databaseId).collection(collectionId).update(documentId: documentId, data: data)
                DispatchQueue.main.async {
                    result(doc?.toDict())
                }
            } catch {
                DispatchQueue.main.async {
                    result(Self.flutterError(error, code: "DOCUMENT_ERROR"))
                }
            }
        }
    }

    private func handleSetDocument(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let databaseId = args["databaseId"] as? String,
              let collectionId = args["collectionId"] as? String,
              let documentId = args["documentId"] as? String,
              let data = args["data"] as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGS", message: "databaseId, collectionId, documentId, data required", details: nil))
            return
        }

        // Replace by default; merge only when asked.
        let merge = args["merge"] as? Bool ?? false

        Task {
            do {
                let doc = try await RiviumSync.shared?.database(databaseId).collection(collectionId).set(documentId: documentId, data: data, merge: merge)
                DispatchQueue.main.async {
                    result(doc?.toDict())
                }
            } catch {
                DispatchQueue.main.async {
                    result(Self.flutterError(error, code: "DOCUMENT_ERROR"))
                }
            }
        }
    }

    private func handleDeleteDocument(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let databaseId = args["databaseId"] as? String,
              let collectionId = args["collectionId"] as? String,
              let documentId = args["documentId"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "databaseId, collectionId, documentId required", details: nil))
            return
        }

        Task {
            do {
                try await RiviumSync.shared?.database(databaseId).collection(collectionId).delete(documentId: documentId)
                DispatchQueue.main.async {
                    result(nil)
                }
            } catch {
                DispatchQueue.main.async {
                    result(Self.flutterError(error, code: "DOCUMENT_ERROR"))
                }
            }
        }
    }

    private func handleQueryDocuments(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let databaseId = args["databaseId"] as? String,
              let collectionId = args["collectionId"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "databaseId, collectionId required", details: nil))
            return
        }

        Task {
            do {
                let query = Self.buildQuery(args, databaseId: databaseId, collectionId: collectionId)

                let docs = try await query?.get() ?? []
                DispatchQueue.main.async {
                    result(docs.map { $0.toDict() })
                }
            } catch {
                DispatchQueue.main.async {
                    result(Self.flutterError(error, code: "QUERY_ERROR"))
                }
            }
        }
    }

    private func handleListenCollection(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let databaseId = args["databaseId"] as? String,
              let collectionId = args["collectionId"] as? String,
              let listenerId = args["listenerId"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "databaseId, collectionId, listenerId required", details: nil))
            return
        }

        let registration = RiviumSync.shared?.database(databaseId).collection(collectionId).listen(callback: { [weak self] docs in
            DispatchQueue.main.async {
                self?.collectionEventSink?([
                    "listenerId": listenerId,
                    "documents": docs.map { $0.toDict() }
                ])
            }
        }, onError: { [weak self] error in
            DispatchQueue.main.async {
                self?.collectionEventSink?(["listenerId": listenerId, "error": Self.listenerErrorMap(error)])
            }
        })

        if let registration = registration {
            listeners[listenerId] = registration
        }

        result(nil)
    }

    private func handleListenDocument(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let databaseId = args["databaseId"] as? String,
              let collectionId = args["collectionId"] as? String,
              let documentId = args["documentId"] as? String,
              let listenerId = args["listenerId"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "databaseId, collectionId, documentId, listenerId required", details: nil))
            return
        }

        let registration = RiviumSync.shared?.database(databaseId).collection(collectionId).listenDocument(documentId: documentId, callback: { [weak self] doc in
            DispatchQueue.main.async {
                self?.documentEventSink?([
                    "listenerId": listenerId,
                    "document": doc?.toDict() as Any
                ])
            }
        }, onError: { [weak self] error in
            DispatchQueue.main.async {
                self?.documentEventSink?(["listenerId": listenerId, "error": Self.listenerErrorMap(error)])
            }
        })

        if let registration = registration {
            listeners[listenerId] = registration
        }

        result(nil)
    }

    private func handleListenQuery(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let databaseId = args["databaseId"] as? String,
              let collectionId = args["collectionId"] as? String,
              let listenerId = args["listenerId"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "databaseId, collectionId, listenerId required", details: nil))
            return
        }

        let query = Self.buildQuery(args, databaseId: databaseId, collectionId: collectionId)
        let registration = query?.listen(callback: { [weak self] docs in
            DispatchQueue.main.async {
                self?.queryEventSink?([
                    "listenerId": listenerId,
                    "documents": docs.map { $0.toDict() }
                ])
            }
        }, onError: { [weak self] error in
            DispatchQueue.main.async {
                self?.queryEventSink?(["listenerId": listenerId, "error": Self.listenerErrorMap(error)])
            }
        })

        if let registration = registration {
            listeners[listenerId] = registration
        }

        result(nil)
    }

    /// The query described by the call's filters / orderBy / limit / offset.
    private static func buildQuery(_ args: [String: Any], databaseId: String, collectionId: String) -> SyncQuery? {
        var query = RiviumSync.shared?.database(databaseId).collection(collectionId).query()

        if let filters = args["filters"] as? [[String: Any]] {
            for filter in filters {
                if let field = filter["field"] as? String,
                   let opString = filter["operator"] as? String {
                    let value = filter["value"]
                    let op: QueryOperator
                    switch opString {
                    case "==": op = .equal
                    case "!=": op = .notEqual
                    case ">": op = .greaterThan
                    case ">=": op = .greaterThanOrEqual
                    case "<": op = .lessThan
                    case "<=": op = .lessThanOrEqual
                    case "array-contains": op = .arrayContains
                    case "in": op = .in
                    case "not-in": op = .notIn
                    default: op = .equal
                    }
                    query = query?.where(field, op, value)
                }
            }
        }

        if let orderBy = args["orderBy"] as? [String: Any],
           let field = orderBy["field"] as? String {
            let direction: OrderDirection = orderBy["direction"] as? String == "desc" ? .descending : .ascending
            query = query?.orderBy(field, direction: direction)
        }

        if let limit = args["limit"] as? Int {
            query = query?.limit(limit)
        }

        if let offset = args["offset"] as? Int {
            query = query?.offset(offset)
        }

        return query
    }

    /// The error for a failed call, typed on the Dart side (RiviumSyncError.fromPlatformException): the HTTP status
    /// the server answered with in `details.statusCode`, and `query_not_allowed` with its fields.
    private static func flutterError(_ error: Error, code: String) -> FlutterError {
        if case RiviumSyncError.queryNotAllowed(let message, let fields) = error {
            return FlutterError(code: "query_not_allowed", message: message, details: ["fields": fields, "statusCode": 403])
        }
        let status = (error as? RiviumSyncError)?.statusCode
        return FlutterError(code: code, message: error.localizedDescription,
                            details: status.map { ["statusCode": $0] })
    }

    /// The error map of a refused queued write, read by RiviumSyncError.fromMap on the Dart side.
    private static func rejectionErrorMap(_ error: Error) -> [String: Any] {
        let flutter = flutterError(error, code: "DOCUMENT_ERROR")
        var map: [String: Any] = ["code": flutter.code, "message": flutter.message ?? "The server refused the write"]
        if let details = flutter.details as? [String: Any] {
            map.merge(details) { _, new in new }
        }
        return map
    }

    /// The error map a listener event carries when the listener stopped (read by RiviumSyncListenerError.fromMap):
    /// `query_not_allowed` with its fields, `listener_revoked`, `permission_denied`, else UNKNOWN_ERROR.
    private static func listenerErrorMap(_ error: Error) -> [String: Any] {
        guard let syncError = error as? RiviumSyncError else {
            return ["code": "UNKNOWN_ERROR", "message": error.localizedDescription]
        }
        switch syncError {
        case .queryNotAllowed(let message, let fields):
            return ["code": "query_not_allowed", "message": message, "fields": fields, "statusCode": 403]
        case .listenerRevoked(let message):
            return ["code": "listener_revoked", "message": message]
        case .permissionError(let message):
            return ["code": "permission_denied", "message": message, "statusCode": 403]
        default:
            return ["code": syncError.code ?? "UNKNOWN_ERROR", "message": syncError.localizedDescription]
        }
    }

    private func handleExecuteBatch(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let operations = args["operations"] as? [[String: Any]] else {
            result(FlutterError(code: "INVALID_ARGS", message: "operations required", details: nil))
            return
        }

        Task {
            do {
                guard let batch = RiviumSync.shared?.batch() else {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "NOT_INITIALIZED", message: "RiviumSync not initialized", details: nil))
                    }
                    return
                }

                for op in operations {
                    guard let type = op["type"] as? String,
                          let databaseId = op["databaseId"] as? String,
                          let collectionId = op["collectionId"] as? String else {
                        continue
                    }

                    let documentId = op["documentId"] as? String
                    let data = op["data"] as? [String: Any]
                    let merge = op["merge"] as? Bool ?? false

                    guard let collection = RiviumSync.shared?.database(databaseId).collection(collectionId) else {
                        continue
                    }

                    switch type {
                    case "set":
                        if let documentId = documentId, let data = data {
                            batch.set(collection, documentId: documentId, data: data, merge: merge)
                        }
                    case "update":
                        if let documentId = documentId, let data = data {
                            batch.update(collection, documentId: documentId, data: data)
                        }
                    case "delete":
                        if let documentId = documentId {
                            batch.delete(collection, documentId: documentId)
                        }
                    case "create":
                        if let data = data {
                            batch.create(collection, data: data)
                        }
                    default:
                        break
                    }
                }

                try await batch.commit()
                DispatchQueue.main.async {
                    result(nil)
                }
            } catch {
                DispatchQueue.main.async {
                    result(Self.flutterError(error, code: "BATCH_ERROR"))
                }
            }
        }
    }

    private func handleRemoveListener(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let listenerId = args["listenerId"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "listenerId required", details: nil))
            return
        }

        listeners[listenerId]?.remove()
        listeners.removeValue(forKey: listenerId)
        result(nil)
    }

    // MARK: - Offline Persistence Methods

    private func handleGetSyncState(result: @escaping FlutterResult) {
        result(Self.syncStateName(RiviumSync.shared?.syncState ?? .idle))
    }

    private static func syncStateName(_ state: SyncState) -> String {
        switch state {
        case .idle: return "idle"
        case .syncing: return "syncing"
        case .offline: return "offline"
        case .error: return "error"
        }
    }

    private func handleGetPendingCount(result: @escaping FlutterResult) {
        let count = RiviumSync.shared?.pendingCount ?? 0
        result(count)
    }

    private func handleForceSyncNow(result: @escaping FlutterResult) {
        RiviumSync.shared?.forceSyncNow()
        result(nil)
    }

    private func handleClearOfflineCache(result: @escaping FlutterResult) {
        RiviumSync.shared?.clearOfflineCache()
        result(nil)
    }
}

// MARK: - Stream Handler for EventChannel
/// One shared stream per channel (see the event sinks above); listen / cancel just set or clear the sink.
private class RiviumSyncStreamHandler: NSObject, FlutterStreamHandler {
    private let setSink: (FlutterEventSink?) -> Void

    init(setSink: @escaping (FlutterEventSink?) -> Void) {
        self.setSink = setSink
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        setSink(events)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        setSink(nil)
        return nil
    }
}

// MARK: - SyncListener
/// Forwards the sync engine's rejections to Dart (RiviumSync.onDocumentRejected). The other events keep their
/// default empty implementations.
extension RiviumSyncPlugin: SyncEngine.SyncListener {
    public func onDocumentRejected(documentId: String, operation: OperationType, error: Error) {
        let event: [String: Any] = [
            "documentId": documentId,
            "operation": operation.rawValue,
            "error": Self.rejectionErrorMap(error)
        ]
        DispatchQueue.main.async { [weak self] in
            self?.channel?.invokeMethod("onDocumentRejected", arguments: event)
        }
    }
}

// MARK: - RiviumSyncDelegate
extension RiviumSyncPlugin: RiviumSyncDelegate {
    public func riviumSyncDidConnect(_ riviumSync: RiviumSync) {
        channel?.invokeMethod("onConnectionState", arguments: true)
    }

    public func riviumSync(_ riviumSync: RiviumSync, didDisconnectWithError error: Error?) {
        channel?.invokeMethod("onConnectionState", arguments: false)
    }

    public func riviumSync(_ riviumSync: RiviumSync, didFailToConnectWithError error: Error) {
        channel?.invokeMethod("onError", arguments: [
            "code": "connectionError",
            "message": error.localizedDescription
        ])
    }
}
