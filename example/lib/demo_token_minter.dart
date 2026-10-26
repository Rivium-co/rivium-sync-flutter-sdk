import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:rivium_sync/rivium_sync.dart';

import 'app_config.dart';

/// Stands in for YOUR backend, so this example can run against a project that
/// has "Require signed user tokens" turned on.
///
/// Security Rules read `auth.uid`. An app cannot decide that value: its API key
/// ships inside the app, so anyone could claim any user. Only a server holding
/// the project's server secret can mint a user token.
///
/// In a real app, replace [fetchToken] with a call to your own endpoint, behind
/// your own login, that mints a token for the user who is actually signed in
/// (the Node SDK's `createUserToken` does this). The server secret must never be
/// in an app - this example only reads it in debug builds, from config/local.json.
class DemoTokenMinter {
  DemoTokenMinter._();

  static String get _apiUrl {
    final host = AppConfig.emulatorHost;
    return host != null ? 'http://$host:3006' : 'https://sync.rivium.co';
  }

  static String _currentUserId = AppConfig.demoUserId;

  /// The user the demo signs tokens for: `demoUserId`, or a second demo user
  /// after [switchUser] (to see what Security Rules do with another user's
  /// data). A real app signs in through its own login instead.
  static String get currentUserId => _currentUserId;

  /// The other demo user's id (`demoUserId` + "-2").
  static String get otherUserId => _currentUserId == AppConfig.demoUserId
      ? '${AppConfig.demoUserId}-2'
      : AppConfig.demoUserId;

  /// True when config/local.json gave this debug build a server secret.
  static bool get isConfigured => AppConfig.serverSecret.isNotEmpty;

  /// Sign in as the other demo user: the SDK asks [fetchToken] again and
  /// reconnects as that user.
  static Future<void> switchUser() async {
    _currentUserId = otherUserId;
    await RiviumSync.refreshUserToken();
  }

  /// Mints a token for the demo user. The SDK's token provider: called at
  /// init, shortly before the token expires, and on [RiviumSync.refreshUserToken].
  static Future<String?> fetchToken() async {
    if (!isConfigured) return null;
    final userId = _currentUserId;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(Uri.parse('$_apiUrl/users/token'));
      request.headers.contentType = ContentType.json;
      request.headers.set('x-api-key', AppConfig.apiKey);
      request.headers.set('x-server-secret', AppConfig.serverSecret);
      request.write(jsonEncode({'userId': userId}));
      final response = await request.close().timeout(const Duration(seconds: 10));
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode > 299) {
        debugPrint('DemoTokenMinter: token request failed (${response.statusCode})');
        return null;
      }
      final json = jsonDecode(text);
      // The Sync API wraps answers in `data`; accept both shapes.
      final body = json is Map && json['data'] is Map ? json['data'] as Map : json as Map;
      final token = body['token'] as String?;
      debugPrint('DemoTokenMinter: minted a user token for $userId');
      return token;
    } catch (e) {
      debugPrint('DemoTokenMinter: could not reach $_apiUrl: $e');
      return null;
    } finally {
      client.close();
    }
  }
}
