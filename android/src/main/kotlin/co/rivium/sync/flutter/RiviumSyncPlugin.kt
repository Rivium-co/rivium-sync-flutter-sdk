package co.rivium.sync.flutter

import android.content.Context
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import co.rivium.sync.sdk.*
import kotlinx.coroutines.*

private const val TAG = "RiviumSyncFlutter"

/**
 * Flutter plugin for RiviumSync SDK
 */
class RiviumSyncPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var collectionEventChannel: EventChannel
    private lateinit var documentEventChannel: EventChannel
    private lateinit var queryEventChannel: EventChannel
    private lateinit var context: Context

    private var riviumSync: RiviumSync? = null
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    /** Forwards the sync state and pending count to Dart (RiviumSync.onSyncState / onPendingCount). */
    private var offlineStateJob: Job? = null
    private val listeners = mutableMapOf<String, ListenerRegistration>()

    // Event sinks for streaming updates to Flutter
    // One stream per event channel: Flutter keeps a single active stream per channel, so every listener of a kind
    // shares it and each event carries its listenerId (the Dart side hands it to the right listener).
    private val collectionEvents = EventSinkHolder()
    private val documentEvents = EventSinkHolder()
    private val queryEvents = EventSinkHolder()

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "co.rivium.sync/rivium_sync")
        channel.setMethodCallHandler(this)

        collectionEventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "co.rivium.sync/collection_events")
        documentEventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "co.rivium.sync/document_events")
        queryEventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "co.rivium.sync/query_events")

        // Set up stream handlers for event channels
        collectionEventChannel.setStreamHandler(createStreamHandler(collectionEvents))
        documentEventChannel.setStreamHandler(createStreamHandler(documentEvents))
        queryEventChannel.setStreamHandler(createStreamHandler(queryEvents))

        context = flutterPluginBinding.applicationContext
    }

    private class EventSinkHolder {
        @Volatile var sink: EventChannel.EventSink? = null
    }

    private fun createStreamHandler(holder: EventSinkHolder): EventChannel.StreamHandler {
        return object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                holder.sink = events
            }

            override fun onCancel(arguments: Any?) {
                holder.sink = null
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        collectionEventChannel.setStreamHandler(null)
        documentEventChannel.setStreamHandler(null)
        queryEventChannel.setStreamHandler(null)
        collectionEvents.sink = null
        documentEvents.sink = null
        queryEvents.sink = null
        scope.cancel()
        listeners.values.forEach { it.remove() }
        listeners.clear()
        riviumSync?.destroy()
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "init" -> init(call, result)
            "connect" -> connect(result)
            "disconnect" -> disconnect(result)
            "isConnected" -> result.success(riviumSync?.isConnected() ?: false)
            "isAwaitingUserToken" -> result.success(riviumSync?.isAwaitingUserToken ?: false)
            "setUserToken" -> setUserToken(call, result)

            // Database operations
            "listDatabases" -> listDatabases(result)

            // Collection operations
            "listCollections" -> listCollections(call, result)
            "createCollection" -> createCollection(call, result)
            "deleteCollection" -> deleteCollection(call, result)

            // Document operations
            "addDocument" -> addDocument(call, result)
            "getDocument" -> getDocument(call, result)
            "getAllDocuments" -> getAllDocuments(call, result)
            "updateDocument" -> updateDocument(call, result)
            "setDocument" -> setDocument(call, result)
            "deleteDocument" -> deleteDocument(call, result)
            "queryDocuments" -> queryDocuments(call, result)

            // Listeners
            "listenCollection" -> listenCollection(call, result)
            "removeCollectionListener" -> removeListener(call, result)
            "listenDocument" -> listenDocument(call, result)
            "removeDocumentListener" -> removeListener(call, result)
            "listenQuery" -> listenQuery(call, result)
            "removeQueryListener" -> removeListener(call, result)

            // Batch operations
            "executeBatch" -> executeBatch(call, result)

            // Offline persistence operations
            "getSyncState" -> getSyncState(result)
            "getPendingCount" -> getPendingCount(result)
            "forceSyncNow" -> forceSyncNow(result)
            "clearOfflineCache" -> clearOfflineCache(result)

            else -> result.notImplemented()
        }
    }

    /**
     * Replace the signed user token. Dart fetches it from the app's own backend
     * (it has an HTTP client of its own) and pushes it down here, which keeps
     * the bridge one-way and avoids calling back into Dart from the SDK.
     */
    private fun setUserToken(call: MethodCall, result: Result) {
        val sync = riviumSync
        if (sync == null) {
            result.error("notInitialized", "Call init before setUserToken", null)
            return
        }
        sync.userTokens.set(call.argument<String>("token"))
        result.success(null)
    }

    private fun init(call: MethodCall, result: Result) {
        val args = call.arguments as Map<*, *>

        // Parse offline enabled (handle both Boolean and other types)
        val offlineEnabled = when (val value = args["offlineEnabled"]) {
            is Boolean -> value
            is String -> value.equals("true", ignoreCase = true)
            else -> false
        }

        Log.d(TAG, "Flutter Plugin init: offlineEnabled=$offlineEnabled, raw value=${args["offlineEnabled"]}")

        val configBuilder = RiviumSyncConfig.builder(args["apiKey"] as String)
            .debugMode(args["debugMode"] as? Boolean ?: false)
            .autoReconnect(args["autoReconnect"] as? Boolean ?: true)
            .offlineEnabled(offlineEnabled)

        // User identity for Security Rules (auth.uid). A signed token is
        // trustworthy; the plain userId is not, and a project that enforces
        // requireSignedTokens refuses it.
        (args["userId"] as? String)?.let { configBuilder.userId(it) }
        (args["userToken"] as? String)?.let { configBuilder.userToken(it) }

        // Other offline persistence options
        (args["offlineCacheSizeMb"] as? Int)?.let { configBuilder.offlineCacheSizeMb(it) }
        (args["syncOnReconnect"] as? Boolean)?.let { configBuilder.syncOnReconnect(it) }
        (args["conflictStrategy"] as? String)?.let { strategy ->
            val conflictStrategy = when (strategy) {
                "clientWins" -> co.rivium.sync.sdk.offline.ConflictStrategy.CLIENT_WINS
                "merge" -> co.rivium.sync.sdk.offline.ConflictStrategy.MERGE
                "manual" -> co.rivium.sync.sdk.offline.ConflictStrategy.MANUAL
                else -> co.rivium.sync.sdk.offline.ConflictStrategy.SERVER_WINS
            }
            configBuilder.conflictStrategy(conflictStrategy)
        }

        // Report this plugin (flutter/<version>) in the X-Rivium-SDK header.
        configBuilder.wrapperSdk(args["wrapperSdkName"] as? String, args["wrapperSdkVersion"] as? String)

        // A local Rivium Sync server (plain HTTP, realtime without TLS). Dart checked the values already.
        (args["emulatorHost"] as? String)?.let { host ->
            val port = (args["emulatorPort"] as? Number)?.toInt() ?: 3006
            try {
                configBuilder.useEmulator(host, port)
            } catch (e: IllegalArgumentException) {
                result.error("INVALID_ARGS", e.message, null)
                return
            }
        }

        val config = configBuilder.build()
        Log.d(TAG, "Flutter Plugin init: config.offlineEnabled=${config.offlineEnabled}")

        riviumSync?.removeSyncListener(syncEvents)
        riviumSync = RiviumSync.initialize(context, config)
        // Queued writes the server refuses (offline persistence only; without it nothing is queued).
        riviumSync?.removeSyncListener(syncEvents)
        riviumSync?.addSyncListener(syncEvents)
        // Sync state and pending count as they change (offline persistence only; null flows otherwise).
        offlineStateJob?.cancel()
        offlineStateJob = scope.launch {
            launch { riviumSync?.getSyncState()?.collect { channel.invokeMethod("onSyncState", it.name.lowercase()) } }
            launch { riviumSync?.getPendingCount()?.collect { channel.invokeMethod("onPendingCount", it) } }
        }
        // The project requires a user token and none is set yet: connect() is
        // parked, not failed. The SDK connects when setUserToken supplies one.
        riviumSync?.onAwaitingUserToken = {
            scope.launch { channel.invokeMethod("onAwaitingUserToken", null) }
        }
        riviumSync?.setConnectionListener(object : RiviumSync.ConnectionListener {
            override fun onConnected() {
                scope.launch { channel.invokeMethod("onConnectionState", true) }
            }

            override fun onDisconnected(cause: Throwable?) {
                scope.launch { channel.invokeMethod("onConnectionState", false) }
            }

            override fun onConnectionFailed(cause: Throwable) {
                scope.launch {
                    channel.invokeMethod("onError", mapOf(
                        "code" to "connectionError",
                        "message" to (cause.message ?: "Connection failed")
                    ))
                }
            }
        })

        result.success(null)
    }

    private fun connect(result: Result) {
        riviumSync?.connect(
            onSuccess = { result.success(null) },
            onError = { error -> result.fail("CONNECTION_ERROR", error) }
        )
    }

    private fun disconnect(result: Result) {
        riviumSync?.disconnect()
        result.success(null)
    }

    private fun listDatabases(result: Result) {
        scope.launch {
            try {
                val databases = riviumSync?.listDatabases() ?: emptyList()
                result.success(databases.map { db ->
                    mapOf(
                        "id" to db.id,
                        "name" to db.name,
                        "createdAt" to db.createdAt,
                        "updatedAt" to db.updatedAt
                    )
                })
            } catch (e: Exception) {
                result.fail("DATABASE_ERROR", e)
            }
        }
    }

    private fun listCollections(call: MethodCall, result: Result) {
        val databaseId = call.argument<String>("databaseId") ?: return result.error("INVALID_ARGS", "databaseId required", null)
        scope.launch {
            try {
                val collections = riviumSync?.database(databaseId)?.listCollections() ?: emptyList()
                result.success(collections.map { col ->
                    mapOf(
                        "id" to col.id,
                        "name" to col.name,
                        "databaseId" to col.databaseId,
                        "documentCount" to col.documentCount,
                        "createdAt" to col.createdAt,
                        "updatedAt" to col.updatedAt
                    )
                })
            } catch (e: Exception) {
                result.fail("COLLECTION_ERROR", e)
            }
        }
    }

    private fun createCollection(call: MethodCall, result: Result) {
        val databaseId = call.argument<String>("databaseId") ?: return result.error("INVALID_ARGS", "databaseId required", null)
        val name = call.argument<String>("name") ?: return result.error("INVALID_ARGS", "name required", null)
        scope.launch {
            try {
                val col = riviumSync?.database(databaseId)?.createCollection(name)
                result.success(mapOf(
                    "id" to col?.id,
                    "name" to col?.name,
                    "databaseId" to databaseId
                ))
            } catch (e: Exception) {
                result.fail("COLLECTION_ERROR", e)
            }
        }
    }

    private fun deleteCollection(call: MethodCall, result: Result) {
        val collectionId = call.argument<String>("collectionId") ?: return result.error("INVALID_ARGS", "collectionId required", null)
        scope.launch {
            try {
                // Note: This needs the databaseId from somewhere
                result.success(null)
            } catch (e: Exception) {
                result.fail("COLLECTION_ERROR", e)
            }
        }
    }

    private fun addDocument(call: MethodCall, result: Result) {
        val databaseId = call.argument<String>("databaseId") ?: return result.error("INVALID_ARGS", "databaseId required", null)
        val collectionId = call.argument<String>("collectionId") ?: return result.error("INVALID_ARGS", "collectionId required", null)
        val data = call.argument<Map<String, Any?>>("data") ?: return result.error("INVALID_ARGS", "data required", null)

        scope.launch {
            try {
                val doc = riviumSync?.database(databaseId)?.collection(collectionId)?.add(data)
                result.success(doc?.toMap())
            } catch (e: Exception) {
                result.fail("DOCUMENT_ERROR", e)
            }
        }
    }

    private fun getDocument(call: MethodCall, result: Result) {
        val databaseId = call.argument<String>("databaseId") ?: return result.error("INVALID_ARGS", "databaseId required", null)
        val collectionId = call.argument<String>("collectionId") ?: return result.error("INVALID_ARGS", "collectionId required", null)
        val documentId = call.argument<String>("documentId") ?: return result.error("INVALID_ARGS", "documentId required", null)

        scope.launch {
            try {
                val doc = riviumSync?.database(databaseId)?.collection(collectionId)?.get(documentId)
                result.success(doc?.toMap())
            } catch (e: Exception) {
                result.fail("DOCUMENT_ERROR", e)
            }
        }
    }

    private fun getAllDocuments(call: MethodCall, result: Result) {
        val databaseId = call.argument<String>("databaseId") ?: return result.error("INVALID_ARGS", "databaseId required", null)
        val collectionId = call.argument<String>("collectionId") ?: return result.error("INVALID_ARGS", "collectionId required", null)

        scope.launch {
            try {
                val docs = riviumSync?.database(databaseId)?.collection(collectionId)?.getAll() ?: emptyList()
                result.success(docs.map { it.toMap() })
            } catch (e: Exception) {
                result.fail("DOCUMENT_ERROR", e)
            }
        }
    }

    private fun updateDocument(call: MethodCall, result: Result) {
        val databaseId = call.argument<String>("databaseId") ?: return result.error("INVALID_ARGS", "databaseId required", null)
        val collectionId = call.argument<String>("collectionId") ?: return result.error("INVALID_ARGS", "collectionId required", null)
        val documentId = call.argument<String>("documentId") ?: return result.error("INVALID_ARGS", "documentId required", null)
        val data = call.argument<Map<String, Any?>>("data") ?: return result.error("INVALID_ARGS", "data required", null)

        scope.launch {
            try {
                val doc = riviumSync?.database(databaseId)?.collection(collectionId)?.update(documentId, data)
                result.success(doc?.toMap())
            } catch (e: Exception) {
                result.fail("DOCUMENT_ERROR", e)
            }
        }
    }

    private fun setDocument(call: MethodCall, result: Result) {
        val databaseId = call.argument<String>("databaseId") ?: return result.error("INVALID_ARGS", "databaseId required", null)
        val collectionId = call.argument<String>("collectionId") ?: return result.error("INVALID_ARGS", "collectionId required", null)
        val documentId = call.argument<String>("documentId") ?: return result.error("INVALID_ARGS", "documentId required", null)
        val data = call.argument<Map<String, Any?>>("data") ?: return result.error("INVALID_ARGS", "data required", null)
        // Replace by default; merge only when asked.
        val merge = call.argument<Boolean>("merge") ?: false

        scope.launch {
            try {
                val doc = riviumSync?.database(databaseId)?.collection(collectionId)?.set(documentId, data, merge)
                result.success(doc?.toMap())
            } catch (e: Exception) {
                result.fail("DOCUMENT_ERROR", e)
            }
        }
    }

    private fun deleteDocument(call: MethodCall, result: Result) {
        val databaseId = call.argument<String>("databaseId") ?: return result.error("INVALID_ARGS", "databaseId required", null)
        val collectionId = call.argument<String>("collectionId") ?: return result.error("INVALID_ARGS", "collectionId required", null)
        val documentId = call.argument<String>("documentId") ?: return result.error("INVALID_ARGS", "documentId required", null)

        scope.launch {
            try {
                riviumSync?.database(databaseId)?.collection(collectionId)?.delete(documentId)
                result.success(null)
            } catch (e: Exception) {
                result.fail("DOCUMENT_ERROR", e)
            }
        }
    }

    private fun queryDocuments(call: MethodCall, result: Result) {
        val databaseId = call.argument<String>("databaseId") ?: return result.error("INVALID_ARGS", "databaseId required", null)
        val collectionId = call.argument<String>("collectionId") ?: return result.error("INVALID_ARGS", "collectionId required", null)

        scope.launch {
            try {
                val docs = buildQuery(call, databaseId, collectionId)?.get() ?: emptyList()
                result.success(docs.map { it.toMap() })
            } catch (e: Exception) {
                result.fail("QUERY_ERROR", e)
            }
        }
    }

    /** The query described by the call's filters / orderBy / limit / offset. */
    private fun buildQuery(call: MethodCall, databaseId: String, collectionId: String): SyncQuery? {
        val filters = call.argument<List<Map<String, Any?>>>("filters")
        val orderBy = call.argument<Map<String, Any?>>("orderBy")
        val limit = call.argument<Int>("limit")
        val offset = call.argument<Int>("offset")

        var query = riviumSync?.database(databaseId)?.collection(collectionId)?.query()

        filters?.forEach { filter ->
            val field = filter["field"] as String
            val operator = filter["operator"] as String
            val value = filter["value"]
            val op = when (operator) {
                "==" -> QueryOperator.EQUAL
                "!=" -> QueryOperator.NOT_EQUAL
                ">" -> QueryOperator.GREATER_THAN
                ">=" -> QueryOperator.GREATER_THAN_OR_EQUAL
                "<" -> QueryOperator.LESS_THAN
                "<=" -> QueryOperator.LESS_THAN_OR_EQUAL
                "array-contains" -> QueryOperator.ARRAY_CONTAINS
                "in" -> QueryOperator.IN
                "not-in" -> QueryOperator.NOT_IN
                else -> QueryOperator.EQUAL
            }
            query = query?.where(field, op, value)
        }

        orderBy?.let {
            val field = it["field"] as String
            val direction = if (it["direction"] == "desc") OrderDirection.DESCENDING else OrderDirection.ASCENDING
            query = query?.orderBy(field, direction)
        }

        limit?.let { query = query?.limit(it) }
        offset?.let { query = query?.offset(it) }
        return query
    }

    /**
     * Reply with the native error, typed on the Dart side (RiviumSyncError.fromPlatformException): the HTTP status
     * the server answered with in `details.statusCode`, and `query_not_allowed` with its fields.
     */
    private fun Result.fail(code: String, e: Throwable) {
        if (e is RiviumSyncException.QueryNotAllowedException) {
            error("query_not_allowed", e.message, mapOf("fields" to e.fields, "statusCode" to e.statusCode))
        } else {
            error(code, e.message, errorDetails(e))
        }
    }

    /** `statusCode` (and the server's error `code`) of a request the server answered, else null. */
    private fun errorDetails(e: Throwable): Map<String, Any?>? {
        val network = e as? RiviumSyncException.NetworkException ?: return null
        if (network.statusCode == null && network.code == null) return null
        return mapOf("statusCode" to network.statusCode, "serverCode" to network.code)
    }

    /** The error map of a refused queued write, read by RiviumSyncError.fromMap on the Dart side. */
    private fun rejectionErrorMap(e: Throwable): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>(
            "code" to if (e is RiviumSyncException.QueryNotAllowedException) "query_not_allowed" else "DOCUMENT_ERROR",
            "message" to (e.message ?: "The server refused the write"),
        )
        errorDetails(e)?.let { map.putAll(it) }
        if (e is RiviumSyncException.QueryNotAllowedException) map["fields"] = e.fields
        return map
    }

    /**
     * Forwards the sync engine's rejections to Dart (RiviumSync.onDocumentRejected). The other events are not
     * forwarded.
     */
    private val syncEvents = object : SyncListener {
        override fun onSyncStarted() {}
        override fun onSyncCompleted(syncedCount: Int) {}
        override fun onSyncFailed(error: Throwable) {}
        override fun onConflictDetected(conflict: co.rivium.sync.sdk.offline.ConflictInfo) {}
        override fun onDocumentSynced(documentId: String, operation: co.rivium.sync.sdk.offline.OperationType) {}
        override fun onDocumentRejected(
            documentId: String,
            operation: co.rivium.sync.sdk.offline.OperationType,
            error: Throwable,
        ) {
            scope.launch {
                channel.invokeMethod("onDocumentRejected", mapOf(
                    "documentId" to documentId,
                    "operation" to operation.name.lowercase(),
                    "error" to rejectionErrorMap(error)
                ))
            }
        }
    }

    /**
     * The error map a listener event carries when the listener stopped (read by RiviumSyncListenerError.fromMap):
     * `query_not_allowed` with its fields, `listener_revoked`, `permission_denied` for another 403, else the
     * server's code.
     */
    private fun listenerErrorMap(e: RiviumSyncException): Map<String, Any?> = when (e) {
        is RiviumSyncException.QueryNotAllowedException -> mapOf(
            "code" to "query_not_allowed",
            "message" to e.message,
            "fields" to e.fields,
            "statusCode" to e.statusCode
        )
        is RiviumSyncException.NetworkException -> mapOf(
            "code" to (e.code ?: if (e.statusCode == 403) "permission_denied" else "UNKNOWN_ERROR"),
            "message" to e.message,
            "statusCode" to e.statusCode
        )
        else -> mapOf("code" to "UNKNOWN_ERROR", "message" to e.message)
    }

    private fun listenCollection(call: MethodCall, result: Result) {
        val databaseId = call.argument<String>("databaseId") ?: return result.error("INVALID_ARGS", "databaseId required", null)
        val collectionId = call.argument<String>("collectionId") ?: return result.error("INVALID_ARGS", "collectionId required", null)
        val listenerId = call.argument<String>("listenerId") ?: return result.error("INVALID_ARGS", "listenerId required", null)

        val registration = riviumSync?.database(databaseId)?.collection(collectionId)?.listen(
            { docs ->
                scope.launch {
                    collectionEvents.sink?.success(mapOf(
                        "listenerId" to listenerId,
                        "documents" to docs.map { it.toMap() }
                    ))
                }
            },
            { error ->
                scope.launch {
                    collectionEvents.sink?.success(mapOf("listenerId" to listenerId, "error" to listenerErrorMap(error)))
                }
            }
        )

        registration?.let { listeners[listenerId] = it }
        result.success(null)
    }

    private fun listenDocument(call: MethodCall, result: Result) {
        val databaseId = call.argument<String>("databaseId") ?: return result.error("INVALID_ARGS", "databaseId required", null)
        val collectionId = call.argument<String>("collectionId") ?: return result.error("INVALID_ARGS", "collectionId required", null)
        val documentId = call.argument<String>("documentId") ?: return result.error("INVALID_ARGS", "documentId required", null)
        val listenerId = call.argument<String>("listenerId") ?: return result.error("INVALID_ARGS", "listenerId required", null)

        val registration = riviumSync?.database(databaseId)?.collection(collectionId)?.listenDocument(
            documentId,
            { doc ->
                scope.launch {
                    documentEvents.sink?.success(mapOf(
                        "listenerId" to listenerId,
                        "document" to doc?.toMap()
                    ))
                }
            },
            { error ->
                scope.launch {
                    documentEvents.sink?.success(mapOf("listenerId" to listenerId, "error" to listenerErrorMap(error)))
                }
            }
        )

        registration?.let { listeners[listenerId] = it }
        result.success(null)
    }

    private fun listenQuery(call: MethodCall, result: Result) {
        val databaseId = call.argument<String>("databaseId") ?: return result.error("INVALID_ARGS", "databaseId required", null)
        val collectionId = call.argument<String>("collectionId") ?: return result.error("INVALID_ARGS", "collectionId required", null)
        val listenerId = call.argument<String>("listenerId") ?: return result.error("INVALID_ARGS", "listenerId required", null)

        try {
            val registration = buildQuery(call, databaseId, collectionId)?.listen(
                { docs ->
                    scope.launch {
                        queryEvents.sink?.success(mapOf(
                            "listenerId" to listenerId,
                            "documents" to docs.map { it.toMap() }
                        ))
                    }
                },
                { error ->
                    scope.launch {
                        queryEvents.sink?.success(mapOf("listenerId" to listenerId, "error" to listenerErrorMap(error)))
                    }
                }
            )

            registration?.let { listeners[listenerId] = it }
            result.success(null)
        } catch (e: Exception) {
            result.fail("QUERY_ERROR", e)
        }
    }

    private fun executeBatch(call: MethodCall, result: Result) {
        val operations = call.argument<List<Map<String, Any?>>>("operations")
            ?: return result.error("INVALID_ARGS", "operations required", null)

        scope.launch {
            try {
                // Create a WriteBatch and add all operations
                val batch = riviumSync?.batch() ?: return@launch result.error("NOT_INITIALIZED", "RiviumSync not initialized", null)

                for (op in operations) {
                    val type = op["type"] as? String ?: continue
                    val databaseId = op["databaseId"] as? String ?: continue
                    val collectionId = op["collectionId"] as? String ?: continue
                    val documentId = op["documentId"] as? String
                    @Suppress("UNCHECKED_CAST")
                    val data = op["data"] as? Map<String, Any?>

                    val merge = op["merge"] as? Boolean ?: false

                    val collection = riviumSync?.database(databaseId)?.collection(collectionId) ?: continue

                    when (type) {
                        "set" -> {
                            if (documentId != null && data != null) {
                                batch.set(collection, documentId, data, merge)
                            }
                        }
                        "update" -> {
                            if (documentId != null && data != null) {
                                batch.update(collection, documentId, data)
                            }
                        }
                        "delete" -> {
                            if (documentId != null) {
                                batch.delete(collection, documentId)
                            }
                        }
                        "create" -> {
                            if (data != null) {
                                batch.create(collection, data)
                            }
                        }
                    }
                }

                batch.commit()
                result.success(null)
            } catch (e: Exception) {
                result.fail("BATCH_ERROR", e)
            }
        }
    }

    private fun removeListener(call: MethodCall, result: Result) {
        val listenerId = call.argument<String>("listenerId") ?: return result.error("INVALID_ARGS", "listenerId required", null)
        listeners.remove(listenerId)?.remove()
        result.success(null)
    }

    // ==================== Offline Persistence Methods ====================

    private fun getSyncState(result: Result) {
        try {
            val stateFlow = riviumSync?.getSyncState()
            val state = stateFlow?.value?.name?.lowercase() ?: "idle"
            result.success(state)
        } catch (e: Exception) {
            result.success("idle")
        }
    }

    private fun getPendingCount(result: Result) {
        try {
            val countFlow = riviumSync?.getPendingCount()
            val count = countFlow?.value ?: 0
            Log.d(TAG, "Flutter Plugin getPendingCount: $count")
            result.success(count)
        } catch (e: Exception) {
            Log.e(TAG, "Flutter Plugin getPendingCount error", e)
            result.success(0)
        }
    }

    private fun forceSyncNow(result: Result) {
        try {
            Log.d(TAG, "Flutter Plugin forceSyncNow called, riviumSync=${riviumSync != null}")
            riviumSync?.forceSyncNow()
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Flutter Plugin forceSyncNow error", e)
            result.error("SYNC_ERROR", e.message, null)
        }
    }

    private fun clearOfflineCache(result: Result) {
        scope.launch {
            try {
                riviumSync?.clearOfflineCache()
                result.success(null)
            } catch (e: Exception) {
                result.fail("CACHE_ERROR", e)
            }
        }
    }
}
