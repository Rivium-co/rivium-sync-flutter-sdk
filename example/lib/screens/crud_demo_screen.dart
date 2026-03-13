import 'package:flutter/material.dart';
import 'package:rivium_sync/rivium_sync.dart';
import '../config.dart';
import '../widgets/result_card.dart';
import '../widgets/code_snippet.dart';

class CrudDemoScreen extends StatefulWidget {
  const CrudDemoScreen({super.key});

  @override
  State<CrudDemoScreen> createState() => _CrudDemoScreenState();
}

class _CrudDemoScreenState extends State<CrudDemoScreen> {
  late SyncCollection _collection;
  List<SyncDocument> _documents = [];
  String? _lastResult;
  bool _isLoading = false;
  String? _selectedDocId;

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final db = RiviumSync.database(AppConfig.databaseId);
    _collection = db.collection(AppConfig.todosCollection);
    _loadDocuments();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadDocuments() async {
    setState(() => _isLoading = true);
    try {
      print('Loading documents from collection: ${_collection.id}');
      final docs = await _collection.getAll();
      print('Loaded ${docs.length} documents');
      for (var doc in docs) {
        print('  Doc: ${doc.id} - ${doc.data}');
      }
      setState(() {
        _documents = docs;
        _lastResult = 'Loaded ${docs.length} documents';
      });
    } catch (e, stackTrace) {
      print('Error loading documents: $e');
      print('Stack trace: $stackTrace');
      setState(() => _lastResult = 'Error loading: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _createDocument() async {
    if (_titleController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a title')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final doc = await _collection.add({
        'title': _titleController.text,
        'description': _descriptionController.text,
        'completed': false,
        'createdAt': DateTime.now().toIso8601String(),
      });

      _titleController.clear();
      _descriptionController.clear();

      setState(() {
        _lastResult = 'Created document: ${doc.id}';
      });

      await _loadDocuments();
    } catch (e) {
      setState(() => _lastResult = 'Error creating: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _readDocument(String docId) async {
    setState(() => _isLoading = true);
    try {
      final doc = await _collection.get(docId);
      if (doc != null) {
        setState(() {
          _lastResult = 'Read document:\n'
              'ID: ${doc.id}\n'
              'Data: ${doc.data}\n'
              'Version: ${doc.version}\n'
              'CreatedAt: ${doc.createdAt}\n'
              'UpdatedAt: ${doc.updatedAt}';
          _selectedDocId = docId;
        });
      } else {
        setState(() => _lastResult = 'Document not found');
      }
    } catch (e) {
      setState(() => _lastResult = 'Error reading: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateDocument(String docId) async {
    setState(() => _isLoading = true);
    try {
      final doc = await _collection.update(docId, {
        'updatedAt': DateTime.now().toIso8601String(),
        'description': 'Updated at ${DateTime.now().toLocal()}',
      });

      setState(() {
        _lastResult = 'Updated document: ${doc.id}\nNew version: ${doc.version}';
      });

      await _loadDocuments();
    } catch (e) {
      setState(() => _lastResult = 'Error updating: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleComplete(String docId, bool currentValue) async {
    setState(() => _isLoading = true);
    try {
      await _collection.update(docId, {
        'completed': !currentValue,
        'completedAt': !currentValue ? DateTime.now().toIso8601String() : null,
      });

      setState(() {
        _lastResult = 'Toggled completed: ${!currentValue}';
      });

      await _loadDocuments();
    } catch (e) {
      setState(() => _lastResult = 'Error toggling: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteDocument(String docId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Document'),
        content: const Text('Are you sure you want to delete this document?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      await _collection.delete(docId);
      setState(() {
        _lastResult = 'Deleted document: $docId';
        if (_selectedDocId == docId) _selectedDocId = null;
      });
      await _loadDocuments();
    } catch (e) {
      setState(() => _lastResult = 'Error deleting: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CRUD Operations'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDocuments,
            tooltip: 'Refresh',
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
              title: 'CRUD Example',
              code: '''
// Create
final doc = await collection.add({
  'title': 'My Task',
  'completed': false,
});

// Read
final doc = await collection.get('doc-id');

// Update
await collection.update('doc-id', {
  'completed': true,
});

// Delete
await collection.delete('doc-id');''',
            ),
            const SizedBox(height: 16),

            // Create Form
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Create Document',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _isLoading ? null : _createDocument,
                      icon: const Icon(Icons.add),
                      label: const Text('Create'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Documents List
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Documents',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        Text(
                          '${_documents.length} items',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const Divider(),
                    if (_isLoading && _documents.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_documents.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'No documents yet. Create one above!',
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _documents.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final doc = _documents[index];
                          final completed =
                              doc.data['completed'] as bool? ?? false;
                          return ListTile(
                            leading: Checkbox(
                              value: completed,
                              onChanged: (_) =>
                                  _toggleComplete(doc.id, completed),
                            ),
                            title: Text(
                              doc.data['title']?.toString() ?? 'Untitled',
                              style: TextStyle(
                                decoration: completed
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            subtitle: Text(
                              doc.data['description']?.toString() ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            selected: _selectedDocId == doc.id,
                            trailing: PopupMenuButton<String>(
                              itemBuilder: (context) => [
                                PopupMenuItem<String>(
                                  value: 'read',
                                  child: Row(
                                    children: const [
                                      Icon(Icons.visibility),
                                      SizedBox(width: 12),
                                      Text('Read'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem<String>(
                                  value: 'update',
                                  child: Row(
                                    children: const [
                                      Icon(Icons.edit),
                                      SizedBox(width: 12),
                                      Text('Update'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem<String>(
                                  value: 'delete',
                                  child: Row(
                                    children: const [
                                      Icon(Icons.delete, color: Colors.red),
                                      SizedBox(width: 12),
                                      Text('Delete',
                                          style: TextStyle(color: Colors.red)),
                                    ],
                                  ),
                                ),
                              ],
                              onSelected: (value) {
                                // Unfocus any text field first
                                FocusScope.of(context).unfocus();
                                switch (value) {
                                  case 'read':
                                    _readDocument(doc.id);
                                    break;
                                  case 'update':
                                    _updateDocument(doc.id);
                                    break;
                                  case 'delete':
                                    _deleteDocument(doc.id);
                                    break;
                                }
                              },
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Result Card
            if (_lastResult != null)
              ResultCard(
                title: 'Last Operation Result',
                result: _lastResult!,
              ),
          ],
        ),
      ),
    );
  }
}
