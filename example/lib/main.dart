import 'package:flutter/material.dart';
import 'package:rivium_sync/rivium_sync.dart';
import 'screens/home_screen.dart';
import 'app_config.dart';
import 'demo_token_minter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Values come from config/local.json, see app_config.dart.
  if (!await AppConfig.load()) {
    runApp(const _MissingConfigApp());
    return;
  }

  await RiviumSync.init(RiviumSyncConfig(
    apiKey: AppConfig.apiKey,
    offlineEnabled: true,
    // Set debugMode: true only during development to see internal SDK logs
    debugMode: true,
    // The signed-in user's token. DemoTokenMinter stands in for your backend
    // (debug builds with a serverSecret only).
    tokenProvider: DemoTokenMinter.isConfigured ? DemoTokenMinter.fetchToken : null,
    // A Rivium Sync server on your computer (debug builds only), see app_config.dart.
    emulatorHost: AppConfig.emulatorHost,
  ));

  runApp(const RiviumSyncExampleApp());
}

class RiviumSyncExampleApp extends StatelessWidget {
  const RiviumSyncExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RiviumSync Example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF10B981), // Emerald green
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF10B981),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}

/// Shown instead of the demo when config/local.json is missing or has no API key.
class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No API key.\n\nCopy example/config/local.example.json to '
              'example/config/local.json, fill it in, and run the app again.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
