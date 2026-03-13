// This is a basic Flutter widget test.

import 'package:flutter_test/flutter_test.dart';
import 'package:rivium_sync_example/main.dart';

void main() {
  testWidgets('App builds correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const RiviumSyncExampleApp());

    // Verify that the app builds
    expect(find.text('RiviumSync Demo'), findsOneWidget);
  });
}
