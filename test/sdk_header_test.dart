import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivium_sync/rivium_sync.dart';

/// The plugin hands its identity to the native SDK, which sends
/// `X-Rivium-SDK: flutter/<version> android|ios/<native version>`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('riviumSyncSdkVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec);
    expect(match, isNotNull);
    expect(riviumSyncSdkVersion, match!.group(1));
    expect(riviumSyncSdkName, 'flutter');
  });

  test('RiviumSyncConfig forwards the wrapper identity', () {
    final map = const RiviumSyncConfig(apiKey: 'rv_live_test').toMap();
    expect(map['wrapperSdkName'], 'flutter');
    expect(map['wrapperSdkVersion'], riviumSyncSdkVersion);
  });

  test('init sends the wrapper identity to the native SDK', () async {
    const channel = MethodChannel('co.rivium.sync/rivium_sync');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    await RiviumSync.init(const RiviumSyncConfig(apiKey: 'rv_live_test'));

    final args = calls.singleWhere((c) => c.method == 'init').arguments as Map;
    expect(args['apiKey'], 'rv_live_test');
    expect(args['wrapperSdkName'], 'flutter');
    expect(args['wrapperSdkVersion'], riviumSyncSdkVersion);
  });
}
