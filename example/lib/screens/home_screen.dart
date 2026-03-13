import 'package:flutter/material.dart';
import 'package:rivium_sync/rivium_sync.dart';
import 'crud_demo_screen.dart';
import 'realtime_demo_screen.dart';
import 'query_demo_screen.dart';
import 'batch_demo_screen.dart';
import 'offline_demo_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isConnected = false;
  bool _isConnecting = false;
  SyncState _syncState = SyncState.idle;
  int _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    _setupListeners();
    _checkConnection();
    _autoConnect();
  }

  Future<void> _autoConnect() async {
    // Auto-connect on startup if not already connected
    final connected = await RiviumSync.isConnected();
    if (!connected) {
      try {
        await RiviumSync.connect();
      } catch (e) {
        // Silently fail auto-connect, user can manually connect
      }
    }
  }

  void _setupListeners() {
    RiviumSync.onConnectionState((connected) {
      setState(() => _isConnected = connected);
    });

    RiviumSync.onSyncState((state) {
      setState(() => _syncState = state);
    });

    RiviumSync.onPendingCount((count) {
      setState(() => _pendingCount = count);
    });
  }

  Future<void> _checkConnection() async {
    final connected = await RiviumSync.isConnected();
    setState(() => _isConnected = connected);
  }

  Future<void> _toggleConnection() async {
    setState(() => _isConnecting = true);
    try {
      if (_isConnected) {
        await RiviumSync.disconnect();
      } else {
        await RiviumSync.connect();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RiviumSync Example'),
        actions: [
          // Connection status indicator
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isConnected ? Colors.green : Colors.red,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _isConnected ? 'Connected' : 'Disconnected',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Card
            _buildHeaderCard(),
            const SizedBox(height: 16),

            // Connection Card
            _buildConnectionCard(),
            const SizedBox(height: 16),

            // Status Card (Offline info)
            if (RiviumSync.isOfflineEnabled) ...[
              _buildStatusCard(),
              const SizedBox(height: 16),
            ],

            // Demo Cards
            const Text(
              'Demo Features',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            _buildDemoCard(
              icon: Icons.edit_document,
              title: 'CRUD Operations',
              description: 'Create, Read, Update, Delete documents',
              color: Colors.blue,
              onTap: () => _navigateTo(const CrudDemoScreen()),
            ),

            _buildDemoCard(
              icon: Icons.sync,
              title: 'Realtime Listeners',
              description: 'Listen to document and collection changes',
              color: Colors.green,
              onTap: () => _navigateTo(const RealtimeDemoScreen()),
            ),

            _buildDemoCard(
              icon: Icons.search,
              title: 'Query Operations',
              description: 'Filter, sort, and paginate data',
              color: Colors.purple,
              onTap: () => _navigateTo(const QueryDemoScreen()),
            ),

            _buildDemoCard(
              icon: Icons.layers,
              title: 'Batch Operations',
              description: 'Atomic multi-document writes',
              color: Colors.orange,
              onTap: () => _navigateTo(const BatchDemoScreen()),
            ),

            _buildDemoCard(
              icon: Icons.wifi_off,
              title: 'Offline Persistence',
              description: 'Work offline with automatic sync',
              color: Colors.teal,
              onTap: () => _navigateTo(const OfflineDemoScreen()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_sync,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'RiviumSync SDK',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Version ${RiviumSync.version}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              'A Firebase-like realtime database for instant data synchronization',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _isConnected ? Icons.cloud_done : Icons.cloud_off,
                  color: _isConnected ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Realtime Connection',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        _isConnected
                            ? 'Connected to RiviumSync server'
                            : 'Not connected',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonal(
                  onPressed: _isConnecting ? null : _toggleConnection,
                  child: _isConnecting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isConnected ? 'Disconnect' : 'Connect'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sync Status',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildStatusChip(
                  'State',
                  _syncState.name.toUpperCase(),
                  _getSyncStateColor(),
                ),
                const SizedBox(width: 12),
                _buildStatusChip(
                  'Pending',
                  _pendingCount.toString(),
                  _pendingCount > 0 ? Colors.orange : Colors.green,
                ),
              ],
            ),
            if (_pendingCount > 0) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () => RiviumSync.forceSyncNow(),
                icon: const Icon(Icons.sync),
                label: const Text('Force Sync Now'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Color _getSyncStateColor() {
    switch (_syncState) {
      case SyncState.idle:
        return Colors.green;
      case SyncState.syncing:
        return Colors.blue;
      case SyncState.offline:
        return Colors.orange;
      case SyncState.error:
        return Colors.red;
    }
  }

  Widget _buildDemoCard({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateTo(Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }
}
