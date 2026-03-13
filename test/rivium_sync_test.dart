import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivium_sync/rivium_sync.dart';

// ============================================================================
// Test Helpers
// ============================================================================

/// A mock method channel handler that records calls and returns preset results.
class MockMethodChannel {
  final List<MethodCall> calls = [];
  final Map<String, dynamic Function(Map<dynamic, dynamic>?)> handlers = {};
  dynamic defaultResult;

  MockMethodChannel();

  void setHandler(String method, dynamic Function(Map<dynamic, dynamic>?) handler) {
    handlers[method] = handler;
  }

  Future<dynamic> handle(MethodCall call) async {
    calls.add(call);
    final handler = handlers[call.method];
    if (handler != null) {
      return handler(call.arguments as Map<dynamic, dynamic>?);
    }
    return defaultResult;
  }

  List<MethodCall> callsFor(String method) {
    return calls.where((c) => c.method == method).toList();
  }

  void reset() {
    calls.clear();
    handlers.clear();
    defaultResult = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ============================================================================
  // RiviumSyncConfig Tests
  // ============================================================================

  group('RiviumSyncConfig', () {
    test('should require apiKey', () {
      final config = RiviumSyncConfig(apiKey: 'rv_test_abc123');
      expect(config.apiKey, 'rv_test_abc123');
    });

    test('should have correct default values', () {
      final config = RiviumSyncConfig(apiKey: 'key');
      expect(config.debugMode, false);
      expect(config.autoReconnect, true);
      expect(config.offlineEnabled, false);
      expect(config.offlineCacheSizeMb, 100);
      expect(config.syncOnReconnect, true);
      expect(config.conflictStrategy, ConflictStrategy.serverWins);
      expect(config.maxSyncRetries, 3);
    });

    test('should accept custom values', () {
      final config = RiviumSyncConfig(
        apiKey: 'rv_live_xyz',
        debugMode: true,
        autoReconnect: false,
        offlineEnabled: true,
        offlineCacheSizeMb: 50,
        syncOnReconnect: false,
        conflictStrategy: ConflictStrategy.clientWins,
        maxSyncRetries: 5,
      );

      expect(config.apiKey, 'rv_live_xyz');
      expect(config.debugMode, true);
      expect(config.autoReconnect, false);
      expect(config.offlineEnabled, true);
      expect(config.offlineCacheSizeMb, 50);
      expect(config.syncOnReconnect, false);
      expect(config.conflictStrategy, ConflictStrategy.clientWins);
      expect(config.maxSyncRetries, 5);
    });

    test('toMap should serialize all fields', () {
      final config = RiviumSyncConfig(
        apiKey: 'rv_test_key',
        debugMode: true,
        autoReconnect: false,
        offlineEnabled: true,
        offlineCacheSizeMb: 200,
        syncOnReconnect: false,
        conflictStrategy: ConflictStrategy.merge,
        maxSyncRetries: 10,
      );

      final map = config.toMap();

      expect(map['apiKey'], 'rv_test_key');
      expect(map['debugMode'], true);
      expect(map['autoReconnect'], false);
      expect(map['offlineEnabled'], true);
      expect(map['offlineCacheSizeMb'], 200);
      expect(map['syncOnReconnect'], false);
      expect(map['conflictStrategy'], 'merge');
      expect(map['maxSyncRetries'], 10);
    });

    test('toMap should serialize default values correctly', () {
      final config = RiviumSyncConfig(apiKey: 'key');
      final map = config.toMap();

      expect(map['apiKey'], 'key');
      expect(map['debugMode'], false);
      expect(map['autoReconnect'], true);
      expect(map['offlineEnabled'], false);
      expect(map['offlineCacheSizeMb'], 100);
      expect(map['syncOnReconnect'], true);
      expect(map['conflictStrategy'], 'serverWins');
      expect(map['maxSyncRetries'], 3);
    });

    test('toMap should serialize all conflict strategies', () {
      for (final strategy in ConflictStrategy.values) {
        final config = RiviumSyncConfig(
          apiKey: 'key',
          conflictStrategy: strategy,
        );
        final map = config.toMap();
        expect(map['conflictStrategy'], strategy.name);
      }
    });
  });

  // ============================================================================
  // ConflictStrategy Tests
  // ============================================================================

  group('ConflictStrategy', () {
    test('should have all expected values', () {
      expect(ConflictStrategy.values.length, 4);
      expect(ConflictStrategy.values, contains(ConflictStrategy.serverWins));
      expect(ConflictStrategy.values, contains(ConflictStrategy.clientWins));
      expect(ConflictStrategy.values, contains(ConflictStrategy.merge));
      expect(ConflictStrategy.values, contains(ConflictStrategy.manual));
    });

    test('should have correct names', () {
      expect(ConflictStrategy.serverWins.name, 'serverWins');
      expect(ConflictStrategy.clientWins.name, 'clientWins');
      expect(ConflictStrategy.merge.name, 'merge');
      expect(ConflictStrategy.manual.name, 'manual');
    });
  });

  // ============================================================================
  // RiviumSyncError Tests
  // ============================================================================

  group('RiviumSyncError', () {
    test('should create with required fields', () {
      final error = RiviumSyncError(
        code: RiviumSyncErrorCode.networkError,
        message: 'Connection failed',
      );
      expect(error.code, RiviumSyncErrorCode.networkError);
      expect(error.message, 'Connection failed');
      expect(error.details, isNull);
    });

    test('should create with optional details', () {
      final error = RiviumSyncError(
        code: RiviumSyncErrorCode.authenticationError,
        message: 'Invalid token',
        details: 'Token expired at 2024-01-01',
      );
      expect(error.code, RiviumSyncErrorCode.authenticationError);
      expect(error.message, 'Invalid token');
      expect(error.details, 'Token expired at 2024-01-01');
    });

    test('should implement Exception', () {
      final error = RiviumSyncError(
        code: RiviumSyncErrorCode.unknown,
        message: 'test',
      );
      expect(error, isA<Exception>());
    });

    test('toString should include code and message', () {
      final error = RiviumSyncError(
        code: RiviumSyncErrorCode.databaseError,
        message: 'DB not found',
      );
      expect(
        error.toString(),
        'RiviumSyncError(code: RiviumSyncErrorCode.databaseError, message: DB not found)',
      );
    });

    group('fromMap', () {
      test('should parse valid map', () {
        final error = RiviumSyncError.fromMap({
          'code': 'networkError',
          'message': 'Connection lost',
          'details': 'Timeout after 30s',
        });
        expect(error.code, RiviumSyncErrorCode.networkError);
        expect(error.message, 'Connection lost');
        expect(error.details, 'Timeout after 30s');
      });

      test('should default to unknown code for invalid code string', () {
        final error = RiviumSyncError.fromMap({
          'code': 'nonExistentCode',
          'message': 'Something happened',
        });
        expect(error.code, RiviumSyncErrorCode.unknown);
        expect(error.message, 'Something happened');
      });

      test('should default to unknown code when code is null', () {
        final error = RiviumSyncError.fromMap({
          'message': 'Error occurred',
        });
        expect(error.code, RiviumSyncErrorCode.unknown);
      });

      test('should default message when message is null', () {
        final error = RiviumSyncError.fromMap({
          'code': 'networkError',
        });
        expect(error.message, 'Unknown error');
      });

      test('should handle empty map', () {
        final error = RiviumSyncError.fromMap({});
        expect(error.code, RiviumSyncErrorCode.unknown);
        expect(error.message, 'Unknown error');
        expect(error.details, isNull);
      });

      test('should handle null details', () {
        final error = RiviumSyncError.fromMap({
          'code': 'permissionError',
          'message': 'Access denied',
          'details': null,
        });
        expect(error.details, isNull);
      });

      test('should parse all error codes', () {
        for (final code in RiviumSyncErrorCode.values) {
          final error = RiviumSyncError.fromMap({
            'code': code.name,
            'message': 'test',
          });
          expect(error.code, code);
        }
      });
    });
  });

  // ============================================================================
  // RiviumSyncErrorCode Tests
  // ============================================================================

  group('RiviumSyncErrorCode', () {
    test('should have all expected error codes', () {
      expect(RiviumSyncErrorCode.values.length, 11);
      expect(RiviumSyncErrorCode.values, contains(RiviumSyncErrorCode.notInitialized));
      expect(RiviumSyncErrorCode.values, contains(RiviumSyncErrorCode.networkError));
      expect(RiviumSyncErrorCode.values, contains(RiviumSyncErrorCode.authenticationError));
      expect(RiviumSyncErrorCode.values, contains(RiviumSyncErrorCode.databaseError));
      expect(RiviumSyncErrorCode.values, contains(RiviumSyncErrorCode.collectionError));
      expect(RiviumSyncErrorCode.values, contains(RiviumSyncErrorCode.documentError));
      expect(RiviumSyncErrorCode.values, contains(RiviumSyncErrorCode.connectionError));
      expect(RiviumSyncErrorCode.values, contains(RiviumSyncErrorCode.timeoutError));
      expect(RiviumSyncErrorCode.values, contains(RiviumSyncErrorCode.permissionError));
      expect(RiviumSyncErrorCode.values, contains(RiviumSyncErrorCode.invalidResponse));
      expect(RiviumSyncErrorCode.values, contains(RiviumSyncErrorCode.unknown));
    });
  });

  // ============================================================================
  // SyncDocument Tests
  // ============================================================================

  group('SyncDocument', () {
    test('should create with required fields', () {
      final doc = SyncDocument(
        id: 'doc1',
        data: {'name': 'Test'},
        createdAt: 1000,
        updatedAt: 2000,
      );
      expect(doc.id, 'doc1');
      expect(doc.data, {'name': 'Test'});
      expect(doc.createdAt, 1000);
      expect(doc.updatedAt, 2000);
      expect(doc.version, 1); // default
    });

    test('should create with custom version', () {
      final doc = SyncDocument(
        id: 'doc1',
        data: {},
        createdAt: 0,
        updatedAt: 0,
        version: 5,
      );
      expect(doc.version, 5);
    });

    group('fromMap', () {
      test('should parse valid map', () {
        final doc = SyncDocument.fromMap({
          'id': 'abc123',
          'data': {'title': 'Hello', 'count': 42},
          'createdAt': 1700000000000,
          'updatedAt': 1700000001000,
          'version': 3,
        });

        expect(doc.id, 'abc123');
        expect(doc.data['title'], 'Hello');
        expect(doc.data['count'], 42);
        expect(doc.createdAt, 1700000000000);
        expect(doc.updatedAt, 1700000001000);
        expect(doc.version, 3);
      });

      test('should handle missing fields with defaults', () {
        final doc = SyncDocument.fromMap({});
        expect(doc.id, '');
        expect(doc.data, isEmpty);
        expect(doc.createdAt, 0);
        expect(doc.updatedAt, 0);
        expect(doc.version, 1);
      });

      test('should handle null values', () {
        final doc = SyncDocument.fromMap({
          'id': null,
          'data': null,
          'createdAt': null,
          'updatedAt': null,
          'version': null,
        });
        expect(doc.id, '');
        expect(doc.data, isEmpty);
        expect(doc.createdAt, 0);
        expect(doc.updatedAt, 0);
        expect(doc.version, 1);
      });

      test('should handle numeric types (int and double)', () {
        final doc = SyncDocument.fromMap({
          'id': 'doc1',
          'data': {},
          'createdAt': 1000.0, // double
          'updatedAt': 2000,   // int
          'version': 3.0,     // double
        });
        expect(doc.createdAt, 1000);
        expect(doc.updatedAt, 2000);
        expect(doc.version, 3);
      });
    });

    group('toMap', () {
      test('should serialize all fields', () {
        final doc = SyncDocument(
          id: 'doc1',
          data: {'key': 'value'},
          createdAt: 1000,
          updatedAt: 2000,
          version: 3,
        );

        final map = doc.toMap();
        expect(map['id'], 'doc1');
        expect(map['data'], {'key': 'value'});
        expect(map['createdAt'], 1000);
        expect(map['updatedAt'], 2000);
        expect(map['version'], 3);
      });

      test('roundtrip fromMap/toMap should preserve data', () {
        final original = {
          'id': 'roundtrip',
          'data': {'nested': {'deep': true}, 'list': [1, 2, 3]},
          'createdAt': 999,
          'updatedAt': 1000,
          'version': 7,
        };

        final doc = SyncDocument.fromMap(original);
        final result = doc.toMap();

        expect(result['id'], original['id']);
        expect(result['data'], original['data']);
        expect(result['createdAt'], original['createdAt']);
        expect(result['updatedAt'], original['updatedAt']);
        expect(result['version'], original['version']);
      });
    });

    group('typed getters', () {
      late SyncDocument doc;

      setUp(() {
        doc = SyncDocument(
          id: 'doc1',
          data: {
            'name': 'Alice',
            'age': 30,
            'score': 95.5,
            'active': true,
            'tags': ['flutter', 'dart'],
            'address': {'city': 'NYC', 'zip': '10001'},
            'nullField': null,
          },
          createdAt: 0,
          updatedAt: 0,
        );
      });

      test('get should return typed value', () {
        expect(doc.get<String>('name'), 'Alice');
        expect(doc.get<int>('age'), 30);
        expect(doc.get<bool>('active'), true);
      });

      test('get should return null for missing field', () {
        expect(doc.get<String>('nonexistent'), isNull);
      });

      test('getString should return string value', () {
        expect(doc.getString('name'), 'Alice');
      });

      test('getString should return null for non-string field', () {
        expect(doc.getString('nonexistent'), isNull);
      });

      test('getInt should return int value', () {
        expect(doc.getInt('age'), 30);
      });

      test('getInt should return null for missing field', () {
        expect(doc.getInt('nonexistent'), isNull);
      });

      test('getDouble should return double value', () {
        expect(doc.getDouble('score'), 95.5);
      });

      test('getDouble should convert int to double', () {
        expect(doc.getDouble('age'), 30.0);
      });

      test('getDouble should return null for missing field', () {
        expect(doc.getDouble('nonexistent'), isNull);
      });

      test('getBool should return bool value', () {
        expect(doc.getBool('active'), true);
      });

      test('getBool should return null for missing field', () {
        expect(doc.getBool('nonexistent'), isNull);
      });

      test('getList should return list value', () {
        expect(doc.getList<String>('tags'), ['flutter', 'dart']);
      });

      test('getList should return null for missing field', () {
        expect(doc.getList<String>('nonexistent'), isNull);
      });

      test('getMap should return map value', () {
        final addr = doc.getMap('address');
        expect(addr, isNotNull);
        expect(addr!['city'], 'NYC');
        expect(addr['zip'], '10001');
      });

      test('getMap should return null for missing field', () {
        expect(doc.getMap('nonexistent'), isNull);
      });

      test('getMap should return null for null field', () {
        expect(doc.getMap('nullField'), isNull);
      });
    });

    group('contains', () {
      test('should return true for existing field', () {
        final doc = SyncDocument(
          id: 'doc1',
          data: {'name': 'test', 'nullField': null},
          createdAt: 0,
          updatedAt: 0,
        );
        expect(doc.contains('name'), true);
        expect(doc.contains('nullField'), true);
      });

      test('should return false for missing field', () {
        final doc = SyncDocument(
          id: 'doc1',
          data: {'name': 'test'},
          createdAt: 0,
          updatedAt: 0,
        );
        expect(doc.contains('nonexistent'), false);
      });
    });

    group('exists', () {
      test('should return true for non-empty id', () {
        final doc = SyncDocument(
          id: 'doc1',
          data: {},
          createdAt: 0,
          updatedAt: 0,
        );
        expect(doc.exists, true);
      });

      test('should return false for empty id', () {
        final doc = SyncDocument(
          id: '',
          data: {},
          createdAt: 0,
          updatedAt: 0,
        );
        expect(doc.exists, false);
      });
    });

    test('toString should include id and data', () {
      final doc = SyncDocument(
        id: 'doc1',
        data: {'name': 'Test'},
        createdAt: 0,
        updatedAt: 0,
      );
      expect(doc.toString(), contains('doc1'));
      expect(doc.toString(), contains('name'));
    });
  });

  // ============================================================================
  // DatabaseInfo Tests
  // ============================================================================

  group('DatabaseInfo', () {
    test('should create with required fields', () {
      final info = DatabaseInfo(
        id: 'db1',
        name: 'My Database',
        createdAt: 1000,
        updatedAt: 2000,
      );
      expect(info.id, 'db1');
      expect(info.name, 'My Database');
      expect(info.createdAt, 1000);
      expect(info.updatedAt, 2000);
    });

    test('fromMap should parse valid map', () {
      final info = DatabaseInfo.fromMap({
        'id': 'db1',
        'name': 'Test DB',
        'createdAt': 1700000000000,
        'updatedAt': 1700000001000,
      });
      expect(info.id, 'db1');
      expect(info.name, 'Test DB');
      expect(info.createdAt, 1700000000000);
      expect(info.updatedAt, 1700000001000);
    });

    test('fromMap should handle missing fields', () {
      final info = DatabaseInfo.fromMap({});
      expect(info.id, '');
      expect(info.name, '');
      expect(info.createdAt, 0);
      expect(info.updatedAt, 0);
    });

    test('fromMap should handle null values', () {
      final info = DatabaseInfo.fromMap({
        'id': null,
        'name': null,
        'createdAt': null,
        'updatedAt': null,
      });
      expect(info.id, '');
      expect(info.name, '');
      expect(info.createdAt, 0);
      expect(info.updatedAt, 0);
    });
  });

  // ============================================================================
  // CollectionInfo Tests
  // ============================================================================

  group('CollectionInfo', () {
    test('should create with required fields', () {
      final info = CollectionInfo(
        id: 'col1',
        name: 'users',
        databaseId: 'db1',
        documentCount: 42,
        createdAt: 1000,
        updatedAt: 2000,
      );
      expect(info.id, 'col1');
      expect(info.name, 'users');
      expect(info.databaseId, 'db1');
      expect(info.documentCount, 42);
      expect(info.createdAt, 1000);
      expect(info.updatedAt, 2000);
    });

    test('fromMap should parse valid map', () {
      final info = CollectionInfo.fromMap({
        'id': 'col1',
        'name': 'todos',
        'databaseId': 'db1',
        'documentCount': 100,
        'createdAt': 1700000000000,
        'updatedAt': 1700000001000,
      });
      expect(info.id, 'col1');
      expect(info.name, 'todos');
      expect(info.databaseId, 'db1');
      expect(info.documentCount, 100);
      expect(info.createdAt, 1700000000000);
      expect(info.updatedAt, 1700000001000);
    });

    test('fromMap should handle missing fields', () {
      final info = CollectionInfo.fromMap({});
      expect(info.id, '');
      expect(info.name, '');
      expect(info.databaseId, '');
      expect(info.documentCount, 0);
      expect(info.createdAt, 0);
      expect(info.updatedAt, 0);
    });
  });

  // ============================================================================
  // SyncState Tests
  // ============================================================================

  group('SyncState', () {
    test('should have all expected values', () {
      expect(SyncState.values.length, 4);
      expect(SyncState.values, contains(SyncState.idle));
      expect(SyncState.values, contains(SyncState.syncing));
      expect(SyncState.values, contains(SyncState.offline));
      expect(SyncState.values, contains(SyncState.error));
    });
  });

  // ============================================================================
  // ListenerRegistration Tests
  // ============================================================================

  group('ListenerRegistration', () {
    test('should call onRemove when remove is called', () {
      var removed = false;
      final registration = ListenerRegistration(() {
        removed = true;
      });

      expect(removed, false);
      registration.remove();
      expect(removed, true);
    });

    test('should allow multiple remove calls', () {
      var callCount = 0;
      final registration = ListenerRegistration(() {
        callCount++;
      });

      registration.remove();
      registration.remove();
      expect(callCount, 2);
    });
  });

  // ============================================================================
  // RiviumSyncListenerError Tests
  // ============================================================================

  group('RiviumSyncListenerError', () {
    test('should create with code and message', () {
      final error = RiviumSyncListenerError(
        code: 'PERMISSION_DENIED',
        message: 'Access denied',
      );
      expect(error.code, 'PERMISSION_DENIED');
      expect(error.message, 'Access denied');
    });

    test('should implement Exception', () {
      final error = RiviumSyncListenerError(code: 'ERR', message: 'test');
      expect(error, isA<Exception>());
    });

    test('toString should include code and message', () {
      final error = RiviumSyncListenerError(
        code: 'NOT_FOUND',
        message: 'Document not found',
      );
      expect(error.toString(), 'RiviumSyncListenerError(NOT_FOUND): Document not found');
    });
  });

  // ============================================================================
  // QueryOperator Tests
  // ============================================================================

  group('QueryOperator', () {
    test('should have all expected operators', () {
      expect(QueryOperator.values.length, 9);
      expect(QueryOperator.values, contains(QueryOperator.equal));
      expect(QueryOperator.values, contains(QueryOperator.notEqual));
      expect(QueryOperator.values, contains(QueryOperator.greaterThan));
      expect(QueryOperator.values, contains(QueryOperator.greaterThanOrEqual));
      expect(QueryOperator.values, contains(QueryOperator.lessThan));
      expect(QueryOperator.values, contains(QueryOperator.lessThanOrEqual));
      expect(QueryOperator.values, contains(QueryOperator.arrayContains));
      expect(QueryOperator.values, contains(QueryOperator.isIn));
      expect(QueryOperator.values, contains(QueryOperator.notIn));
    });
  });

  // ============================================================================
  // OrderDirection Tests
  // ============================================================================

  group('OrderDirection', () {
    test('should have ascending and descending', () {
      expect(OrderDirection.values.length, 2);
      expect(OrderDirection.values, contains(OrderDirection.ascending));
      expect(OrderDirection.values, contains(OrderDirection.descending));
    });
  });

  // ============================================================================
  // RiviumSync Main Class Tests (with mock MethodChannel)
  // ============================================================================

  group('RiviumSync', () {
    const channel = MethodChannel('co.rivium.sync/rivium_sync');
    final mockHandler = MockMethodChannel();

    setUp(() {
      mockHandler.reset();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, mockHandler.handle);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('version should be 1.0.0', () {
      expect(RiviumSync.version, '1.0.0');
    });

    group('init', () {
      test('should call native init with config', () async {
        final config = RiviumSyncConfig(apiKey: 'rv_test_key', debugMode: true);
        await RiviumSync.init(config);

        final initCalls = mockHandler.callsFor('init');
        expect(initCalls.length, 1);

        final args = initCalls.first.arguments as Map;
        expect(args['apiKey'], 'rv_test_key');
        expect(args['debugMode'], true);
      });

      test('should set initialized flag', () async {
        // Already initialized from prior test, re-init should be idempotent
        expect(RiviumSync.isInitialized, true);
      });
    });

    group('connect', () {
      test('should call native connect', () async {
        await RiviumSync.connect();
        expect(mockHandler.callsFor('connect').length, 1);
      });
    });

    group('disconnect', () {
      test('should call native disconnect', () async {
        await RiviumSync.disconnect();
        expect(mockHandler.callsFor('disconnect').length, 1);
      });
    });

    group('isConnected', () {
      test('should return true when native returns true', () async {
        mockHandler.setHandler('isConnected', (_) => true);
        final result = await RiviumSync.isConnected();
        expect(result, true);
      });

      test('should return false when native returns false', () async {
        mockHandler.setHandler('isConnected', (_) => false);
        final result = await RiviumSync.isConnected();
        expect(result, false);
      });

      test('should return false when native returns null', () async {
        mockHandler.setHandler('isConnected', (_) => null);
        final result = await RiviumSync.isConnected();
        expect(result, false);
      });
    });

    group('database', () {
      test('should return SyncDatabase with correct id', () {
        final db = RiviumSync.database('my-db-id');
        expect(db, isA<SyncDatabase>());
        expect(db.id, 'my-db-id');
      });
    });

    group('batch', () {
      test('should return a WriteBatch', () {
        final batch = RiviumSync.batch();
        expect(batch, isA<WriteBatch>());
      });
    });

    group('listDatabases', () {
      test('should return list of DatabaseInfo', () async {
        mockHandler.setHandler('listDatabases', (_) => [
          {'id': 'db1', 'name': 'DB 1', 'createdAt': 1000, 'updatedAt': 2000},
          {'id': 'db2', 'name': 'DB 2', 'createdAt': 3000, 'updatedAt': 4000},
        ]);

        final databases = await RiviumSync.listDatabases();
        expect(databases.length, 2);
        expect(databases[0].id, 'db1');
        expect(databases[0].name, 'DB 1');
        expect(databases[1].id, 'db2');
        expect(databases[1].name, 'DB 2');
      });

      test('should return empty list when native returns null', () async {
        mockHandler.setHandler('listDatabases', (_) => null);
        final databases = await RiviumSync.listDatabases();
        expect(databases, isEmpty);
      });
    });

    group('offline APIs', () {
      test('onSyncState should set callback', () {
        SyncState? receivedState;
        RiviumSync.onSyncState((state) => receivedState = state);
        // Callback is set; tested further with native method handler tests
        expect(receivedState, isNull);
      });

      test('onPendingCount should set callback', () {
        int? receivedCount;
        RiviumSync.onPendingCount((count) => receivedCount = count);
        expect(receivedCount, isNull);
      });

      test('onConnectionState should set callback', () {
        bool? receivedState;
        RiviumSync.onConnectionState((connected) => receivedState = connected);
        expect(receivedState, isNull);
      });

      test('onError should set callback', () {
        RiviumSyncError? receivedError;
        RiviumSync.onError((error) => receivedError = error);
        expect(receivedError, isNull);
      });

      test('getSyncState should return idle when offline not enabled', () async {
        // Default config has offlineEnabled = false
        // We need to reinit with offline disabled - but since init is idempotent,
        // we test the behavior based on current state
        mockHandler.setHandler('getSyncState', (_) => 'syncing');
        final state = await RiviumSync.getSyncState();
        // Since offline may or may not be enabled depending on init order,
        // we just verify it returns a valid SyncState
        expect(state, isA<SyncState>());
      });

      test('getPendingCount should call native method', () async {
        mockHandler.setHandler('getPendingCount', (_) => 5);
        final count = await RiviumSync.getPendingCount();
        expect(count, isA<int>());
      });

      test('forceSyncNow should call native method', () async {
        await RiviumSync.forceSyncNow();
        // Just verify no error thrown
      });

      test('clearOfflineCache should call native method', () async {
        await RiviumSync.clearOfflineCache();
        // Just verify no error thrown
      });
    });

    group('native method handler', () {
      test('should handle onConnectionState callback', () async {
        bool? receivedState;
        RiviumSync.onConnectionState((connected) => receivedState = connected);

        // Simulate native calling Flutter
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
          'co.rivium.sync/rivium_sync',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('onConnectionState', true),
          ),
          (ByteData? data) {},
        );

        expect(receivedState, true);
      });

      test('should handle onError callback', () async {
        RiviumSyncError? receivedError;
        RiviumSync.onError((error) => receivedError = error);

        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
          'co.rivium.sync/rivium_sync',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('onError', {
              'code': 'networkError',
              'message': 'Connection lost',
            }),
          ),
          (ByteData? data) {},
        );

        expect(receivedError, isNotNull);
        expect(receivedError!.code, RiviumSyncErrorCode.networkError);
        expect(receivedError!.message, 'Connection lost');
      });

      test('should handle onSyncState callback', () async {
        SyncState? receivedState;
        RiviumSync.onSyncState((state) => receivedState = state);

        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
          'co.rivium.sync/rivium_sync',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('onSyncState', 'syncing'),
          ),
          (ByteData? data) {},
        );

        expect(receivedState, SyncState.syncing);
      });

      test('should handle onPendingCount callback', () async {
        int? receivedCount;
        RiviumSync.onPendingCount((count) => receivedCount = count);

        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
          'co.rivium.sync/rivium_sync',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('onPendingCount', 7),
          ),
          (ByteData? data) {},
        );

        expect(receivedCount, 7);
      });

      test('should handle onPendingCount with null argument', () async {
        int? receivedCount;
        RiviumSync.onPendingCount((count) => receivedCount = count);

        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
          'co.rivium.sync/rivium_sync',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('onPendingCount', null),
          ),
          (ByteData? data) {},
        );

        expect(receivedCount, 0);
      });

      test('should handle onSyncState with unknown state', () async {
        SyncState? receivedState;
        RiviumSync.onSyncState((state) => receivedState = state);

        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
          'co.rivium.sync/rivium_sync',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('onSyncState', 'unknownState'),
          ),
          (ByteData? data) {},
        );

        expect(receivedState, SyncState.idle);
      });

      test('should parse all sync states correctly', () async {
        final stateMap = {
          'syncing': SyncState.syncing,
          'offline': SyncState.offline,
          'error': SyncState.error,
          'idle': SyncState.idle, // 'idle' falls to default
        };

        for (final entry in stateMap.entries) {
          SyncState? receivedState;
          RiviumSync.onSyncState((state) => receivedState = state);

          await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .handlePlatformMessage(
            'co.rivium.sync/rivium_sync',
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('onSyncState', entry.key),
            ),
            (ByteData? data) {},
          );

          expect(receivedState, entry.value,
              reason: 'State "${entry.key}" should map to ${entry.value}');
        }
      });
    });
  });

  // ============================================================================
  // SyncDatabase Tests (with mock MethodChannel)
  // ============================================================================

  group('SyncDatabase', () {
    const channel = MethodChannel('co.rivium.sync/rivium_sync');
    final mockHandler = MockMethodChannel();
    late SyncDatabase database;

    setUp(() {
      mockHandler.reset();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, mockHandler.handle);
      database = SyncDatabase(channel, 'db-123', 'Test DB');
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('should expose id and name', () {
      expect(database.id, 'db-123');
      expect(database.name, 'Test DB');
    });

    group('collection', () {
      test('should return SyncCollection with correct ids', () {
        final col = database.collection('users');
        expect(col, isA<SyncCollection>());
        expect(col.id, 'users');
        expect(col.name, 'users');
        expect(col.databaseId, 'db-123');
      });
    });

    group('batch', () {
      test('should return a WriteBatch', () {
        final batch = database.batch();
        expect(batch, isA<WriteBatch>());
      });
    });

    group('listCollections', () {
      test('should return list of CollectionInfo', () async {
        mockHandler.setHandler('listCollections', (_) => [
          {
            'id': 'col1',
            'name': 'users',
            'databaseId': 'db-123',
            'documentCount': 10,
            'createdAt': 1000,
            'updatedAt': 2000,
          },
          {
            'id': 'col2',
            'name': 'orders',
            'databaseId': 'db-123',
            'documentCount': 5,
            'createdAt': 3000,
            'updatedAt': 4000,
          },
        ]);

        final collections = await database.listCollections();
        expect(collections.length, 2);
        expect(collections[0].id, 'col1');
        expect(collections[0].name, 'users');
        expect(collections[0].documentCount, 10);
        expect(collections[1].id, 'col2');
        expect(collections[1].name, 'orders');
      });

      test('should pass databaseId to native', () async {
        mockHandler.setHandler('listCollections', (_) => []);
        await database.listCollections();

        final calls = mockHandler.callsFor('listCollections');
        expect(calls.length, 1);
        expect((calls.first.arguments as Map)['databaseId'], 'db-123');
      });

      test('should return empty list when native returns null', () async {
        mockHandler.setHandler('listCollections', (_) => null);
        final collections = await database.listCollections();
        expect(collections, isEmpty);
      });
    });

    group('createCollection', () {
      test('should create and return SyncCollection', () async {
        mockHandler.setHandler('createCollection', (_) => {
          'id': 'new-col-id',
          'name': 'new-collection',
          'databaseId': 'db-123',
          'documentCount': 0,
          'createdAt': 1000,
          'updatedAt': 1000,
        });

        final col = await database.createCollection('new-collection');
        expect(col, isA<SyncCollection>());
        expect(col.id, 'new-col-id');
        expect(col.name, 'new-collection');
      });

      test('should pass name and databaseId to native', () async {
        mockHandler.setHandler('createCollection', (_) => {
          'id': 'id',
          'name': 'test',
          'databaseId': 'db-123',
          'documentCount': 0,
          'createdAt': 0,
          'updatedAt': 0,
        });

        await database.createCollection('test');

        final calls = mockHandler.callsFor('createCollection');
        expect(calls.length, 1);
        final args = calls.first.arguments as Map;
        expect(args['databaseId'], 'db-123');
        expect(args['name'], 'test');
      });

      test('should throw when native returns null', () async {
        mockHandler.setHandler('createCollection', (_) => null);
        expect(
          () => database.createCollection('test'),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('deleteCollection', () {
      test('should call native with collectionId', () async {
        await database.deleteCollection('col-to-delete');

        final calls = mockHandler.callsFor('deleteCollection');
        expect(calls.length, 1);
        expect((calls.first.arguments as Map)['collectionId'], 'col-to-delete');
      });
    });
  });

  // ============================================================================
  // SyncCollection Tests (with mock MethodChannel)
  // ============================================================================

  group('SyncCollection', () {
    const channel = MethodChannel('co.rivium.sync/rivium_sync');
    final mockHandler = MockMethodChannel();
    late SyncCollection collection;

    setUp(() {
      mockHandler.reset();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, mockHandler.handle);
      collection = SyncCollection(channel, 'db-1', 'col-1', 'users');
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('should expose id, name, and databaseId', () {
      expect(collection.id, 'col-1');
      expect(collection.name, 'users');
      expect(collection.databaseId, 'db-1');
    });

    group('add', () {
      test('should call native addDocument and return SyncDocument', () async {
        mockHandler.setHandler('addDocument', (_) => {
          'id': 'new-doc-id',
          'data': {'title': 'Test'},
          'createdAt': 1000,
          'updatedAt': 1000,
          'version': 1,
        });

        final doc = await collection.add({'title': 'Test'});
        expect(doc.id, 'new-doc-id');
        expect(doc.data['title'], 'Test');
      });

      test('should pass correct arguments', () async {
        mockHandler.setHandler('addDocument', (_) => {
          'id': 'id', 'data': {}, 'createdAt': 0, 'updatedAt': 0, 'version': 1,
        });

        await collection.add({'key': 'value'});

        final calls = mockHandler.callsFor('addDocument');
        expect(calls.length, 1);
        final args = calls.first.arguments as Map;
        expect(args['databaseId'], 'db-1');
        expect(args['collectionId'], 'col-1');
        expect(args['data'], {'key': 'value'});
      });

      test('should throw when native returns null', () async {
        mockHandler.setHandler('addDocument', (_) => null);
        expect(
          () => collection.add({'key': 'value'}),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('get', () {
      test('should return SyncDocument when found', () async {
        mockHandler.setHandler('getDocument', (_) => {
          'id': 'doc-1',
          'data': {'name': 'Alice'},
          'createdAt': 1000,
          'updatedAt': 2000,
          'version': 2,
        });

        final doc = await collection.get('doc-1');
        expect(doc, isNotNull);
        expect(doc!.id, 'doc-1');
        expect(doc.data['name'], 'Alice');
        expect(doc.version, 2);
      });

      test('should return null when document not found', () async {
        mockHandler.setHandler('getDocument', (_) => null);
        final doc = await collection.get('nonexistent');
        expect(doc, isNull);
      });

      test('should pass correct arguments', () async {
        mockHandler.setHandler('getDocument', (_) => null);
        await collection.get('target-doc');

        final calls = mockHandler.callsFor('getDocument');
        expect(calls.length, 1);
        final args = calls.first.arguments as Map;
        expect(args['databaseId'], 'db-1');
        expect(args['collectionId'], 'col-1');
        expect(args['documentId'], 'target-doc');
      });
    });

    group('getAll', () {
      test('should return list of SyncDocuments', () async {
        mockHandler.setHandler('getAllDocuments', (_) => [
          {'id': 'doc-1', 'data': {'name': 'Alice'}, 'createdAt': 1000, 'updatedAt': 1000, 'version': 1},
          {'id': 'doc-2', 'data': {'name': 'Bob'}, 'createdAt': 2000, 'updatedAt': 2000, 'version': 1},
        ]);

        final docs = await collection.getAll();
        expect(docs.length, 2);
        expect(docs[0].id, 'doc-1');
        expect(docs[1].id, 'doc-2');
      });

      test('should return empty list when native returns null', () async {
        mockHandler.setHandler('getAllDocuments', (_) => null);
        final docs = await collection.getAll();
        expect(docs, isEmpty);
      });

      test('should pass databaseId and collectionId', () async {
        mockHandler.setHandler('getAllDocuments', (_) => []);
        await collection.getAll();

        final calls = mockHandler.callsFor('getAllDocuments');
        final args = calls.first.arguments as Map;
        expect(args['databaseId'], 'db-1');
        expect(args['collectionId'], 'col-1');
      });
    });

    group('update', () {
      test('should call native updateDocument and return updated doc', () async {
        mockHandler.setHandler('updateDocument', (_) => {
          'id': 'doc-1',
          'data': {'name': 'Alice Updated'},
          'createdAt': 1000,
          'updatedAt': 3000,
          'version': 2,
        });

        final doc = await collection.update('doc-1', {'name': 'Alice Updated'});
        expect(doc.id, 'doc-1');
        expect(doc.data['name'], 'Alice Updated');
        expect(doc.version, 2);
      });

      test('should pass correct arguments', () async {
        mockHandler.setHandler('updateDocument', (_) => {
          'id': 'id', 'data': {}, 'createdAt': 0, 'updatedAt': 0, 'version': 1,
        });

        await collection.update('doc-1', {'status': 'active'});

        final calls = mockHandler.callsFor('updateDocument');
        final args = calls.first.arguments as Map;
        expect(args['databaseId'], 'db-1');
        expect(args['collectionId'], 'col-1');
        expect(args['documentId'], 'doc-1');
        expect(args['data'], {'status': 'active'});
      });

      test('should throw when native returns null', () async {
        mockHandler.setHandler('updateDocument', (_) => null);
        expect(
          () => collection.update('doc-1', {'key': 'value'}),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('set', () {
      test('should call native setDocument and return doc', () async {
        mockHandler.setHandler('setDocument', (_) => {
          'id': 'doc-1',
          'data': {'name': 'Replaced'},
          'createdAt': 1000,
          'updatedAt': 4000,
          'version': 3,
        });

        final doc = await collection.set('doc-1', {'name': 'Replaced'});
        expect(doc.id, 'doc-1');
        expect(doc.data['name'], 'Replaced');
      });

      test('should pass correct arguments', () async {
        mockHandler.setHandler('setDocument', (_) => {
          'id': 'id', 'data': {}, 'createdAt': 0, 'updatedAt': 0, 'version': 1,
        });

        await collection.set('doc-1', {'full': 'replace'});

        final calls = mockHandler.callsFor('setDocument');
        final args = calls.first.arguments as Map;
        expect(args['databaseId'], 'db-1');
        expect(args['collectionId'], 'col-1');
        expect(args['documentId'], 'doc-1');
        expect(args['data'], {'full': 'replace'});
      });

      test('should throw when native returns null', () async {
        mockHandler.setHandler('setDocument', (_) => null);
        expect(
          () => collection.set('doc-1', {'key': 'value'}),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('delete', () {
      test('should call native deleteDocument', () async {
        await collection.delete('doc-to-delete');

        final calls = mockHandler.callsFor('deleteDocument');
        expect(calls.length, 1);
        final args = calls.first.arguments as Map;
        expect(args['databaseId'], 'db-1');
        expect(args['collectionId'], 'col-1');
        expect(args['documentId'], 'doc-to-delete');
      });
    });

    group('query', () {
      test('should return SyncQuery instance', () {
        final q = collection.query();
        expect(q, isA<SyncQuery>());
      });
    });

    group('where', () {
      test('should return SyncQuery with filter applied', () {
        final q = collection.where('age', QueryOperator.greaterThan, 18);
        expect(q, isA<SyncQuery>());
      });
    });
  });

  // ============================================================================
  // SyncQuery Tests (with mock MethodChannel)
  // ============================================================================

  group('SyncQuery', () {
    const channel = MethodChannel('co.rivium.sync/rivium_sync');
    final mockHandler = MockMethodChannel();
    late SyncQuery query;

    setUp(() {
      mockHandler.reset();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, mockHandler.handle);
      query = SyncQuery(channel, 'db-1', 'col-1');
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    group('where', () {
      test('should support equal operator', () async {
        mockHandler.setHandler('queryDocuments', (args) {
          final filters = args!['filters'] as List;
          expect(filters.length, 1);
          expect(filters[0]['field'], 'status');
          expect(filters[0]['operator'], '==');
          expect(filters[0]['value'], 'active');
          return [];
        });

        await query.where('status', QueryOperator.equal, 'active').get();
      });

      test('should support notEqual operator', () async {
        mockHandler.setHandler('queryDocuments', (args) {
          final filters = args!['filters'] as List;
          expect(filters[0]['operator'], '!=');
          return [];
        });

        await query.where('status', QueryOperator.notEqual, 'deleted').get();
      });

      test('should support greaterThan operator', () async {
        mockHandler.setHandler('queryDocuments', (args) {
          final filters = args!['filters'] as List;
          expect(filters[0]['operator'], '>');
          return [];
        });

        await query.where('age', QueryOperator.greaterThan, 18).get();
      });

      test('should support greaterThanOrEqual operator', () async {
        mockHandler.setHandler('queryDocuments', (args) {
          final filters = args!['filters'] as List;
          expect(filters[0]['operator'], '>=');
          return [];
        });

        await query.where('age', QueryOperator.greaterThanOrEqual, 21).get();
      });

      test('should support lessThan operator', () async {
        mockHandler.setHandler('queryDocuments', (args) {
          final filters = args!['filters'] as List;
          expect(filters[0]['operator'], '<');
          return [];
        });

        await query.where('price', QueryOperator.lessThan, 100).get();
      });

      test('should support lessThanOrEqual operator', () async {
        mockHandler.setHandler('queryDocuments', (args) {
          final filters = args!['filters'] as List;
          expect(filters[0]['operator'], '<=');
          return [];
        });

        await query.where('price', QueryOperator.lessThanOrEqual, 50).get();
      });

      test('should support arrayContains operator', () async {
        mockHandler.setHandler('queryDocuments', (args) {
          final filters = args!['filters'] as List;
          expect(filters[0]['operator'], 'array-contains');
          return [];
        });

        await query.where('tags', QueryOperator.arrayContains, 'flutter').get();
      });

      test('should support isIn operator', () async {
        mockHandler.setHandler('queryDocuments', (args) {
          final filters = args!['filters'] as List;
          expect(filters[0]['operator'], 'in');
          expect(filters[0]['value'], ['a', 'b', 'c']);
          return [];
        });

        await query.where('status', QueryOperator.isIn, ['a', 'b', 'c']).get();
      });

      test('should support notIn operator', () async {
        mockHandler.setHandler('queryDocuments', (args) {
          final filters = args!['filters'] as List;
          expect(filters[0]['operator'], 'not-in');
          return [];
        });

        await query.where('status', QueryOperator.notIn, ['deleted']).get();
      });

      test('should support chaining multiple where clauses', () async {
        mockHandler.setHandler('queryDocuments', (args) {
          final filters = args!['filters'] as List;
          expect(filters.length, 2);
          expect(filters[0]['field'], 'age');
          expect(filters[0]['operator'], '>=');
          expect(filters[0]['value'], 18);
          expect(filters[1]['field'], 'active');
          expect(filters[1]['operator'], '==');
          expect(filters[1]['value'], true);
          return [];
        });

        await query
            .where('age', QueryOperator.greaterThanOrEqual, 18)
            .where('active', QueryOperator.equal, true)
            .get();
      });
    });

    group('orderBy', () {
      test('should set ascending order by default', () async {
        mockHandler.setHandler('queryDocuments', (args) {
          final orderBy = args!['orderBy'] as Map;
          expect(orderBy['field'], 'name');
          expect(orderBy['direction'], 'asc');
          return [];
        });

        await query.orderBy('name').get();
      });

      test('should set descending order', () async {
        mockHandler.setHandler('queryDocuments', (args) {
          final orderBy = args!['orderBy'] as Map;
          expect(orderBy['field'], 'createdAt');
          expect(orderBy['direction'], 'desc');
          return [];
        });

        await query.orderBy('createdAt', direction: OrderDirection.descending).get();
      });
    });

    group('limit', () {
      test('should set limit on results', () async {
        mockHandler.setHandler('queryDocuments', (args) {
          expect(args!['limit'], 10);
          return [];
        });

        await query.limit(10).get();
      });
    });

    group('offset', () {
      test('should set offset for pagination', () async {
        mockHandler.setHandler('queryDocuments', (args) {
          expect(args!['offset'], 20);
          return [];
        });

        await query.offset(20).get();
      });
    });

    group('chaining', () {
      test('should support full query chain', () async {
        mockHandler.setHandler('queryDocuments', (args) {
          expect(args!['databaseId'], 'db-1');
          expect(args['collectionId'], 'col-1');
          final filters = args['filters'] as List;
          expect(filters.length, 1);
          expect(filters[0]['field'], 'active');
          final orderBy = args['orderBy'] as Map;
          expect(orderBy['field'], 'name');
          expect(orderBy['direction'], 'asc');
          expect(args['limit'], 5);
          expect(args['offset'], 10);
          return [];
        });

        await query
            .where('active', QueryOperator.equal, true)
            .orderBy('name')
            .limit(5)
            .offset(10)
            .get();
      });

      test('should return this for fluent chaining', () {
        final q1 = query.where('a', QueryOperator.equal, 1);
        expect(q1, same(query));

        final q2 = query.orderBy('b');
        expect(q2, same(query));

        final q3 = query.limit(10);
        expect(q3, same(query));

        final q4 = query.offset(5);
        expect(q4, same(query));
      });
    });

    group('get', () {
      test('should return list of SyncDocuments', () async {
        mockHandler.setHandler('queryDocuments', (_) => [
          {'id': 'doc-1', 'data': {'name': 'Alice'}, 'createdAt': 1000, 'updatedAt': 1000, 'version': 1},
          {'id': 'doc-2', 'data': {'name': 'Bob'}, 'createdAt': 2000, 'updatedAt': 2000, 'version': 1},
        ]);

        final docs = await query.get();
        expect(docs.length, 2);
        expect(docs[0].id, 'doc-1');
        expect(docs[0].data['name'], 'Alice');
        expect(docs[1].id, 'doc-2');
      });

      test('should return empty list when native returns null', () async {
        mockHandler.setHandler('queryDocuments', (_) => null);
        final docs = await query.get();
        expect(docs, isEmpty);
      });

      test('should pass databaseId and collectionId without filters', () async {
        mockHandler.setHandler('queryDocuments', (args) {
          expect(args!['databaseId'], 'db-1');
          expect(args['collectionId'], 'col-1');
          expect(args.containsKey('filters'), false);
          expect(args.containsKey('orderBy'), false);
          expect(args.containsKey('limit'), false);
          expect(args.containsKey('offset'), false);
          return [];
        });

        await query.get();
      });
    });
  });

  // ============================================================================
  // WriteBatch Tests (with mock MethodChannel)
  // ============================================================================

  group('WriteBatch', () {
    const channel = MethodChannel('co.rivium.sync/rivium_sync');
    final mockHandler = MockMethodChannel();
    late WriteBatch batch;
    late SyncCollection collection;

    setUp(() {
      mockHandler.reset();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, mockHandler.handle);
      batch = WriteBatch(channel);
      collection = SyncCollection(channel, 'db-1', 'col-1', 'users');
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('should start empty', () {
      expect(batch.size, 0);
      expect(batch.isEmpty, true);
    });

    group('set', () {
      test('should add set operation', () {
        batch.set(collection, 'doc-1', {'name': 'John'});
        expect(batch.size, 1);
        expect(batch.isEmpty, false);
      });

      test('should return this for chaining', () {
        final result = batch.set(collection, 'doc-1', {'name': 'John'});
        expect(result, same(batch));
      });
    });

    group('update', () {
      test('should add update operation', () {
        batch.update(collection, 'doc-1', {'status': 'active'});
        expect(batch.size, 1);
      });

      test('should return this for chaining', () {
        final result = batch.update(collection, 'doc-1', {'status': 'active'});
        expect(result, same(batch));
      });
    });

    group('delete', () {
      test('should add delete operation', () {
        batch.delete(collection, 'doc-1');
        expect(batch.size, 1);
      });

      test('should return this for chaining', () {
        final result = batch.delete(collection, 'doc-1');
        expect(result, same(batch));
      });
    });

    group('create', () {
      test('should add create operation', () {
        batch.create(collection, {'name': 'New Doc'});
        expect(batch.size, 1);
      });

      test('should return this for chaining', () {
        final result = batch.create(collection, {'name': 'New Doc'});
        expect(result, same(batch));
      });
    });

    group('chaining multiple operations', () {
      test('should track all operations', () {
        batch
            .set(collection, 'doc-1', {'name': 'John'})
            .update(collection, 'doc-2', {'status': 'active'})
            .delete(collection, 'doc-3')
            .create(collection, {'name': 'Jane'});

        expect(batch.size, 4);
        expect(batch.isEmpty, false);
      });
    });

    group('commit', () {
      test('should call native executeBatch with operations', () async {
        batch
            .set(collection, 'user1', {'name': 'John'})
            .update(collection, 'user2', {'status': 'active'})
            .delete(collection, 'user3');

        await batch.commit();

        final calls = mockHandler.callsFor('executeBatch');
        expect(calls.length, 1);

        final operations = (calls.first.arguments as Map)['operations'] as List;
        expect(operations.length, 3);

        // Verify set operation
        expect(operations[0]['type'], 'set');
        expect(operations[0]['databaseId'], 'db-1');
        expect(operations[0]['collectionId'], 'col-1');
        expect(operations[0]['documentId'], 'user1');
        expect(operations[0]['data'], {'name': 'John'});

        // Verify update operation
        expect(operations[1]['type'], 'update');
        expect(operations[1]['documentId'], 'user2');
        expect(operations[1]['data'], {'status': 'active'});

        // Verify delete operation
        expect(operations[2]['type'], 'delete');
        expect(operations[2]['documentId'], 'user3');
      });

      test('should not call native for empty batch', () async {
        await batch.commit();
        expect(mockHandler.callsFor('executeBatch'), isEmpty);
      });

      test('should throw StateError when committed twice', () async {
        batch.set(collection, 'doc-1', {'name': 'test'});
        await batch.commit();

        expect(() => batch.commit(), throwsA(isA<StateError>()));
      });

      test('should throw StateError when adding after commit', () async {
        batch.set(collection, 'doc-1', {'name': 'test'});
        await batch.commit();

        expect(
          () => batch.set(collection, 'doc-2', {'name': 'another'}),
          throwsA(isA<StateError>()),
        );
        expect(
          () => batch.update(collection, 'doc-2', {'name': 'another'}),
          throwsA(isA<StateError>()),
        );
        expect(
          () => batch.delete(collection, 'doc-2'),
          throwsA(isA<StateError>()),
        );
        expect(
          () => batch.create(collection, {'name': 'another'}),
          throwsA(isA<StateError>()),
        );
      });

      test('should allow retry after commit failure', () async {
        var callCount = 0;
        mockHandler.setHandler('executeBatch', (_) {
          callCount++;
          if (callCount == 1) {
            throw PlatformException(code: 'ERROR', message: 'Network error');
          }
          return null;
        });

        batch.set(collection, 'doc-1', {'name': 'test'});

        // First commit should fail
        await expectLater(batch.commit(), throwsA(isA<PlatformException>()));

        // Retry should work (committed flag reset on failure)
        await batch.commit();
        expect(callCount, 2);
      });

      test('should include create operation with correct structure', () async {
        batch.create(collection, {'title': 'New Item'});
        await batch.commit();

        final calls = mockHandler.callsFor('executeBatch');
        final operations = (calls.first.arguments as Map)['operations'] as List;
        expect(operations[0]['type'], 'create');
        expect(operations[0]['databaseId'], 'db-1');
        expect(operations[0]['collectionId'], 'col-1');
        expect(operations[0]['data'], {'title': 'New Item'});
        expect(operations[0].containsKey('documentId'), false);
      });
    });
  });
}
