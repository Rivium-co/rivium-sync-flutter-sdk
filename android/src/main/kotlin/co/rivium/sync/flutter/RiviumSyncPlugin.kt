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
    private val listeners = mutableMapOf<String, ListenerRegistration>()

    // Event sinks for streaming updates to Flutter
    private val collectionEventSinks = mutableMapOf<String, EventChannel.EventSink>()
    private val documentEventSinks = mutableMapOf<String, EventChannel.EventSink>()
    private val queryEventSinks = mutableMapOf<String, EventChannel.EventSink>()

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "co.rivium.sync/rivium_sync")
        channel.setMethodCallHandler(this)

        collectionEventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "co.rivium.sync/collection_events")
        documentEventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "co.rivium.sync/document_events")
        queryEventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "co.rivium.sync/query_events")

        // Set up stream handlers for event channels
        collectionEventChannel.setStreamHandler(createStreamHandler(collectionEventSinks))
        documentEventChannel.setStreamHandler(createStreamHandler(documentEventSinks))
        queryEventChannel.setStreamHandler(createStreamHandler(queryEventSinks))

        context = flutterPluginBinding.applicationContext
    }

    private fun createStreamHandler(sinks: MutableMap<String, EventChannel.EventSink>): EventChannel.StreamHandler {
        return object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                val listenerId = arguments as? String ?: return
                events?.let { sinks[listenerId] = it }
            }

            override fun onCancel(arguments: Any?) {
                val listenerId = arguments as? String ?: return
                sinks.remove(listenerId)
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        collectionEventChannel.setStreamHandler(null)
        documentEventChannel.setStreamHandler(null)
        queryEventChannel.setStreamHandler(null)
        collectionEventSinks.clear()
        documentEventSinks.clear()
        queryEventSinks.clear()
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

        // User identity for Security Rules (auth.uid)
        (args["userId"] as? String)?.let { configBuilder.userId(it) }

        // Other offline persistence options
        (args["offlineCacheSizeMb"] as? Int)?.let { configBuilder.offlineCacheSizeMb(it) }
        (args["syncOnReconnect"] as? Boolean)?.let { configBuilder.syncOnReconnect(it) }
        (args["maxSyncRetries"] as? Int)?.let { configBuilder.maxSyncRetries(it) }
        (args["conflictStrategy"] as? String)?.let { strategy ->
            val conflictStrategy = when (strategy) {
                "clientWins" -> co.rivium.sync.sdk.offline.ConflictStrategy.CLIENT_WINS
                "merge" -> co.rivium.sync.sdk.offline.ConflictStrategy.MERGE
                "manual" -> co.rivium.sync.sdk.offline.ConflictStrategy.MANUAL
                else -> co.rivium.sync.sdk.offline.ConflictStrategy.SERVER_WINS
            }
            configBuilder.conflictStrategy(conflictStrategy)
        }

        val config = configBuilder.build()
        Log.d(TAG, "Flutter Plugin init: config.offlineEnabled=${config.offlineEnabled}")

        riviumSync = RiviumSync.initialize(context, config)
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
            onError = { error -> result.error("CONNECTION_ERROR", error.message, null) }
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
                result.error("DATABASE_ERROR", e.message, null)
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
                result.error("COLLECTION_ERROR", e.message, null)
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
                result.error("COLLECTION_ERROR", e.message, null)
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
                result.error("COLLECTION_ERROR", e.message, null)
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
                result.error("DOCUMENT_ERROR", e.message, null)
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
                result.error("DOCUMENT_ERROR", e.message, null)
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
                result.error("DOCUMENT_ERROR", e.message, null)
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
                result.error("DOCUMENT_ERROR", e.message, null)
            }
        }
    }

    private fun setDocument(call: MethodCall, result: Result) {
        val databaseId = call.argument<String>("databaseId") ?: return result.error("INVALID_ARGS", "databaseId required", null)
        val collectionId = call.argument<String>("collectionId") ?: return result.error("INVALID_ARGS", "collectionId required", null)
        val documentId = call.argument<String>("documentId") ?: return result.error("INVALID_ARGS", "documentId required", null)
        val data = call.argument<Map<String, Any?>>("data") ?: return result.error("INVALID_ARGS", "data required", null)

        scope.launch {
            try {
                val doc = riviumSync?.database(databaseId)?.collection(collectionId)?.set(documentId, data)
                result.success(doc?.toMap())
            } catch (e: Exception) {
                result.error("DOCUMENT_ERROR", e.message, null)
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
                result.error("DOCUMENT_ERROR", e.message, null)
            }
        }
    }

    private fun queryDocuments(call: MethodCall, result: Result) {
        val databaseId = call.argument<String>("databaseId") ?: return result.error("INVALID_ARGS", "databaseId required", null)
        val collectionId = call.argument<String>("collectionId") ?: return result.error("INVALID_ARGS", "collectionId required", null)
        val filters = call.argument<List<Map<String, Any?>>>("filters")
        val orderBy = call.argument<Map<String, Any?>>("orderBy")
        val limit = call.argument<Int>("limit")
        val offset = call.argument<Int>("offset")

        scope.launch {
            try {
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

                val docs = query?.get() ?: emptyList()
                result.success(docs.map { it.toMap() })
            } catch (e: Exception) {
                result.error("QUERY_ERROR", e.message, null)
            }
        }
    }

    private fun listenCollection(call: MethodCall, result: Result) {
        val databaseId = call.argument<String>("databaseId") ?: return result.error("INVALID_ARGS", "databaseId required", null)
        val collectionId = call.argument<String>("collectionId") ?: return result.error("INVALID_ARGS", "collectionId required", null)
        val listenerId = call.argument<String>("listenerId") ?: return result.error("INVALID_ARGS", "listenerId required", null)

        val registration = riviumSync?.database(databaseId)?.collection(collectionId)?.listen { docs ->
            scope.launch {
                collectionEventSinks[listenerId]?.success(mapOf(
                    "listenerId" to listenerId,
                    "documents" to docs.map { it.toMap() }
                ))
            }
        }

        registration?.let { listeners[listenerId] = it }
        result.success(null)
    }

    private fun listenDocument(call: MethodCall, result: Result) {
        val databaseId = call.argument<String>("databaseId") ?: return result.error("INVALID_ARGS", "databaseId required", null)
        val collectionId = call.argument<String>("collectionId") ?: return result.error("INVALID_ARGS", "collectionId required", null)
        val documentId = call.argument<String>("documentId") ?: return result.error("INVALID_ARGS", "documentId required", null)
        val listenerId = call.argument<String>("listenerId") ?: return result.error("INVALID_ARGS", "listenerId required", null)

        val registration = riviumSync?.database(databaseId)?.collection(collectionId)?.listenDocument(documentId) { doc ->
            scope.launch {
                documentEventSinks[listenerId]?.success(mapOf(
                    "listenerId" to listenerId,
                    "document" to doc?.toMap()
                ))
            }
        }

        registration?.let { listeners[listenerId] = it }
        result.success(null)
    }

    private fun listenQuery(call: MethodCall, result: Result) {
        val databaseId = call.argument<String>("databaseId") ?: return result.error("INVALID_ARGS", "databaseId required", null)
        val collectionId = call.argument<String>("collectionId") ?: return result.error("INVALID_ARGS", "collectionId required", null)
        val listenerId = call.argument<String>("listenerId") ?: return result.error("INVALID_ARGS", "listenerId required", null)
        val filters = call.argument<List<Map<String, Any?>>>("filters")
        val orderBy = call.argument<Map<String, Any?>>("orderBy")
        val limit = call.argument<Int>("limit")
        val offset = call.argument<Int>("offset")

        scope.launch {
            try {
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

                val registration = query?.listen { docs ->
                    scope.launch {
                        queryEventSinks[listenerId]?.success(mapOf(
                            "listenerId" to listenerId,
                            "documents" to docs.map { it.toMap() }
                        ))
                    }
                }

                registration?.let { listeners[listenerId] = it }
                result.success(null)
            } catch (e: Exception) {
                result.error("QUERY_ERROR", e.message, null)
            }
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

                    val collection = riviumSync?.database(databaseId)?.collection(collectionId) ?: continue

                    when (type) {
                        "set" -> {
                            if (documentId != null && data != null) {
                                batch.set(collection, documentId, data)
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
                result.error("BATCH_ERROR", e.message, null)
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
                result.error("CACHE_ERROR", e.message, null)
            }
        }
    }
}
