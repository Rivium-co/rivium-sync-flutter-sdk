import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rivium_sync/rivium_sync.dart';

import '../app_config.dart';
import '../demo_token_minter.dart';

/// Checks for the default "owner only" Security Rules (each document's
/// `userId` must be the signed-in user): what the server refuses, and that the
/// SDK reports it instead of hiding it in the offline cache. Each button prints
/// PASS or FAIL with what it expected.
class RulesScreen extends StatefulWidget {
  const RulesScreen({super.key});

  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen> {
  late final SyncCollection _collection;
  final List<String> _log = [];
  ListenerRegistration? _documentListener;
  ListenerRegistration? _queryListener;
  Completer<String>? _rejected;
  bool _running = false;

  String get _profileId => 'profile_${AppConfig.userId}';

  @override
  void initState() {
    super.initState();
    _collection = RiviumSync.database(AppConfig.databaseId)
        .collection(AppConfig.todosCollection);
    _rejections = RiviumSync.documentRejections.listen((r) {
      _append('Sync: server refused queued ${r.operation.name} of ${r.documentId}: '
          '${r.error.message} (status ${r.error.statusCode})');
      final rejected = _rejected;
      if (rejected != null && !rejected.isCompleted) rejected.complete(r.documentId);
    });
  }

  StreamSubscription<DocumentRejection>? _rejections;

  @override
  void dispose() {
    _rejections?.cancel();
    _documentListener?.remove();
    _queryListener?.remove();
    super.dispose();
  }

  // ==================== Checks ====================

  Future<void> _refusedWrite() async {
    final pendingBefore = await RiviumSync.getPendingCount();
    Object? error;
    try {
      await _collection.add({'title': 'Not mine', 'userId': DemoTokenMinter.otherUserId});
    } catch (e) {
      error = e;
    }
    final status = error is RiviumSyncError ? error.statusCode : null;
    final queued = await RiviumSync.getPendingCount() - pendingBefore;
    _check(status == 403 && queued == 0, '403 and nothing queued',
        'status=$status, queued $queued, ${error ?? 'it was accepted'}');
  }

  Future<void> _refusedList() async {
    try {
      final docs = await _collection.getAll();
      _check(false, 'queryNotAllowed naming userId (not the cache)',
          'no error: ${docs.length} documents came back');
    } on RiviumSyncError catch (e) {
      _check(e.code == RiviumSyncErrorCode.queryNotAllowed && e.fields.contains('userId'),
          'queryNotAllowed naming userId (not the cache)', '$e');
    }
  }

  Future<void> _otherUsersTodos() async {
    try {
      final docs = await _collection
          .where('userId', QueryOperator.equal, DemoTokenMinter.otherUserId)
          .get();
      _check(false, 'queryNotAllowed', "no error: ${docs.length} of another user's todos came back");
    } on RiviumSyncError catch (e) {
      _check(e.code == RiviumSyncErrorCode.queryNotAllowed, 'queryNotAllowed', '$e');
    }
  }

  Future<void> _typedEquality() async {
    await _collection.add({'title': 'Typed', 'userId': AppConfig.userId, 'completed': false});
    final asText =
        (await AppConfig.mine(_collection).where('completed', QueryOperator.equal, 'false').get()).length;
    final asBoolean =
        (await AppConfig.mine(_collection).where('completed', QueryOperator.equal, false).get()).length;
    _check(asText == 0 && asBoolean >= 1, '"false" finds 0, false finds 1+',
        '"false" found $asText, false found $asBoolean');
  }

  Future<void> _setAndMerge() async {
    await _collection.set(_profileId, {'userId': AppConfig.userId, 'a': 1, 'b': 2});
    await _collection.set(_profileId, {'userId': AppConfig.userId, 'a': 9});
    final replaced = (await _collection.get(_profileId))?.data;
    await _collection.set(_profileId, {'c': 3}, merge: true);
    final merged = (await _collection.get(_profileId))?.data;
    _append('after set: $replaced');
    _append('after merge: $merged');
    final ok = replaced != null &&
        !replaced.containsKey('b') &&
        merged?['a'] == 9 &&
        merged?['c'] == 3 &&
        merged?['userId'] == AppConfig.userId;
    _check(ok, 'set drops b; merge keeps a + userId and adds c', 'set=$replaced, merge=$merged');
  }

  Future<void> _listenDocument() async {
    _documentListener?.remove();
    final heard = Completer<void>();
    final tick = DateTime.now().millisecondsSinceEpoch;
    await _collection.set(_profileId, {'userId': AppConfig.userId}, merge: true);
    _documentListener = _collection.listenDocument(
      _profileId,
      (doc) {
        _append('listenDocument: ${doc?.data}');
        if ((doc?.data['tick'] as num?)?.toInt() == tick && !heard.isCompleted) heard.complete();
      },
      onError: (e) => _append('listenDocument stopped: $e'),
    );
    await _collection.set(_profileId, {'tick': tick}, merge: true);
    final ok = await heard.future
        .then((_) => true)
        .timeout(const Duration(seconds: 10), onTimeout: () => false);
    _check(ok, 'the listener hears tick=$tick', 'nothing heard in 10 s');
  }

  Future<void> _batchAllOrNothing() async {
    final before = (await AppConfig.mine(_collection).get()).length;
    Object? error;
    try {
      await (RiviumSync.batch()
            ..create(_collection, {'title': 'Batch ok', 'userId': AppConfig.userId})
            ..create(_collection, {'title': 'Batch not mine', 'userId': DemoTokenMinter.otherUserId}))
          .commit();
    } catch (e) {
      error = e;
    }
    final after = (await AppConfig.mine(_collection).get()).length;
    _check(error != null && after == before, 'refused, and the allowed create is not saved either',
        'error=$error, my todos $before → $after');
  }

  Future<void> _offlineRefusedWrite() async {
    final rejected = _rejected = Completer<String>();
    await RiviumSync.disconnect();
    final queued =
        await _collection.add({'title': 'Queued, not mine', 'userId': DemoTokenMinter.otherUserId});
    _append('Offline: queued ${queued.id}; reconnecting');
    await RiviumSync.connect();
    final id = await rejected.future
        .then<String?>((id) => id)
        .timeout(const Duration(seconds: 15), onTimeout: () => null);
    _rejected = null;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final stillPending = await RiviumSync.getPendingCount();
    _check(id == queued.id && stillPending == 0, 'rejected and removed from the queue',
        'rejected=$id, still pending=$stillPending');
  }

  Future<void> _listenMine() async {
    _queryListener?.remove();
    _queryListener = AppConfig.mine(_collection).listen(
      (docs) => _append('listen: ${docs.length} todos'),
      onError: (e) => _append('listen stopped: $e'),
    );
    _append('Listening. In the Console, publish rules that deny reading todos: '
        'expect "listen stopped: RiviumSyncListenerError(listener_revoked)". '
        'Publish the old rules again after.');
  }

  Future<void> _switchUser() async {
    await DemoTokenMinter.switchUser();
    _append('Signed in as ${AppConfig.userId} (checks 1-3 now use the other user)');
  }

  // ==================== Output ====================

  Future<void> _run(String label, Future<void> Function() action) async {
    if (_running) return;
    setState(() => _running = true);
    _append('— $label');
    try {
      await action();
    } catch (e) {
      _append('✗ FAIL: unexpected $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  void _check(bool passed, String expected, String got) {
    _append(passed ? '✓ PASS: $expected' : '✗ FAIL: expected $expected; got $got');
  }

  void _append(String line) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final entry = '[${two(now.hour)}:${two(now.minute)}:${two(now.second)}] $line';
    debugPrint('RulesCheck: $line');
    if (mounted) setState(() => _log.add(entry));
  }

  @override
  Widget build(BuildContext context) {
    final checks = <(String, Future<void> Function())>[
      ("1. Write with another user's id → 403, not queued", _refusedWrite),
      ('2. List with no filter → queryNotAllowed', _refusedList),
      ("3. Another user's todos → refused", _otherUsersTodos),
      ('4. Typed equality: "false" ≠ false', _typedEquality),
      ('5. set replaces, set merge keeps', _setAndMerge),
      ('6. Listen to one document', _listenDocument),
      ('7. Batch is all or nothing', _batchAllOrNothing),
      ('8. Offline write the rules refuse is rolled back', _offlineRefusedWrite),
      ('9. Listen to my todos (then change rules in Console)', _listenMine),
      ('Switch user', _switchUser),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Security Rules')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Signed in as ${AppConfig.userId}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          if (!DemoTokenMinter.isConfigured)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('No serverSecret in config/local.json: no user token, so these checks fail.',
                  style: TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 8),
          for (final (label, action) in checks)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: OutlinedButton(
                onPressed: _running ? null : () => _run(label, action),
                child: Align(alignment: Alignment.centerLeft, child: Text(label)),
              ),
            ),
          TextButton(
            onPressed: () => setState(_log.clear),
            child: const Text('Clear log'),
          ),
          SelectableText(
            _log.join('\n'),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ],
      ),
    );
  }
}
