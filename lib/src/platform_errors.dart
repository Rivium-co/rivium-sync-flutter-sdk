import 'package:flutter/services.dart';

import 'rivium_sync_error.dart';

/// Runs [call] and turns the native side's errors into [RiviumSyncError]s,
/// with the HTTP status the server answered with ([RiviumSyncError.statusCode])
/// and, for a `query_not_allowed` answer, [RiviumSyncErrorCode.queryNotAllowed]
/// and its `fields`.
Future<T> withTypedErrors<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on PlatformException catch (e) {
    throw RiviumSyncError.fromPlatformException(e);
  }
}

/// The error a listener event carries, or null when it carries none.
RiviumSyncListenerError? listenerErrorOf(Map<dynamic, dynamic> event) {
  final error = event['error'];
  if (error == null) return null;
  if (error is Map) return RiviumSyncListenerError.fromMap(error);
  return RiviumSyncListenerError(code: 'UNKNOWN_ERROR', message: error.toString());
}
