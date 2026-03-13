import 'package:flutter/material.dart';
import 'package:rivium_sync/rivium_sync.dart';
import '../config.dart';
import '../widgets/result_card.dart';
import '../widgets/code_snippet.dart';

class RealtimeDemoScreen extends StatefulWidget {
  const RealtimeDemoScreen({super.key});

  @override
  State<RealtimeDemoScreen> createState() => _RealtimeDemoScreenState();
}

class _RealtimeDemoScreenState extends State<RealtimeDemoScreen> {
  late SyncCollection _collection;
  ListenerRegistration? _collectionListener;
  ListenerRegistration? _documentListener;

  List<SyncDocument> _documents = [];
  SyncDocument? _watchedDocument;
  String? _watchedDocId;
  List<String> _eventLog = [];
  bool _isListeningCollection = false;
  bool _isListeningDocument = false;

  @override
  void initState() {
    super.initState();
    final db = RiviumSync.database(AppConfig.databaseId);
    _collection = db.collection(AppConfig.messagesCollection);
  }

  @override
  void dispose() {
    _collectionListener?.remove();
    _documentListener?.remove();
    super.dispose();
  }

  void _addToLog(String message) {
    setState(() {
      _eventLog.insert(0, '[${DateTime.now().toLocal().toString().substring(11, 19)}] $message');
      if (_eventLog.length > 50) {
        _eventLog.removeLast();
      }
    });
  }

  void _startCollectionListener() {
    if (_isListeningCollection) return;

    _collectionListener = _collection.listen(
      (documents) {
        setState(() {
          _documents = documents;
        });
        _addToLog('Collection updated: ${documents.length} documents');
      },
      onError: (error) {
        _addToLog('Collection error: $error');
      },
    );

    setState(() => _isListeningCollection = true);
    _addToLog('Started listening to collection');
  }

  void _stopCollectionListener() {
    _collectionListener?.remove();
    _collectionListener = null;
    setState(() {
      _isListeningCollection = false;
      _documents = [];
    });
    _addToLog('Stopped listening to collection');
  }

  void _startDocumentListener(String docId) {
    _documentListener?.remove();

    _documentListener = _collection.listenDocument(
      docId,
      (document) {
        setState(() {
          _watchedDocument = document;
          _watchedDocId = docId;
        });
        if (document != null) {
          _addToLog('Document updated: ${document.data}');
        } else {
          _addToLog('Document deleted');
        }
      },
      onError: (error) {
        _addToLog('Document error: $error');
      },
    );

    setState(() => _isListeningDocument = true);
    _addToLog('Started listening to document: $docId');
  }

  void _stopDocumentListener() {
    _documentListener?.remove();
    _documentListener = null;
    setState(() {
      _isListeningDocument = false;
      _watchedDocument = null;
      _watchedDocId = null;
    });
    _addToLog('Stopped listening to document');
  }

  Future<void> _createTestDocument() async {
    try {
      final doc = await _collection.add({
        'message': 'Hello at ${DateTime.now().toLocal()}',
        'sender': 'Test User',
        'timestamp': DateTime.now().toIso8601String(),
      });
      _addToLog('Created document: ${doc.id}');

      // Auto-start collection listener if not active so user can see the new document
      if (!_isListeningCollection) {
        _addToLog('Auto-starting collection listener...');
        _startCollectionListener();
      }
    } catch (e) {
      _addToLog('Error creating: $e');
    }
  }

  Future<void> _updateRandomDocument() async {
    if (_documents.isEmpty) {
      _addToLog('No documents to update. Create a document first!');
      return;
    }

    final doc = _documents.first;
    try {
      await _collection.update(doc.id, {
        'message': 'Updated at ${DateTime.now().toLocal()}',
        'updatedAt': DateTime.now().toIso8601String(),
      });
      _addToLog('Updated document: ${doc.id}');
    } catch (e) {
      _addToLog('Error updating: $e');
    }
  }

  Future<void> _deleteRandomDocument() async {
    if (_documents.isEmpty) {
      _addToLog('No documents to delete. Create a document first!');
      return;
    }

    final doc = _documents.last;
    try {
      await _collection.delete(doc.id);
      _addToLog('Deleted document: ${doc.id}');
    } catch (e) {
      _addToLog('Error deleting: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Realtime Listeners'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Code example
            const CodeSnippet(
              title: 'Realtime Listener Example',
              code: '''
// Listen to collection changes
final listener = collection.listen((documents) {
  print('Collection updated: \${documents.length}');
});

// Listen to specific document
final docListener = collection.listenDocument(
  'doc-id',
  (document) {
    if (document != null) {
      print('Document changed: \${document.data}');
    } else {
      print('Document was deleted');
    }
  },
);

// Stop listening
listener.remove();
docListener.remove();''',
            ),
            const SizedBox(height: 16),

            // Collection Listener Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isListeningCollection
                              ? Icons.hearing
                              : Icons.hearing_disabled,
                          color: _isListeningCollection
                              ? Colors.green
                              : Colors.grey,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Collection Listener',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Switch(
                          value: _isListeningCollection,
                          onChanged: (value) {
                            if (value) {
                              _startCollectionListener();
                            } else {
                              _stopCollectionListener();
                            }
                          },
                        ),
                      ],
                    ),
                    if (_isListeningCollection && _documents.isNotEmpty) ...[
                      const Divider(),
                      Text(
                        '${_documents.length} documents',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 150,
                        child: ListView.builder(
                          itemCount: _documents.length,
                          itemBuilder: (context, index) {
                            final doc = _documents[index];
                            return ListTile(
                              dense: true,
                              title: Text(
                                doc.data['message']?.toString() ?? 'No message',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                'ID: ${doc.id.substring(0, 8)}...',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.visibility, size: 20),
                                onPressed: () =>
                                    _startDocumentListener(doc.id),
                                tooltip: 'Watch this document',
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Document Listener Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isListeningDocument
                              ? Icons.visibility
                              : Icons.visibility_off,
                          color:
                              _isListeningDocument ? Colors.blue : Colors.grey,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Document Listener',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              if (_watchedDocId != null)
                                Text(
                                  'Watching: ${_watchedDocId!.substring(0, 8)}...',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                        if (_isListeningDocument)
                          TextButton(
                            onPressed: _stopDocumentListener,
                            child: const Text('Stop'),
                          ),
                      ],
                    ),
                    if (_watchedDocument != null) ...[
                      const Divider(),
                      Text(
                        'Document Data:',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _watchedDocument!.data.toString(),
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Test Actions Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Test Actions',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Trigger changes to see realtime updates',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _createTestDocument,
                          icon: const Icon(Icons.add),
                          label: const Text('Create'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _updateRandomDocument,
                          icon: const Icon(Icons.edit),
                          label: const Text('Update'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _deleteRandomDocument,
                          icon: const Icon(Icons.delete),
                          label: const Text('Delete'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Event Log Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Event Log',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () =>
                              setState(() => _eventLog.clear()),
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                    const Divider(),
                    if (_eventLog.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'No events yet. Start a listener and make changes!',
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      SizedBox(
                        height: 200,
                        child: ListView.builder(
                          itemCount: _eventLog.length,
                          itemBuilder: (context, index) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                _eventLog[index],
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
