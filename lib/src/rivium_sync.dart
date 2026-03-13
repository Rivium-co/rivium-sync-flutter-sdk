import 'dart:async';
import 'package:flutter/services.dart';
import 'rivium_sync_config.dart';
import 'sync_database.dart';
import 'sync_document.dart';
import 'rivium_sync_error.dart';
import 'write_batch.dart';

export 'write_batch.dart';

/// Callback for connection state changes
typedef OnConnectionStateCallback = void Function(bool connected);

/// Callback for errors
typedef OnErrorCallback = void Function(RiviumSyncError error);

/// Callback for sync state changes
typedef OnSyncStateCallback = void Function(SyncState state);

/// Callback for pending count changes
typedef OnPendingCountCallback = void Function(int count);

/// Sync state for the sync engine
enum SyncState {
  idle,
  syncing,
  offline,
  error,
}

/// RiviumSync - Realtime Database SDK
///
/// A Firebase-like realtime database service for instant data synchronization
/// across all connected devices.
///
/// Usage:
/// ```dart
/// // Initialize
/// await RiviumSync.init(RiviumSyncConfig(
///   jwtToken: 'your-jwt-token',
/// ));
///
/// // Connect to realtime
/// await RiviumSync.connect();
///
/// // Get database and collection
/// final db = RiviumSync.database('my-database-id');
/// final todos = db.collection('todos');
///
/// // CRUD operations
/// final doc = await todos.add({'title': 'Buy milk', 'completed': false});
///
/// // Listen to realtime changes
/// final listener = todos.listen((documents) {
///   print('Todos updated: ${documents.length}');
/// });
///
/// // Clean up when done
/// listener.remove();
/// await RiviumSync.disconnect();
/// ```
class RiviumSync {
  static const MethodChannel _channel = MethodChannel('co.rivium.sync/rivium_sync');

  static OnConnectionStateCallback? _onConnectionState;
  static OnErrorCallback? _onError;
  static OnSyncStateCallback? _onSyncState;
  static OnPendingCountCallback? _onPendingCount;

  static bool _initialized = false;
  static bool _offlineEnabled = false;

  /// SDK version
  static const String version = '1.0.0';

  /// Initialize the SDK with configuration
  static Future<void> init(RiviumSyncConfig config) async {
    if (_initialized) return;

    _channel.setMethodCallHandler(_handleMethod);
    _offlineEnabled = config.offlineEnabled;

    await _channel.invokeMethod('init', config.toMap());
    _initialized = true;
  }

  /// Check if SDK is initialized
  static bool get isInitialized => _initialized;

  /// Set callback for connection state changes
  static void onConnectionState(OnConnectionStateCallback callback) {
    _onConnectionState = callback;
  }

  /// Set callback for errors
  static void onError(OnErrorCallback callback) {
    _onError = callback;
  }

  /// Connect to realtime sync service
  static Future<void> connect() async {
    _ensureInitialized();
    await _channel.invokeMethod('connect');
  }

  /// Disconnect from realtime sync service
  static Future<void> disconnect() async {
    await _channel.invokeMethod('disconnect');
  }

  /// Check if connected to realtime service
  static Future<bool> isConnected() async {
    final result = await _channel.invokeMethod<bool>('isConnected');
    return result ?? false;
  }

  /// Get a database reference by ID
  static SyncDatabase database(String databaseId) {
    _ensureInitialized();
    return SyncDatabase(_channel, databaseId, '');
  }

  // ==================== Batch Operations ====================

  /// Create a new WriteBatch for atomic operations.
  ///
  /// A WriteBatch is used to perform multiple writes as a single atomic unit.
  /// None of the writes will be committed until `commit()` is called.
  ///
  /// Usage:
  /// ```dart
  /// final batch = RiviumSync.batch();
  /// batch.set(usersCollection, 'user1', {'name': 'John'});
  /// batch.update(ordersCollection, 'order1', {'status': 'shipped'});
  /// batch.delete(tempCollection, 'temp1');
  /// await batch.commit();
  /// ```
  ///
  /// Returns a new WriteBatch instance.
  static WriteBatch batch() {
    _ensureInitialized();
    return WriteBatch(_channel);
  }

  /// List all databases for the current user
  static Future<List<DatabaseInfo>> listDatabases() async {
    _ensureInitialized();
    final result = await _channel.invokeMethod<List<dynamic>>('listDatabases');

    if (result == null) return [];

    return result
        .map((item) => DatabaseInfo.fromMap(item as Map))
        .toList();
  }

  // ==================== Offline API ====================

  /// Check if offline persistence is enabled
  static bool get isOfflineEnabled => _offlineEnabled;

  /// Set callback for sync state changes
  static void onSyncState(OnSyncStateCallback callback) {
    _onSyncState = callback;
  }

  /// Set callback for pending count changes
  static void onPendingCount(OnPendingCountCallback callback) {
    _onPendingCount = callback;
  }

  /// Get the current sync state
  static Future<SyncState> getSyncState() async {
    if (!_offlineEnabled) return SyncState.idle;

    final result = await _channel.invokeMethod<String>('getSyncState');
    return _parseSyncState(result);
  }

  /// Get the count of pending operations waiting to be synced
  static Future<int> getPendingCount() async {
    if (!_offlineEnabled) return 0;

    final result = await _channel.invokeMethod<int>('getPendingCount');
    return result ?? 0;
  }

  /// Force sync all pending operations now
  static Future<void> forceSyncNow() async {
    if (!_offlineEnabled) return;

    await _channel.invokeMethod('forceSyncNow');
  }

  /// Clear all cached data
  static Future<void> clearOfflineCache() async {
    if (!_offlineEnabled) return;

    await _channel.invokeMethod('clearOfflineCache');
  }

  static SyncState _parseSyncState(String? state) {
    switch (state) {
      case 'syncing':
        return SyncState.syncing;
      case 'offline':
        return SyncState.offline;
      case 'error':
        return SyncState.error;
      default:
        return SyncState.idle;
    }
  }

  static void _ensureInitialized() {
    if (!_initialized) {
      throw const RiviumSyncError(
        code: RiviumSyncErrorCode.notInitialized,
        message: 'RiviumSync SDK not initialized. Call RiviumSync.init() first.',
      );
    }
  }

  /// Handle method calls from native side
  static Future<void> _handleMethod(MethodCall call) async {
    switch (call.method) {
      case 'onConnectionState':
        final connected = call.arguments as bool;
        _onConnectionState?.call(connected);
        break;

      case 'onError':
        if (call.arguments is Map) {
          final error = RiviumSyncError.fromMap(
            call.arguments as Map<dynamic, dynamic>,
          );
          _onError?.call(error);
        }
        break;

      case 'onSyncState':
        final state = _parseSyncState(call.arguments as String?);
        _onSyncState?.call(state);
        break;

      case 'onPendingCount':
        final count = call.arguments as int? ?? 0;
        _onPendingCount?.call(count);
        break;
    }
  }
}
