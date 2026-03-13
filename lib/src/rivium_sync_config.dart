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
  /// Your RiviumSync API key from the Rivium Console (rv_live_xxx or rv_test_xxx)
  final String apiKey;

  /// Optional user/device identifier for Security Rules.
  /// Used as `auth.uid` when evaluating database security rules.
  /// If not provided, the SDK auto-generates a stable device ID on the native side.
  final String? userId;

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

  /// Maximum number of sync retries for failed operations
  /// Default is 3
  final int maxSyncRetries;

  const RiviumSyncConfig({
    required this.apiKey,
    this.userId,
    this.debugMode = false,
    this.autoReconnect = true,
    this.offlineEnabled = false,
    this.offlineCacheSizeMb = 100,
    this.syncOnReconnect = true,
    this.conflictStrategy = ConflictStrategy.serverWins,
    this.maxSyncRetries = 3,
  });

  Map<String, dynamic> toMap() => {
        'apiKey': apiKey,
        if (userId != null) 'userId': userId,
        'debugMode': debugMode,
        'autoReconnect': autoReconnect,
        'offlineEnabled': offlineEnabled,
        'offlineCacheSizeMb': offlineCacheSizeMb,
        'syncOnReconnect': syncOnReconnect,
        'conflictStrategy': conflictStrategy.name,
        'maxSyncRetries': maxSyncRetries,
      };
}
