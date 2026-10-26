import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivium_sync/rivium_sync.dart';

/// 0.3.0: errors carry the server's HTTP status, the emulator settings reach
/// the native SDK, and refused queued writes are reported.
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

  Matcher syncError(RiviumSyncErrorCode code, int? status) => throwsA(isA<RiviumSyncError>()
      .having((e) => e.code, 'code', code)
      .having((e) => e.statusCode, 'statusCode', status));

  group('statusCode', () {
    test('a write the rules refuse: 403, permissionError', () async {
      answer = (_) async => throw PlatformException(
          code: 'DOCUMENT_ERROR', message: 'Permission denied', details: {'statusCode': 403});
      await expectLater(todos.add({'userId': 'someone-else'}), syncError(RiviumSyncErrorCode.permissionError, 403));
    });

    test('404 and 422 keep the channel code', () async {
      answer = (_) async => throw PlatformException(code: 'DOCUMENT_ERROR', message: 'nope', details: {'statusCode': 404});
      await expectLater(todos.update('x', {'a': 1}), syncError(RiviumSyncErrorCode.documentError, 404));
      answer = (_) async => throw PlatformException(code: 'DOCUMENT_ERROR', message: 'bad', details: {'statusCode': 422});
      await expectLater(todos.set('x', {'a': 1}), syncError(RiviumSyncErrorCode.documentError, 422));
    });

    test('401 is an authenticationError', () async {
      answer = (_) async => throw PlatformException(code: 'DOCUMENT_ERROR', message: 'token', details: {'statusCode': 401});
      await expectLater(todos.get('x'), syncError(RiviumSyncErrorCode.authenticationError, 401));
    });

    test('no answer from the server: no status', () async {
      answer = (_) async => throw PlatformException(code: 'DOCUMENT_ERROR', message: 'offline');
      await expectLater(todos.delete('x'), syncError(RiviumSyncErrorCode.documentError, null));
    });

    test('getAll refused by the rules is query_not_allowed with fields and 403', () async {
      answer = (_) async => throw PlatformException(
          code: 'query_not_allowed', message: 'Filter on userId', details: {'fields': ['userId'], 'statusCode': 403});
      await expectLater(
        todos.getAll(),
        throwsA(isA<RiviumSyncError>()
            .having((e) => e.code, 'code', RiviumSyncErrorCode.queryNotAllowed)
            .having((e) => e.fields, 'fields', ['userId'])
            .having((e) => e.statusCode, 'statusCode', 403)
            .having((e) => e.isPermissionDenied, 'isPermissionDenied', true)),
      );
    });

    test('a refused batch: 403', () async {
      answer = (_) async => throw PlatformException(code: 'BATCH_ERROR', message: 'refused', details: {'statusCode': 403});
      final batch = WriteBatch(method)..create(todos, {'userId': 'x'});
      await expectLater(batch.commit(), syncError(RiviumSyncErrorCode.permissionError, 403));
    });

    test('database calls are typed too', () async {
      answer = (_) async => throw PlatformException(code: 'COLLECTION_ERROR', message: 'x', details: {'statusCode': 500});
      final db = SyncDatabase(method, 'my-app', 'my-app');
      await expectLater(db.listCollections(), syncError(RiviumSyncErrorCode.collectionError, 500));
    });

    test('the listener error map carries the status', () {
      final error = RiviumSyncListenerError.fromMap({'code': 'permission_denied', 'message': 'no', 'statusCode': 403});
      expect(error.statusCode, 403);
    });
  });

  group('emulator', () {
    test('not sent by default', () {
      final map = const RiviumSyncConfig(apiKey: 'rv_live_key').toMap();
      expect(map.containsKey('emulatorHost'), isFalse);
      expect(map.containsKey('emulatorPort'), isFalse);
    });

    test('host and the default port 3006 are sent', () {
      final map = const RiviumSyncConfig(apiKey: 'rv_live_key', emulatorHost: '10.0.2.2').toMap();
      expect(map['emulatorHost'], '10.0.2.2');
      expect(map['emulatorPort'], 3006);
    });

    test('a custom port is sent, the host trimmed', () {
      final map = const RiviumSyncConfig(apiKey: 'k', emulatorHost: ' localhost ', emulatorPort: 4000).toMap();
      expect(map['emulatorHost'], 'localhost');
      expect(map['emulatorPort'], 4000);
    });

    test('a scheme, a port in the host, an empty host or a bad port are refused', () {
      for (final config in const [
        RiviumSyncConfig(apiKey: 'k', emulatorHost: 'http://localhost'),
        RiviumSyncConfig(apiKey: 'k', emulatorHost: 'localhost:3006'),
        RiviumSyncConfig(apiKey: 'k', emulatorHost: '  '),
        RiviumSyncConfig(apiKey: 'k', emulatorHost: 'localhost', emulatorPort: 0),
        RiviumSyncConfig(apiKey: 'k', emulatorHost: 'localhost', emulatorPort: 70000),
      ]) {
        expect(config.toMap, throwsArgumentError, reason: '${config.emulatorHost}:${config.emulatorPort}');
      }
    });

    test('init sends the emulator settings to the native SDK', () async {
      await RiviumSync.init(const RiviumSyncConfig(apiKey: 'rv_live_key', emulatorHost: 'localhost', offlineEnabled: true));
      final args = calls.singleWhere((c) => c.method == 'init').arguments as Map;
      expect(args['emulatorHost'], 'localhost');
      expect(args['emulatorPort'], 3006);
    });
  });

  group('onDocumentRejected', () {
    Future<void> fromNative(String name, Object? arguments) async {
      await messenger.handlePlatformMessage(
        method.name,
        method.codec.encodeMethodCall(MethodCall(name, arguments)),
        (_) {},
      );
    }

    test('a refused queued write reaches the callback with its status', () async {
      // init ran in the group above (RiviumSync keeps static state), which set the call handler.
      final heard = <(String, SyncOperationType, RiviumSyncError)>[];
      RiviumSync.onDocumentRejected((id, op, error) => heard.add((id, op, error)));

      await fromNative('onDocumentRejected', {
        'documentId': 'local_1',
        'operation': 'create',
        'error': {'code': 'DOCUMENT_ERROR', 'message': 'Permission denied', 'statusCode': 403},
      });

      expect(heard, hasLength(1));
      expect(heard.single.$1, 'local_1');
      expect(heard.single.$2, SyncOperationType.create);
      expect(heard.single.$3.statusCode, 403);
      expect(heard.single.$3.code, RiviumSyncErrorCode.permissionError);
      expect(heard.single.$3.message, 'Permission denied');
    });

    test('update and delete; a malformed event is ignored', () async {
      final ops = <SyncOperationType>[];
      RiviumSync.onDocumentRejected((_, op, __) => ops.add(op));
      await fromNative('onDocumentRejected', {'documentId': 'a', 'operation': 'update', 'error': {'code': 'DOCUMENT_ERROR', 'message': 'bad', 'statusCode': 422}});
      await fromNative('onDocumentRejected', {'documentId': 'b', 'operation': 'delete', 'error': {'message': 'no'}});
      await fromNative('onDocumentRejected', {'operation': 'create'});
      await fromNative('onDocumentRejected', null);
      expect(ops, [SyncOperationType.update, SyncOperationType.delete]);
    });
  });

  group('event streams', () {
    Future<void> fromNative(String name, Object? arguments) async {
      await messenger.handlePlatformMessage(
        method.name,
        method.codec.encodeMethodCall(MethodCall(name, arguments)),
        (_) {},
      );
    }

    test('two screens both hear the connection state; a cancelled one stops (the setter kept only the last)', () async {
      final home = <bool>[];
      final offline = <bool>[];
      final a = RiviumSync.connectionStateChanges.listen(home.add);
      final b = RiviumSync.connectionStateChanges.listen(offline.add);

      await fromNative('onConnectionState', false);
      await b.cancel();
      await fromNative('onConnectionState', true);
      await Future<void>.delayed(Duration.zero);

      expect(home, [false, true]);
      expect(offline, [false]);
      await a.cancel();
    });

    test('sync state, pending count and rejections arrive on their streams', () async {
      final states = <SyncState>[];
      final counts = <int>[];
      final rejected = <DocumentRejection>[];
      final subs = [
        RiviumSync.syncStateChanges.listen(states.add),
        RiviumSync.pendingCountChanges.listen(counts.add),
        RiviumSync.documentRejections.listen(rejected.add),
      ];

      await fromNative('onSyncState', 'offline');
      await fromNative('onPendingCount', 2);
      await fromNative('onDocumentRejected', {
        'documentId': 'local_9',
        'operation': 'create',
        'error': {'code': 'DOCUMENT_ERROR', 'message': 'Permission denied', 'statusCode': 403},
      });
      await Future<void>.delayed(Duration.zero);

      expect(states, [SyncState.offline]);
      expect(counts, [2]);
      expect(rejected.single.documentId, 'local_9');
      expect(rejected.single.error.statusCode, 403);
      for (final sub in subs) {
        await sub.cancel();
      }
    });
  });
}
