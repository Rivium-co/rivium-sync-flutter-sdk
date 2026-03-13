import Flutter
import UIKit

public class RiviumSyncPlugin: NSObject, FlutterPlugin {
    private var channel: FlutterMethodChannel?
    private var collectionEventChannel: FlutterEventChannel?
    private var documentEventChannel: FlutterEventChannel?
    private var queryEventChannel: FlutterEventChannel?

    private var listeners: [String: ListenerRegistration] = [:]

    // Event sinks for streaming updates to Flutter
    private var collectionEventSinks: [String: FlutterEventSink] = [:]
    private var documentEventSinks: [String: FlutterEventSink] = [:]
    private var queryEventSinks: [String: FlutterEventSink] = [:]

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
        instance.collectionStreamHandler = RiviumSyncStreamHandler(name: "collection", sinks: { instance.collectionEventSinks }, setSink: { id, sink in instance.collectionEventSinks[id] = sink }, removeSink: { id in instance.collectionEventSinks.removeValue(forKey: id) })
        instance.documentStreamHandler = RiviumSyncStreamHandler(name: "document", sinks: { instance.documentEventSinks }, setSink: { id, sink in instance.documentEventSinks[id] = sink }, removeSink: { id in instance.documentEventSinks.removeValue(forKey: id) })
        instance.queryStreamHandler = RiviumSyncStreamHandler(name: "query", sinks: { instance.queryEventSinks }, setSink: { id, sink in instance.queryEventSinks[id] = sink }, removeSink: { id in instance.queryEventSinks.removeValue(forKey: id) })

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
        case "isConnected":
            result(RiviumSync.shared?.isConnected ?? false)

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

        let config = RiviumSyncConfig(
            apiKey: apiKey,
            userId: args["userId"] as? String,
            debugMode: args["debugMode"] as? Bool ?? false,
            autoReconnect: args["autoReconnect"] as? Bool ?? true,
            offlineEnabled: args["offlineEnabled"] as? Bool ?? false,
            offlineCacheSizeMb: args["offlineCacheSizeMb"] as? Int,
            syncOnReconnect: args["syncOnReconnect"] as? Bool ?? true,
            conflictStrategy: conflictStrategy,
            maxSyncRetries: args["maxSyncRetries"] as? Int
        )

        RiviumSync.initialize(config: config)

        RiviumSync.shared?.delegate = self

        result(nil)
    }

    private func handleConnect(result: @escaping FlutterResult) {
        RiviumSync.shared?.connect { connectResult in
            switch connectResult {
            case .success:
                result(nil)
            case .failure(let error):
                result(FlutterError(code: "CONNECTION_ERROR", message: error.localizedDescription, details: nil))
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
                    result(FlutterError(code: "DATABASE_ERROR", message: error.localizedDescription, details: nil))
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
                    result(FlutterError(code: "DATABASE_ERROR", message: error.localizedDescription, details: nil))
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
                    result(FlutterError(code: "DATABASE_ERROR", message: error.localizedDescription, details: nil))
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
                    result(FlutterError(code: "COLLECTION_ERROR", message: error.localizedDescription, details: nil))
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
                    result(FlutterError(code: "COLLECTION_ERROR", message: error.localizedDescription, details: nil))
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
                    result(FlutterError(code: "COLLECTION_ERROR", message: error.localizedDescription, details: nil))
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
                    result(FlutterError(code: "DOCUMENT_ERROR", message: error.localizedDescription, details: nil))
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
                    result(FlutterError(code: "DOCUMENT_ERROR", message: error.localizedDescription, details: nil))
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
                    result(FlutterError(code: "DOCUMENT_ERROR", message: error.localizedDescription, details: nil))
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
                    result(FlutterError(code: "DOCUMENT_ERROR", message: error.localizedDescription, details: nil))
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

        Task {
            do {
                let doc = try await RiviumSync.shared?.database(databaseId).collection(collectionId).set(documentId: documentId, data: data)
                DispatchQueue.main.async {
                    result(doc?.toDict())
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "DOCUMENT_ERROR", message: error.localizedDescription, details: nil))
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
                    result(FlutterError(code: "DOCUMENT_ERROR", message: error.localizedDescription, details: nil))
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

                let docs = try await query?.get() ?? []
                DispatchQueue.main.async {
                    result(docs.map { $0.toDict() })
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "QUERY_ERROR", message: error.localizedDescription, details: nil))
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

        let registration = RiviumSync.shared?.database(databaseId).collection(collectionId).listen { [weak self] docs in
            DispatchQueue.main.async {
                self?.collectionEventSinks[listenerId]?.self([
                    "listenerId": listenerId,
                    "documents": docs.map { $0.toDict() }
                ])
            }
        }

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

        print("[RiviumSyncPlugin] handleListenDocument: listenerId=\(listenerId), documentId=\(documentId)")
        print("[RiviumSyncPlugin] Current documentEventSinks keys: \(Array(documentEventSinks.keys))")

        let registration = RiviumSync.shared?.database(databaseId).collection(collectionId).listenDocument(documentId: documentId) { [weak self] doc in
            print("[RiviumSyncPlugin] Document callback received for listenerId=\(listenerId), doc=\(doc != nil ? "present" : "nil")")
            print("[RiviumSyncPlugin] documentEventSinks keys at callback: \(Array(self?.documentEventSinks.keys ?? [:].keys))")
            let hasSink = self?.documentEventSinks[listenerId] != nil
            print("[RiviumSyncPlugin] Has sink for \(listenerId): \(hasSink)")

            DispatchQueue.main.async {
                if let sink = self?.documentEventSinks[listenerId] {
                    print("[RiviumSyncPlugin] Sending to Flutter via sink for \(listenerId)")
                    sink([
                        "listenerId": listenerId,
                        "document": doc?.toDict()
                    ])
                } else {
                    print("[RiviumSyncPlugin] ERROR: No sink found for listenerId=\(listenerId)")
                }
            }
        }

        if let registration = registration {
            listeners[listenerId] = registration
            print("[RiviumSyncPlugin] Listener registered: \(listenerId)")
        } else {
            print("[RiviumSyncPlugin] WARNING: registration is nil for \(listenerId)")
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

        Task {
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

            let registration = query?.listen { [weak self] docs in
                DispatchQueue.main.async {
                    self?.queryEventSinks[listenerId]?.self([
                        "listenerId": listenerId,
                        "documents": docs.map { $0.toDict() }
                    ])
                }
            }

            if let registration = registration {
                DispatchQueue.main.async {
                    self.listeners[listenerId] = registration
                }
            }

            DispatchQueue.main.async {
                result(nil)
            }
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

                    guard let collection = RiviumSync.shared?.database(databaseId).collection(collectionId) else {
                        continue
                    }

                    switch type {
                    case "set":
                        if let documentId = documentId, let data = data {
                            batch.set(collection, documentId: documentId, data: data)
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
                    result(FlutterError(code: "BATCH_ERROR", message: error.localizedDescription, details: nil))
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
        let state = RiviumSync.shared?.syncState ?? .idle
        let stateString: String
        switch state {
        case .idle: stateString = "idle"
        case .syncing: stateString = "syncing"
        case .offline: stateString = "offline"
        case .error: stateString = "error"
        }
        result(stateString)
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
private class RiviumSyncStreamHandler: NSObject, FlutterStreamHandler {
    private let getSinks: () -> [String: FlutterEventSink]
    private let setSink: (String, FlutterEventSink?) -> Void
    private let removeSink: (String) -> Void
    private let name: String

    init(name: String = "unknown", sinks: @escaping () -> [String: FlutterEventSink], setSink: @escaping (String, FlutterEventSink?) -> Void, removeSink: @escaping (String) -> Void) {
        self.name = name
        self.getSinks = sinks
        self.setSink = setSink
        self.removeSink = removeSink
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        guard let listenerId = arguments as? String else {
            print("[RiviumSyncStreamHandler:\(name)] onListen called with invalid arguments: \(String(describing: arguments))")
            return nil
        }
        print("[RiviumSyncStreamHandler:\(name)] onListen: registering sink for listenerId=\(listenerId)")
        setSink(listenerId, events)
        print("[RiviumSyncStreamHandler:\(name)] Current sinks after registration: \(Array(getSinks().keys))")
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        guard let listenerId = arguments as? String else {
            return nil
        }
        print("[RiviumSyncStreamHandler:\(name)] onCancel: removing sink for listenerId=\(listenerId)")
        removeSink(listenerId)
        return nil
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
