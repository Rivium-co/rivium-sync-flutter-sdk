import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivium_sync/rivium_sync.dart';

/// 0.3.0: set() replaces unless merge is asked for, and listeners / queries report the security rules' typed errors.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const method = MethodChannel('co.rivium.sync/rivium_sync');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall call) answer;

  setUp(() {
    calls = [];
    answer = (call) async => null;
    messenger.setMockMethodCallHandler(method, (call) {
      calls.add(call);
      return answer(call);
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(method, null));

  final todos = SyncCollection(method, 'my-app', 'todos', 'todos');
  final nativeDoc = {
    'id': 'todo-1',
    'data': {'title': 'Buy milk', 'completed': false},
    'createdAt': 1,
    'updatedAt': 2,
    'version': 3,
  };

  group('set', () {
    test('replaces by default: merge false is sent', () async {
      answer = (_) async => nativeDoc;
      await todos.set('todo-1', {'title': 'Buy milk'});
      final args = calls.single.arguments as Map;
      expect(calls.single.method, 'setDocument');
      expect(args['merge'], false);
      expect(args['data'], {'title': 'Buy milk'});
    });

    test('merge: true is sent', () async {
      answer = (_) async => nativeDoc;
      await todos.set('todo-1', {'completed': true}, merge: true);
      expect((calls.single.arguments as Map)['merge'], true);
    });

    test('the native document is read as is (no extra data wrapper)', () async {
      answer = (_) async => nativeDoc;
      final doc = await todos.set('todo-1', {'title': 'Buy milk', 'completed': false});
      expect(doc.id, 'todo-1');
      expect(doc.data, {'title': 'Buy milk', 'completed': false});
      expect(doc.version, 3);
    });
  });

  group('batch set', () {
    test('replaces by default and merges when asked', () async {
      final batch = WriteBatch(method)
        ..set(todos, 'a', {'x': 1})
        ..set(todos, 'b', {'y': 2}, merge: true);
      await batch.commit();
      final ops = (calls.single.arguments as Map)['operations'] as List;
      expect((ops[0] as Map)['merge'], false);
      expect((ops[1] as Map)['merge'], true);
      expect((ops[1] as Map)['type'], 'set');
    });
  });

  group('query get()', () {
    test('query_not_allowed becomes a typed RiviumSyncError with fields', () async {
      answer = (_) async => throw PlatformException(
            code: 'query_not_allowed',
            message: 'Add a filter on teamId',
            details: {
              'fields': ['teamId']
            },
          );
      await expectLater(
        todos.where('done', QueryOperator.equal, false).get(),
        throwsA(isA<RiviumSyncError>()
            .having((e) => e.code, 'code', RiviumSyncErrorCode.queryNotAllowed)
            .having((e) => e.message, 'message', 'Add a filter on teamId')
            .having((e) => e.fields, 'fields', ['teamId'])),
      );
    });

    test('query_not_allowed without fields has an empty list', () async {
      answer = (_) async => throw PlatformException(code: 'query_not_allowed', message: 'no');
      await expectLater(
        todos.query().get(),
        throwsA(isA<RiviumSyncError>().having((e) => e.fields, 'fields', isEmpty)),
      );
    });

    test('other errors become a RiviumSyncError with no status', () async {
      answer = (_) async => throw PlatformException(code: 'QUERY_ERROR', message: 'offline');
      await expectLater(
        todos.query().get(),
        throwsA(isA<RiviumSyncError>()
            .having((e) => e.code, 'code', RiviumSyncErrorCode.databaseError)
            .having((e) => e.message, 'message', 'offline')
            .having((e) => e.statusCode, 'statusCode', isNull)),
      );
    });

    test('documents are read as the native side sends them', () async {
      answer = (_) async => [nativeDoc];
      final docs = await todos.query().get();
      expect(docs.single.data['title'], 'Buy milk');
    });
  });

  group('listener errors', () {
    MockStreamHandlerEventSink? sink;
    late List<Map> started;

    void mockEvents(String channel) {
      sink = null;
      messenger.setMockStreamHandler(
        EventChannel(channel),
        MockStreamHandler.inline(onListen: (_, events) => sink = events),
      );
    }

    setUp(() {
      started = [];
      answer = (call) async {
        if (call.method.startsWith('listen')) started.add(call.arguments as Map);
        return null;
      };
    });

    tearDown(() {
      for (final c in ['collection', 'document', 'query']) {
        messenger.setMockStreamHandler(EventChannel('co.rivium.sync/${c}_events'), null);
      }
    });

    test('query listener: query_not_allowed with fields', () async {
      mockEvents('co.rivium.sync/query_events');
      final errors = <Object>[];
      final docs = <List<SyncDocument>>[];
      final reg = todos.where('done', QueryOperator.equal, false).listen(docs.add, onError: errors.add);
      await pumpEventQueue();
      final id = started.single['listenerId'];

      sink!.success({
        'listenerId': id,
        'error': {
          'code': 'query_not_allowed',
          'message': 'Add a filter on teamId',
          'fields': ['teamId'],
          'statusCode': 403,
        },
      });
      await pumpEventQueue();

      expect(docs, isEmpty);
      final error = errors.single as RiviumSyncListenerError;
      expect(error.code, RiviumSyncListenerError.queryNotAllowed);
      expect(error.isQueryNotAllowed, isTrue);
      expect(error.fields, ['teamId']);
      expect(error.statusCode, 403);
      expect(error.message, 'Add a filter on teamId');
      reg.remove();
    });

    test('collection listener: listener_revoked', () async {
      mockEvents('co.rivium.sync/collection_events');
      final errors = <Object>[];
      final docs = <List<SyncDocument>>[];
      final reg = todos.listen(docs.add, onError: errors.add);
      await pumpEventQueue();
      final id = started.single['listenerId'];

      sink!.success({'listenerId': id, 'documents': [nativeDoc]});
      sink!.success({
        'listenerId': id,
        'error': {'code': 'listener_revoked', 'message': 'This listener was stopped'},
      });
      await pumpEventQueue();

      expect(docs.single.single.id, 'todo-1');
      final error = errors.single as RiviumSyncListenerError;
      expect(error.isListenerRevoked, isTrue);
      expect(error.fields, isEmpty);
      expect(error.statusCode, isNull);
      reg.remove();
    });

    test('document listener: permission_denied, and the document is unwrapped', () async {
      mockEvents('co.rivium.sync/document_events');
      final errors = <Object>[];
      final docs = <SyncDocument?>[];
      final reg = todos.listenDocument('todo-1', docs.add, onError: errors.add);
      await pumpEventQueue();
      final id = started.single['listenerId'];
      expect(started.single['documentId'], 'todo-1');

      sink!.success({'listenerId': id, 'document': nativeDoc});
      sink!.success({'listenerId': id, 'document': null});
      sink!.success({
        'listenerId': id,
        'error': {'code': 'permission_denied', 'message': 'Read permission denied', 'statusCode': 403},
      });
      await pumpEventQueue();

      expect(docs[0]!.data['title'], 'Buy milk');
      expect(docs[1], isNull, reason: 'deleted');
      expect((errors.single as RiviumSyncListenerError).code, RiviumSyncListenerError.permissionDenied);
      reg.remove();
    });

    test('a listener without onError ignores the error and keeps the old signature', () async {
      mockEvents('co.rivium.sync/query_events');
      final docs = <List<SyncDocument>>[];
      final reg = todos.query().listen(docs.add);
      await pumpEventQueue();
      sink!.success({
        'listenerId': started.single['listenerId'],
        'error': {'code': 'listener_revoked', 'message': 'stopped'},
      });
      await pumpEventQueue();
      expect(docs, isEmpty);
      reg.remove();
    });
  });

  group('RiviumSyncError.fromMap', () {
    test('reads the server code query_not_allowed and fields', () {
      final e = RiviumSyncError.fromMap({
        'code': 'query_not_allowed',
        'message': 'm',
        'fields': ['teamId', 1],
      });
      expect(e.code, RiviumSyncErrorCode.queryNotAllowed);
      expect(e.fields, ['teamId']);
    });
  });
}
