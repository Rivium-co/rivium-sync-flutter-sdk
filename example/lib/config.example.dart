/// Configuration for the RiviumSync Example App
///
/// Copy this file to config.dart and replace the values with your own
/// API key and database ID from Rivium Console.
///
/// cp lib/config.example.dart lib/config.dart
class AppConfig {
  // Your project's API key (Rivium Console > your project > settings)
  static const String apiKey = 'YOUR_API_KEY_HERE';

  // Your database ID (create in RiviumSync console)
  static const String databaseId = 'YOUR_DATABASE_ID_HERE';

  // Demo collection names
  static const String todosCollection = 'todos';
  static const String usersCollection = 'users';
  static const String messagesCollection = 'messages';
}
