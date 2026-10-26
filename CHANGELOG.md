## 0.3.0

### Breaking

- `set()` now replaces the document: fields you leave out are removed. Before,
  it merged into the existing document. To keep merging, pass `merge: true`:
  `todos.set('id', data, merge: true)`. `WriteBatch.set()` takes the same
  `merge` option.
- Failed calls (`add`, `get`, `getAll`, `update`, `set`, `delete`,
  `query.get()`, `batch.commit()`, `connect()`, collection and database calls)
  throw a `RiviumSyncError` instead of a `PlatformException`. Its new
  `statusCode` is the HTTP status the server answered with (403 when your
  security rules refused the request), or null when the server could not be
  reached. A 403 has code `RiviumSyncErrorCode.permissionError`, a 401
  `authenticationError`.
  To migrate, catch `RiviumSyncError` (`on RiviumSyncError catch (e)`) where
  you caught `PlatformException`.

### Added

- Streams for SDK events that any number of widgets can listen to and cancel:
  `RiviumSync.connectionStateChanges`, `syncStateChanges`,
  `pendingCountChanges` and `documentRejections`. The `onConnectionState`,
  `onSyncState`, `onPendingCount` and `onDocumentRejected` setters still work
  but keep one callback each, so a second screen replaced the first one's.
- Listeners are checked by your security rules on the server and receive only
  the changes they are allowed to see.
- The `onError` of `listen()`, `listenDocument()` and `query.listen()` tells
  you why a listener stopped, with a `RiviumSyncListenerError`:
  `query_not_allowed` when the rules do not allow the query (its `fields` name
  the filters that would make it allowed), `listener_revoked` when the rules
  stop allowing it, `permission_denied` when the rules do not allow reading
  it. After an error the listener receives nothing more. `onError` stays
  optional.
- `query.get()` and `getAll()` throw a `RiviumSyncError` with code
  `RiviumSyncErrorCode.queryNotAllowed` (and its `fields`) when the rules do
  not allow the query.
- `RiviumSync.onDocumentRejected((documentId, operation, error) {...})`: with
  offline persistence, a write that waited offline and that the server then
  refuses (your security rules, invalid data) is dropped instead of retried,
  the local copy goes back to what the server has (a refused new document
  disappears), and this callback tells you which one and why.

### Fixed

- A write made offline that could not be sent (no network, server error) is
  retried until it goes through. Before, it was given up after
  3 attempts and stayed on the device unsent, and a queued delete that failed
  this way was later sent as an update, so the document was not deleted.
- `RiviumSyncConfig.maxSyncRetries` is deprecated and has no effect: writes are retried until they go through, and refused ones are
  rolled back.
- `onSyncState` and `onPendingCount` were never called; they now report every
  change, on Android and iOS.

- `listenDocument()` receives only its own document, not every change in the
  collection.
- With offline persistence, the cache stands in only when the server could
  not answer (no network, timeout, 401, 408, 429, 5xx). A refusal by your
  security rules, invalid data or a missing document is thrown instead of
  answered from the cache, and a write the server refuses while online is not
  queued. Deleting a document that does not exist succeeds.
- Uses rivium-sync-android 0.3.0 and RiviumSync (iOS) 0.3.0, installed
  automatically.

## 0.2.8

- Several live listeners at once (for example two queries, or a collection
  and a document) all keep getting updates. Before, starting a second
  listener of the same kind could stop updates to the first one, and closing
  them could report "PlatformException(No active stream to cancel)".
- `get()` with offline persistence throws when the server can't be reached
  and the document is not cached, instead of returning null.
- Uses rivium-sync-android 0.2.8 and RiviumSync (iOS) 0.2.6, installed
  automatically.

## 0.2.7

- Android release builds (R8 / ProGuard) work without rules in your app.
- Uses rivium-sync-android 0.2.7, installed automatically.

## 0.2.6

- Realtime is always encrypted; the SDK never connects unencrypted.
- Uses rivium-sync-android 0.2.6 and RiviumSync (iOS) 0.2.5, installed
  automatically.

## 0.2.5

- Realtime connects where the Sync API tells it (host, port and whether the
  connection is encrypted), so your project can move to encrypted realtime
  (`mqtts`, port 8885) without an app update. It never falls back from an
  encrypted connection to a plain one.
- Uses rivium-sync-android 0.2.5 and RiviumSync (iOS) 0.2.4, installed
  automatically.
- Added `THIRD_PARTY_NOTICES.md`.

## 0.2.4

- The native SDKs now report this plugin to the Sync API in the
  `X-Rivium-SDK` header (`flutter/<version> android/<version>` or
  `flutter/<version> ios/<version>`), so the Console can show which SDK and
  version a project uses. Added `riviumSyncSdkName` / `riviumSyncSdkVersion`.
- Uses rivium-sync-android 0.2.4 and RiviumSync (iOS) 0.2.3, installed
  automatically.

## 0.2.3

- With offline persistence on, writes made before the realtime connection is up
  (or without calling `connect()`) now go to the server instead of waiting in
  the local queue. They are queued only when the device is known to be offline
  (Android 0.2.3, iOS 0.2.2).

## 0.2.2

- Android: fixed a crash when the connection was closed while it was still
  opening, for example on a device with no internet.

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
