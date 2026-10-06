import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
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

/// Called when [RiviumSync.connect] starts waiting for a user token.
typedef OnAwaitingUserTokenCallback = void Function();

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
///   apiKey: 'YOUR_API_KEY',
/// ));
///
/// // Connect to realtime
/// await RiviumSync.connect();
///
/// // Get database and collection by NAME (as shown in Rivium Console)
/// final db = RiviumSync.database('my-app');
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

  static OnAwaitingUserTokenCallback? _onAwaitingUserToken;
  static RiviumSyncTokenProvider? _tokenProvider;
  static Timer? _tokenRefreshTimer;
  static DateTime? _tokenExpiresAt;
  static _ResumeObserver? _resumeObserver;

  /// Ask the provider for a new token this long before the old one expires.
  static const Duration _tokenRefreshMargin = Duration(seconds: 60);

  /// Wait this long before asking again after the provider failed.
  static const Duration _tokenRetryDelay = Duration(seconds: 60);

  /// SDK version
  static const String version = '1.0.0';

  /// Initialize the SDK with configuration
  static Future<void> init(RiviumSyncConfig config) async {
    if (_initialized) return;

    _channel.setMethodCallHandler(_handleMethod);
    _offlineEnabled = config.offlineEnabled;

    final args = config.toMap();
    _tokenProvider = config.tokenProvider ?? _tokenProvider;
    String? token = config.userToken;
    if (_tokenProvider != null) {
      token = await _askProvider() ?? token;
      if (token != null) args['userToken'] = token;
    }

    await _channel.invokeMethod('init', args);
    _initialized = true;
    _trackToken(token);
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

  /// Replace the signed user token the SDK sends with every request.
  ///
  /// Your backend mints it with its server secret (`POST /users/token`); the app
  /// never holds that secret. Call this when the user signs in, and again
  /// whenever you refresh the token - they are short lived, an hour by default.
  /// With a [RiviumSyncConfig.tokenProvider] the SDK does this for you.
  ///
  /// ```dart
  /// final token = await myBackend.fetchRiviumSyncToken();
  /// await RiviumSync.setUserToken(token);
  /// ```
  ///
  /// If [connect] was waiting for a token, the SDK connects now; if it is
  /// connected as another user, it reconnects as this one.
  ///
  /// Pass `null` to stop sending a token, for example when the user signs out.
  static Future<void> setUserToken(String? token) async {
    await _channel.invokeMethod('setUserToken', {'token': token});
    _trackToken(token);
  }

  /// Set or remove the token provider after [init]. The provider is asked
  /// straight away.
  static Future<void> setTokenProvider(RiviumSyncTokenProvider? provider) async {
    _tokenProvider = provider;
    if (provider == null) {
      _tokenRefreshTimer?.cancel();
      return;
    }
    if (_initialized) await refreshUserToken();
  }

  /// Ask the token provider again and hand the result to the SDK. Call this
  /// when the user signs in or out. Does nothing without a provider.
  static Future<void> refreshUserToken() async {
    if (_tokenProvider == null || !_initialized) return;
    final String? token;
    try {
      token = await _tokenProvider!();
    } catch (_) {
      // Keep the token the SDK has; it may still be valid. Try again later.
      _scheduleTokenRefresh(_tokenRetryDelay);
      return;
    }
    await setUserToken(token);
  }

  /// Called when [connect] starts waiting for a user token: the project
  /// requires signed user tokens and none has been supplied yet.
  static void onAwaitingUserToken(OnAwaitingUserTokenCallback callback) {
    _onAwaitingUserToken = callback;
  }

  /// True while [connect] is waiting for a user token.
  static Future<bool> isAwaitingUserToken() async {
    final result = await _channel.invokeMethod<bool>('isAwaitingUserToken');
    return result ?? false;
  }

  /// Connect to realtime sync service.
  ///
  /// May be called before anyone is signed in. If the project requires signed
  /// user tokens and there is none yet, this completes normally and the SDK
  /// connects once a token is set (see [setUserToken], [refreshUserToken]).
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

  /// Get a database reference by its [name].
  ///
  /// Pass the database NAME exactly as shown in Rivium Console (for example
  /// `'my-app'`), not its UUID. Realtime updates are published per database
  /// name, so `listen` only receives changes when you address the database by
  /// name; a UUID would still work for plain reads and writes but live updates
  /// would never arrive.
  ///
  /// ```dart
  /// final todos = RiviumSync.database('my-app').collection('todos');
  /// ```
  static SyncDatabase database(String name) {
    _ensureInitialized();
    return SyncDatabase(_channel, name, '');
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
  static Future<String?> _askProvider() async {
    try {
      return await _tokenProvider!();
    } catch (_) {
      return null;
    }
  }

  /// Remember when [token] expires and, with a provider, plan its renewal.
  static void _trackToken(String? token) {
    _tokenExpiresAt = token == null ? null : _expiryOf(token);
    _tokenRefreshTimer?.cancel();
    if (_tokenProvider == null) return;
    _watchAppResume();
    final expiresAt = _tokenExpiresAt;
    // No token (signed out) or an unreadable one: nothing to renew until the
    // app calls refreshUserToken().
    if (expiresAt == null) return;
    final wait = expiresAt.subtract(_tokenRefreshMargin).difference(DateTime.now());
    _scheduleTokenRefresh(wait.isNegative ? Duration.zero : wait);
  }

  static void _scheduleTokenRefresh(Duration wait) {
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = Timer(wait, refreshUserToken);
  }

  /// Timers do not run while the app is suspended, so a token can expire
  /// unnoticed. Check once when the app comes back.
  static void _watchAppResume() {
    if (_resumeObserver != null) return;
    try {
      final observer = _ResumeObserver(() {
        final expiresAt = _tokenExpiresAt;
        if (expiresAt == null) return;
        if (DateTime.now().isAfter(expiresAt.subtract(_tokenRefreshMargin))) {
          refreshUserToken();
        }
      });
      WidgetsBinding.instance.addObserver(observer);
      _resumeObserver = observer;
    } catch (_) {
      // No binding (a background isolate): the timer alone has to do.
    }
  }

  /// `exp` from a JWT, or null when it cannot be read.
  static DateTime? _expiryOf(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length < 2) return null;
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final exp = (payload as Map)['exp'];
      if (exp is! num) return null;
      return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _handleMethod(MethodCall call) async {
    switch (call.method) {
      case 'onAwaitingUserToken':
        _onAwaitingUserToken?.call();
        break;

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

class _ResumeObserver with WidgetsBindingObserver {
  _ResumeObserver(this._onResumed);
  final void Function() _onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _onResumed();
  }
}
