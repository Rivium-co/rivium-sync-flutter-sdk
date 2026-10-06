## 0.2.1

- Added `tokenProvider`, `RiviumSync.setTokenProvider()` and
  `RiviumSync.refreshUserToken()`: the SDK gets and renews the user token itself.
- `connect()` can be called before sign-in when user tokens are required: the
  SDK waits for a token and then connects (`onAwaitingUserToken`,
  `isAwaitingUserToken()`).
- Setting a token for a different user reconnects as that user.

## 0.2.0

- Added `userToken` in the config and `RiviumSync.setUserToken()`, so Security
  Rules can trust `auth.uid`. Your backend mints a short-lived token.
- Uses the 0.2.0 native SDKs, which fix: `getAll()` stopping at 100 documents,
  deleted documents reappearing offline, stale reads at app start, and an app
  started offline never connecting.

## 0.1.0

- Initial release
- Realtime database SDK with offline-first sync
- CRUD operations, batch writes, queries
- Realtime listeners for collections, documents, and queries
- Offline persistence with conflict resolution
- Android and iOS platform support
