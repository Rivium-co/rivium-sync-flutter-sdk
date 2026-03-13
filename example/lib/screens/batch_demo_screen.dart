import 'package:flutter/material.dart';
import 'package:rivium_sync/rivium_sync.dart';
import '../config.dart';
import '../widgets/result_card.dart';
import '../widgets/code_snippet.dart';

class BatchDemoScreen extends StatefulWidget {
  const BatchDemoScreen({super.key});

  @override
  State<BatchDemoScreen> createState() => _BatchDemoScreenState();
}

class _BatchDemoScreenState extends State<BatchDemoScreen> {
  late SyncDatabase _db;
  late SyncCollection _collection;
  bool _isLoading = false;
  String? _result;
  bool _isError = false;
  List<String> _createdDocIds = [];

  @override
  void initState() {
    super.initState();
    _db = RiviumSync.database(AppConfig.databaseId);
    _collection = _db.collection(AppConfig.messagesCollection);
  }

  Future<void> _runBatchCreate() async {
    setState(() {
      _isLoading = true;
      _result = null;
      _isError = false;
    });

    try {
      final batch = _db.batch();
      final docIds = <String>[];

      // Add multiple documents to batch
      for (int i = 0; i < 5; i++) {
        final docId = 'batch-doc-${DateTime.now().millisecondsSinceEpoch}-$i';
        docIds.add(docId);
        batch.set(
          _collection,
          docId,
          {
            'message': 'Batch created document $i',
            'index': i,
            'createdAt': DateTime.now().toIso8601String(),
            'batchId': DateTime.now().millisecondsSinceEpoch.toString(),
          },
        );
      }

      await batch.commit();

      setState(() {
        _createdDocIds = docIds;
        _result = 'Successfully created ${docIds.length} documents:\n${docIds.join('\n')}';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _result = 'Error: $e';
        _isError = true;
        _isLoading = false;
      });
    }
  }

  Future<void> _runBatchUpdate() async {
    if (_createdDocIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create batch documents first')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _result = null;
      _isError = false;
    });

    try {
      final batch = _db.batch();

      for (final docId in _createdDocIds) {
        batch.update(
          _collection,
          docId,
          {
            'updatedAt': DateTime.now().toIso8601String(),
            'status': 'updated',
          },
        );
      }

      await batch.commit();

      setState(() {
        _result = 'Successfully updated ${_createdDocIds.length} documents';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _result = 'Error: $e';
        _isError = true;
        _isLoading = false;
      });
    }
  }

  Future<void> _runBatchDelete() async {
    if (_createdDocIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create batch documents first')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _result = null;
      _isError = false;
    });

    try {
      final batch = _db.batch();

      for (final docId in _createdDocIds) {
        batch.delete(_collection, docId);
      }

      await batch.commit();

      setState(() {
        _result = 'Successfully deleted ${_createdDocIds.length} documents';
        _createdDocIds = [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _result = 'Error: $e';
        _isError = true;
        _isLoading = false;
      });
    }
  }

  Future<void> _runMixedBatch() async {
    setState(() {
      _isLoading = true;
      _result = null;
      _isError = false;
    });

    try {
      final batch = _db.batch();
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      // Create 2 new documents
      batch.set(_collection, 'mixed-create-$timestamp-1', {
        'message': 'Mixed batch - created 1',
        'type': 'created',
        'timestamp': DateTime.now().toIso8601String(),
      });
      batch.set(_collection, 'mixed-create-$timestamp-2', {
        'message': 'Mixed batch - created 2',
        'type': 'created',
        'timestamp': DateTime.now().toIso8601String(),
      });

      // Update existing documents (if any)
      if (_createdDocIds.isNotEmpty) {
        batch.update(_collection, _createdDocIds.first, {
          'mixedBatchUpdate': true,
          'updatedAt': DateTime.now().toIso8601String(),
        });
      }

      await batch.commit();

      setState(() {
        _createdDocIds = ['mixed-create-$timestamp-1', 'mixed-create-$timestamp-2'];
        _result = '''Mixed batch completed:
- Created 2 new documents
- Updated ${_createdDocIds.isEmpty ? 0 : 1} existing document(s)

All operations were atomic - either all succeed or all fail.''';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _result = 'Error: $e';
        _isError = true;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Batch Operations'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Code example
            const CodeSnippet(
              title: 'Batch Write Example',
              code: '''
// Create a batch
final batch = database.batch();

// Add operations
batch.set(collection, 'doc1', {'name': 'Alice'});
batch.set(collection, 'doc2', {'name': 'Bob'});
batch.update(collection, 'doc3', {'status': 'active'});
batch.delete(collection, 'doc4');

// Commit atomically - all succeed or all fail
await batch.commit();''',
            ),
            const SizedBox(height: 16),

            // Info card
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Batch operations are atomic - either all operations succeed or all fail. This is useful for maintaining data consistency.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Actions
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Batch Actions',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (_createdDocIds.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          '${_createdDocIds.length} documents tracked for update/delete',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                        ),
                      ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _isLoading ? null : _runBatchCreate,
                          icon: const Icon(Icons.add),
                          label: const Text('Batch Create'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _isLoading ? null : _runBatchUpdate,
                          icon: const Icon(Icons.edit),
                          label: const Text('Batch Update'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _isLoading ? null : _runBatchDelete,
                          icon: const Icon(Icons.delete),
                          label: const Text('Batch Delete'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _isLoading ? null : _runMixedBatch,
                          icon: const Icon(Icons.shuffle),
                          label: const Text('Mixed Batch'),
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
