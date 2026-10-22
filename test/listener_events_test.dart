import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivium_sync/rivium_sync.dart';

/// Several live listeners of one kind share one EventChannel. Flutter keeps a single active stream per channel, so
/// before 0.2.8 a second listener silently took the stream from the first (whose updates were dropped) and closing
/// both raised "PlatformException(No active stream to cancel)" on Android.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const method = MethodChannel('co.rivium.sync/rivium_sync');
  const queryEvents = EventChannel('co.rivium.sync/query_events');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<String> listenerIds;
  late int listens;
  late int cancels;
  MockStreamHandlerEventSink? sink;

  setUp(() {
    listenerIds = [];
    listens = 0;
    cancels = 0;
    sink = null;
    messenger.setMockMethodCallHandler(method, (call) async {
      if (call.method == 'listenQuery') listenerIds.add((call.arguments as Map)['listenerId'] as String);
      return null;
    });
    messenger.setMockStreamHandler(
      queryEvents,
      MockStreamHandler.inline(
        onListen: (args, events) {
          listens++;
          sink = events;
        },
        onCancel: (args) => cancels++,
      ),
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(method, null);
    messenger.setMockStreamHandler(queryEvents, null);
  });

  Map<String, Object?> docs(String listenerId, String docId) => {
        'listenerId': listenerId,
        'documents': [
          {'id': docId, 'data': <String, Object?>{}, 'createdAt': 0, 'updatedAt': 0, 'version': 1},
        ],
      };

  test('two query listeners each get their own updates', () async {
    final collection = SyncCollection(method, 'db', 'team_members', 'team_members');
    final a = <String>[];
    final b = <String>[];
    final ra = collection.query().listen((d) => a.addAll(d.map((x) => x.id)));
    final rb = collection.query().listen((d) => b.addAll(d.map((x) => x.id)));
    await pumpEventQueue();

    expect(listenerIds, hasLength(2));
    expect(listenerIds[0], isNot(listenerIds[1]));
    expect(listens, 1, reason: 'one shared stream for the channel');

    sink!.success(docs(listenerIds[0], 'for-a'));
    sink!.success(docs(listenerIds[1], 'for-b'));
    await pumpEventQueue();

    expect(a, ['for-a'], reason: 'the first listener still gets updates after the second one started');
    expect(b, ['for-b']);

    ra.remove();
    rb.remove();
    await pumpEventQueue();
  });

  test('closing several listeners cancels the stream once, without an error', () async {
    final collection = SyncCollection(method, 'db', 'shared_scans', 'shared_scans');
    final errors = <Object>[];
    final regs = [
      for (var i = 0; i < 3; i++) collection.query().listen((_) {}, onError: errors.add),
    ];
    await pumpEventQueue();
    for (final r in regs) {
      r.remove();
    }
    await pumpEventQueue();

    expect(listens, 1);
    expect(cancels, 1);
    expect(errors, isEmpty);

    // A new listener after all were closed opens the stream again.
    final r = collection.query().listen((_) {});
    await pumpEventQueue();
    expect(listens, 2);
    r.remove();
    await pumpEventQueue();
    expect(cancels, 2);
  });
}
