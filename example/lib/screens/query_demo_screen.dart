import 'package:flutter/material.dart';
import 'package:rivium_sync/rivium_sync.dart';
import '../config.dart';
import '../widgets/result_card.dart';
import '../widgets/code_snippet.dart';

class QueryDemoScreen extends StatefulWidget {
  const QueryDemoScreen({super.key});

  @override
  State<QueryDemoScreen> createState() => _QueryDemoScreenState();
}

class _QueryDemoScreenState extends State<QueryDemoScreen> {
  late SyncCollection _collection;
  List<SyncDocument> _results = [];
  bool _isLoading = false;
  String? _lastQuery;
  String? _error;

  @override
  void initState() {
    super.initState();
    final db = RiviumSync.database(AppConfig.databaseId);
    _collection = db.collection(AppConfig.messagesCollection);
  }

  Future<void> _executeQuery(String queryName, Future<List<SyncDocument>> Function() queryFn) async {
    setState(() {
      _isLoading = true;
      _error = null;
      _lastQuery = queryName;
    });

    try {
      final results = await queryFn();
      setState(() {
        _results = results;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
        _results = [];
      });
    }
  }

  Future<void> _queryAll() async {
    await _executeQuery('Get All Documents', () async {
      return await _collection.getAll();
    });
  }

  Future<void> _queryWhereEquals() async {
    await _executeQuery('Where sender == "Test User"', () async {
      return await _collection
          .where('sender', QueryOperator.equal, 'Test User')
          .get();
    });
  }

  Future<void> _queryOrderBy() async {
    await _executeQuery('Order by timestamp (desc)', () async {
      return await _collection
          .query()
          .orderBy('timestamp', direction: OrderDirection.descending)
          .get();
    });
  }

  Future<void> _queryLimit() async {
    await _executeQuery('Limit to 5 documents', () async {
      return await _collection
          .query()
          .limit(5)
          .get();
    });
  }

  Future<void> _queryCompound() async {
    await _executeQuery('Compound query (where + orderBy + limit)', () async {
      return await _collection
          .where('sender', QueryOperator.equal, 'Test User')
          .orderBy('timestamp', direction: OrderDirection.descending)
          .limit(3)
          .get();
    });
  }

  Future<void> _createSampleData() async {
    setState(() => _isLoading = true);

    try {
      final senders = ['Alice', 'Bob', 'Test User', 'Charlie'];
      final messages = [
        'Hello everyone!',
        'How are you?',
        'Great to see you!',
        'This is a test message',
        'RiviumSync is awesome!',
      ];

      for (int i = 0; i < 10; i++) {
        await _collection.add({
          'message': messages[i % messages.length],
          'sender': senders[i % senders.length],
          'timestamp': DateTime.now().subtract(Duration(hours: i)).toIso8601String(),
          'priority': i % 3,
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Created 10 sample documents')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Query Operations'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_box),
            onPressed: _isLoading ? null : _createSampleData,
            tooltip: 'Create sample data',
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
              title: 'Query Examples',
              code: '''
// Get all documents
final docs = await collection.getAll();

// Where clause
final filtered = await collection
    .where('sender', QueryOperator.equal, 'Alice')
    .get();

// Order by
final sorted = await collection.query()
    .orderBy('timestamp', direction: OrderDirection.descending)
    .get();

// Limit results
final limited = await collection.query().limit(5).get();

// Compound query
final results = await collection
    .where('status', QueryOperator.equal, 'active')
    .orderBy('timestamp', direction: OrderDirection.descending)
    .limit(10)
    .get();''',
            ),
            const SizedBox(height: 16),

            // Query buttons
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Query Actions',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _isLoading ? null : _queryAll,
                          icon: const Icon(Icons.list),
                          label: const Text('Get All'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _isLoading ? null : _queryWhereEquals,
                          icon: const Icon(Icons.filter_alt),
                          label: const Text('Where'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _isLoading ? null : _queryOrderBy,
                          icon: const Icon(Icons.sort),
                          label: const Text('Order By'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _isLoading ? null : _queryLimit,
                          icon: const Icon(Icons.format_list_numbered),
                          label: const Text('Limit'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _isLoading ? null : _queryCompound,
                          icon: const Icon(Icons.join_inner),
                          label: const Text('Compound'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Results
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Results',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(width: 8),
                        if (_lastQuery != null)
                          Expanded(
                            child: Chip(
                              label: Text(
                                _lastQuery!,
                                style: const TextStyle(fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const Divider(),
                    if (_isLoading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_error != null)
                      ResultCard(
                        title: 'Error',
                        result: _error!,
                        isError: true,
                      )
                    else if (_results.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'No results. Run a query to see results here.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_results.length} documents found',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _results.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final doc = _results[index];
                              return ListTile(
                                dense: true,
                                title: Text(
                                  doc.data['message']?.toString() ?? 'No message',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  'sender: ${doc.data['sender']} | ID: ${doc.id.substring(0, 8)}...',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                trailing: doc.data['priority'] != null
                                    ? CircleAvatar(
                                        radius: 12,
                                        child: Text(
                                          '${doc.data['priority']}',
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                      )
                                    : null,
                              );
                            },
                          ),
                        ],
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
