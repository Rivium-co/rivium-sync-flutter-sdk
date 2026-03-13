import 'package:flutter/material.dart';
import 'package:rivium_sync/rivium_sync.dart';
import '../config.dart';
import '../widgets/result_card.dart';
import '../widgets/code_snippet.dart';

class OfflineDemoScreen extends StatefulWidget {
  const OfflineDemoScreen({super.key});

  @override
  State<OfflineDemoScreen> createState() => _OfflineDemoScreenState();
}

class _OfflineDemoScreenState extends State<OfflineDemoScreen> {
  late SyncCollection _collection;
  bool _isLoading = false;
  String? _result;
  bool _isError = false;
  int _pendingCount = 0;
  SyncState _syncState = SyncState.idle;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    final db = RiviumSync.database(AppConfig.databaseId);
    _collection = db.collection(AppConfig.messagesCollection);
    _checkStatus();

    // Listen to sync state changes
    RiviumSync.onSyncState((state) {
      setState(() => _syncState = state);
    });

    // Listen to pending count changes
    RiviumSync.onPendingCount((count) {
      setState(() => _pendingCount = count);
    });

    // Listen to connection state
    RiviumSync.onConnectionState((connected) {
      setState(() => _isConnected = connected);
    });
  }

  Future<void> _checkStatus() async {
    try {
      final connected = await RiviumSync.isConnected();
      final syncState = await RiviumSync.getSyncState();
      final pending = await RiviumSync.getPendingCount();

      setState(() {
        _isConnected = connected;
        _syncState = syncState;
        _pendingCount = pending;
      });
    } catch (e) {
      // Silently handle - status methods may not be available
    }
  }

  Future<void> _createDocument() async {
    setState(() {
      _isLoading = true;
      _result = null;
    });

    try {
      final doc = await _collection.add({
        'message': 'Created at ${DateTime.now().toLocal()}',
        'timestamp': DateTime.now().toIso8601String(),
        'isConnected': _isConnected,
      });

      setState(() {
        _result = '''Document created: ${doc.id}
Connection: ${_isConnected ? "Online - synced immediately" : "Offline - queued for sync"}''';
        _isError = false;
      });
    } catch (e) {
      setState(() {
        _result = 'Error creating document: $e';
        _isError = true;
      });
    } finally {
      setState(() => _isLoading = false);
      await _checkStatus();
    }
  }

  Future<void> _forceSyncNow() async {
    setState(() {
      _isLoading = true;
      _result = null;
    });

    try {
      await RiviumSync.forceSyncNow();
      setState(() {
        _result = 'Force sync triggered';
        _isError = false;
      });
    } catch (e) {
      setState(() {
        _result = 'Error syncing: $e';
        _isError = true;
      });
    } finally {
      setState(() => _isLoading = false);
      await _checkStatus();
    }
  }

  Future<void> _clearLocalCache() async {
    setState(() {
      _isLoading = true;
      _result = null;
    });

    try {
      await RiviumSync.clearOfflineCache();
      setState(() {
        _result = 'Local cache cleared';
        _isError = false;
      });
    } catch (e) {
      setState(() {
        _result = 'Error clearing cache: $e';
        _isError = true;
      });
    } finally {
      setState(() => _isLoading = false);
      await _checkStatus();
    }
  }

  Future<void> _readDocuments() async {
    setState(() {
      _isLoading = true;
      _result = null;
    });

    try {
      final docs = await _collection.getAll();
      setState(() {
        _result = '''Read ${docs.length} documents:
${docs.take(3).map((d) => '- ${d.id.substring(0, 8)}...: ${d.data['message'] ?? 'no message'}').join('\n')}
${docs.length > 3 ? '... and ${docs.length - 3} more' : ''}''';
        _isError = false;
      });
    } catch (e) {
      setState(() {
        _result = 'Error reading documents: $e';
        _isError = true;
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _syncStateToString(SyncState state) {
    switch (state) {
      case SyncState.idle:
        return 'Idle';
      case SyncState.syncing:
        return 'Syncing...';
      case SyncState.offline:
        return 'Offline';
      case SyncState.error:
        return 'Error';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Persistence'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkStatus,
            tooltip: 'Refresh status',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Code example
            const CodeSnippet(
              title: 'Offline Persistence Example',
              code: '''
// Enable offline persistence (in initialization)
await RiviumSync.init(RiviumSyncConfig(
  apiKey: 'your-api-key',
  offlineEnabled: true,
));

// Listen to sync state changes
RiviumSync.onSyncState((state) {
  print('Sync state: \$state');
});

// Listen to pending count changes
RiviumSync.onPendingCount((count) {
  print('Pending writes: \$count');
});

// Force sync pending writes
await RiviumSync.forceSyncNow();

// Clear local cache
await RiviumSync.clearOfflineCache();''',
            ),
            const SizedBox(height: 16),

            // Status Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isConnected ? Icons.cloud_done : Icons.cloud_off,
                          color: _isConnected ? Colors.green : Colors.orange,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isConnected ? 'Connected' : 'Disconnected',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                'Sync state: ${_syncStateToString(_syncState)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Chip(
                          label: Text(
                            RiviumSync.isOfflineEnabled ? 'Offline enabled' : 'Online only',
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _StatusItem(
                            icon: Icons.pending_actions,
                            label: 'Pending Writes',
                            value: '$_pendingCount',
                          ),
                        ),
                        Expanded(
                          child: _StatusItem(
                            icon: _syncState == SyncState.syncing
                                ? Icons.sync
                                : Icons.cloud_queue,
                            label: 'Sync State',
                            value: _syncStateToString(_syncState),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Actions Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Test Offline Features',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _isLoading ? null : _createDocument,
                          icon: const Icon(Icons.add),
                          label: const Text('Create Document'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _isLoading ? null : _readDocuments,
                          icon: const Icon(Icons.list),
                          label: const Text('Read Documents'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _isLoading || _pendingCount == 0
                              ? null
                              : _forceSyncNow,
                          icon: const Icon(Icons.sync),
                          label: const Text('Force Sync'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _isLoading ? null : _clearLocalCache,
                          icon: const Icon(Icons.delete_sweep),
                          label: const Text('Clear Cache'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Result
            if (_isLoading)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (_result != null)
              ResultCard(
                title: _isError ? 'Error' : 'Result',
                result: _result!,
                isError: _isError,
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatusItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.outline),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
