/// Configuration for the RiviumSync Example App
///
/// Copy this file to config.dart and replace the values with your own
/// API key and database name from Rivium Console.
///
/// cp lib/config.example.dart lib/config.dart
class AppConfig {
  // Your project's API key (Rivium Console > your project > settings)
  static const String apiKey = 'YOUR_API_KEY_HERE';

  // Your database NAME, exactly as shown in Rivium Console (e.g. 'my-app').
  // Use the name, not the UUID: realtime updates only arrive for names.
  static const String databaseId = 'my-app';

  // Demo collection names
  static const String todosCollection = 'todos';
  static const String usersCollection = 'users';
  static const String messagesCollection = 'messages';
}
