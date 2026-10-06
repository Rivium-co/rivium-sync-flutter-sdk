# RiviumSync Flutter SDK

Realtime database SDK for Flutter with offline-first sync.

[![pub.dev](https://img.shields.io/pub/v/rivium_sync)](https://pub.dev/packages/rivium_sync)
[![Flutter 3.3+](https://img.shields.io/badge/Flutter-3.3+-blue.svg)](https://flutter.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Installation

```yaml
dependencies:
  rivium_sync: ^0.2.0
```

Then run:

```bash
flutter pub get
```

## Usage

Databases and collections are addressed by their **name**, exactly as shown in
Rivium Console:

```dart
await RiviumSync.init(RiviumSyncConfig(apiKey: 'YOUR_API_KEY'));
await RiviumSync.connect();

final todos = RiviumSync.database('my-app').collection('todos');

await todos.add({'title': 'Buy milk', 'completed': false});

final listener = todos.listen((documents) {
  print('Todos updated: ${documents.length}');
});
```

Use names, not UUIDs. Realtime updates are published per database and
collection name, so a UUID still works for plain reads and writes but live
updates never arrive.

## Verified user identity

Security Rules check `auth.uid`. The API key ships inside your app, so the app
cannot be trusted to say who the user is - only your own server can. Have your
backend mint a short-lived user token and give the SDK a way to get it:

```dart
await RiviumSync.init(RiviumSyncConfig(
  apiKey: 'rv_live_your_api_key',
  // Return null when no one is signed in.
  tokenProvider: () => myBackend.fetchRiviumToken(),
));

// When the user signs in or out:
await RiviumSync.refreshUserToken();
```

The SDK asks for a token at start and again before the old one expires. It is
the same Rivium user token Rivium Push and Rivium Chat use, so one function can
serve all three. Your backend mints it with your project's server secret, which
must stay on your server and never ship in an app.

If you would rather fetch the token yourself, call
`RiviumSync.setUserToken(token)` after `init` and again whenever you refresh it.

If your project has **Require signed user tokens** turned on in the Console, a
token is required; without it, requests are refused. You can still call
`connect()` before anyone is signed in: the SDK waits
(`RiviumSync.onAwaitingUserToken`) and connects by itself once it has a token.

## Documentation

- [Rivium Cloud](https://rivium.co/cloud)
- [Rivium Console](https://console.rivium.co)

## License

MIT
