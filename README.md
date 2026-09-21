# RiviumSync Flutter SDK

Realtime database SDK for Flutter with offline-first sync powered by pn-protocol.

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

## Verified user identity

Security Rules check `auth.uid`. The API key ships inside your app, so the app
cannot be trusted to say who the user is - only your own server can. Have your
backend mint a short-lived user token and hand it to the SDK:

```dart
// After RiviumSync.init(...):
final token = await myBackend.fetchSyncToken();
await RiviumSync.setUserToken(token);
```

Call it again whenever you refresh the token. Your backend mints it with your
project's server secret, which must stay on your server and never ship in an
app.

If your project has **Require signed user tokens** turned on in the Console, a
token is required; without it, requests are refused.

## Documentation

- [Rivium Cloud](https://rivium.co/cloud)
- [Rivium Console](https://console.rivium.co)

## License

MIT
