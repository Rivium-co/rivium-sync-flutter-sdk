import 'dart:async';

import 'rivium_sync_version.dart';

/// Returns the signed user token for whoever is signed in, or null when no
/// one is. Usually one call to your own backend, which mints the token with
/// the project's server secret. The same function can serve Rivium Push and
/// Rivium Chat: it is one Rivium user token.
typedef RiviumSyncTokenProvider = FutureOr<String?> Function();

/// Conflict resolution strategy for offline sync
enum ConflictStrategy {
  /// Server data wins (default)
  serverWins,

  /// Client data wins
  clientWins,

  /// Automatically merge non-conflicting fields
  merge,

  /// Let the app decide via callback
  manual,
}

/// Configuration for RiviumSync SDK
class RiviumSyncConfig {
  /// Your RiviumSync API key from the Rivium Console (rv_live_xxx)
  final String apiKey;

  /// Optional user/device identifier for Security Rules.
  /// Used as `auth.uid` when evaluating database security rules.
  /// If not provided, the SDK auto-generates a stable device ID on the native side.
  ///
  /// The server cannot trust this value: anyone who unpacks your app can change
  /// it, and a project that enforces `requireSignedTokens` rejects it. Use
  /// [userToken] instead.
  final String? userId;

  /// A signed user token minted by YOUR backend, which holds the server secret
  /// (`POST /users/token`). This is what makes `auth.uid` trustworthy.
  ///
  /// Tokens are short lived - an hour by default. Call
  /// [RiviumSync.setUserToken] with a fresh one when you refresh it, for
  /// instance after your own session refresh or when the user signs in again.
  final String? userToken;

  /// Lets the SDK get the user token by itself: at [RiviumSync.init], again
  /// shortly before the token expires, and when the app returns to the
  /// foreground with an expired one. Call [RiviumSync.refreshUserToken] when
  /// the user signs in or out. Preferred over [userToken].
  final RiviumSyncTokenProvider? tokenProvider;

  /// Enable debug logging
  final bool debugMode;

  /// Automatically reconnect on disconnection
  final bool autoReconnect;

  /// Enable offline persistence
  /// When enabled, data is cached locally and operations work offline
  final bool offlineEnabled;

  /// Maximum cache size in megabytes
  /// Default is 100MB. Old documents are evicted when limit is reached.
  final int offlineCacheSizeMb;

  /// Automatically sync pending operations when connection is restored
  /// Default is true
  final bool syncOnReconnect;

  /// Conflict resolution strategy for offline sync
  /// Default is serverWins
  final ConflictStrategy conflictStrategy;

  /// No longer limits anything: as in Firestore, a write that could not be sent
  /// (no network, server error) is retried until it goes through, and one the
  /// server refuses is rolled back ([RiviumSync.documentRejections]). Kept so
  /// existing code compiles.
  @Deprecated('Writes are retried until they go through; refused ones are rolled back. This has no effect.')
  final int maxSyncRetries;

  /// For Rivium's own SDK tests; apps don't use this.
  final String? emulatorHost;

  /// For Rivium's own SDK tests; apps don't use this.
  final int emulatorPort;

  /// For Rivium's own SDK tests; apps don't use this.
  static const int defaultEmulatorPort = 3006;

  const RiviumSyncConfig({
    required this.apiKey,
    this.userId,
    this.userToken,
    this.tokenProvider,
    this.debugMode = false,
    this.autoReconnect = true,
    this.offlineEnabled = false,
    this.offlineCacheSizeMb = 100,
    this.syncOnReconnect = true,
    this.conflictStrategy = ConflictStrategy.serverWins,
    this.maxSyncRetries = 3,
    this.emulatorHost,
    this.emulatorPort = defaultEmulatorPort,
  });

  /// Throws an [ArgumentError] when [emulatorHost] or [emulatorPort] is not
  /// usable. Called by [toMap], before anything reaches the native SDK.
  void _checkEmulator() {
    final host = emulatorHost;
    if (host == null) return;
    final trimmed = host.trim();
    if (trimmed.isEmpty || trimmed.contains('/') || trimmed.contains(':')) {
      throw ArgumentError.value(host, 'emulatorHost',
          'a host name or IP address, without scheme or port');
    }
    if (emulatorPort < 1 || emulatorPort > 65535) {
      throw ArgumentError.value(
          emulatorPort, 'emulatorPort', 'must be 1-65535');
    }
  }

  Map<String, dynamic> toMap() {
    _checkEmulator();
    return {
      'apiKey': apiKey,
      if (userId != null) 'userId': userId,
      if (userToken != null) 'userToken': userToken,
      'debugMode': debugMode,
      'autoReconnect': autoReconnect,
      'offlineEnabled': offlineEnabled,
      'offlineCacheSizeMb': offlineCacheSizeMb,
      'syncOnReconnect': syncOnReconnect,
      'conflictStrategy': conflictStrategy.name,
      // The native SDK reports this plugin in the X-Rivium-SDK header.
      'wrapperSdkName': riviumSyncSdkName,
      'wrapperSdkVersion': riviumSyncSdkVersion,
      if (emulatorHost != null) 'emulatorHost': emulatorHost!.trim(),
      if (emulatorHost != null) 'emulatorPort': emulatorPort,
    };
  }
}
