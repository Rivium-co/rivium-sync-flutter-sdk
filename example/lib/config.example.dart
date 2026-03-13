/// Configuration for the RiviumSync Example App
///
/// Copy this file to config.dart and replace the values with your own
/// API key and database ID from the AuthLeap dashboard.
///
/// cp lib/config.example.dart lib/config.dart
class AppConfig {
  // Your RiviumSync Project API Key (get from AuthLeap dashboard > Projects)
  static const String apiKey = 'YOUR_API_KEY_HERE';

  // Your database ID (create in RiviumSync console)
  static const String databaseId = 'YOUR_DATABASE_ID_HERE';

  // For local development, use these instead:
  // static const String baseUrl = 'http://localhost:3006';
  // static const String mqttUrl = 'ws://localhost:8083';

  // Demo collection names
  static const String todosCollection = 'todos';
  static const String usersCollection = 'users';
  static const String messagesCollection = 'messages';
}
