import 'package:flutter/services.dart';

/// Error types for RiviumSync SDK
enum RiviumSyncErrorCode {
  notInitialized,
  networkError,
  authenticationError,
  databaseError,
  collectionError,
  documentError,
  connectionError,
  timeoutError,
  permissionError,
  invalidResponse,

  /// The security rules do not allow this query: rules are not filters, so a
  /// query must only be able to return documents the rules allow. Add the
  /// filters named in [RiviumSyncError.fields].
  queryNotAllowed,
  unknown,
}

/// Error class for RiviumSync SDK
class RiviumSyncError implements Exception {
  final RiviumSyncErrorCode code;
  final String message;
  final String? details;

  /// For [RiviumSyncErrorCode.queryNotAllowed]: the fields to filter on, when
  /// the server names them (may be empty).
  final List<String> fields;

  /// The HTTP status the server answered with (for example 403 when your
  /// security rules refused the request, 404 when the document does not
  /// exist), or null when the server could not be reached or the error did
  /// not come from the server.
  final int? statusCode;

  const RiviumSyncError({
    required this.code,
    required this.message,
    this.details,
    this.fields = const [],
    this.statusCode,
  });

  /// True when the security rules refused the request (HTTP 403).
  bool get isPermissionDenied => statusCode == 403;

  factory RiviumSyncError.fromMap(Map<dynamic, dynamic> map) {
    final statusCode = (map['statusCode'] as num?)?.toInt();
    return RiviumSyncError(
      code: _errorCodeOf(map['code'] as String? ?? 'unknown', statusCode),
      message: map['message'] as String? ?? 'Unknown error',
      details: map['details'] as String?,
      fields: _stringList(map['fields']),
      statusCode: statusCode,
    );
  }

  /// The error for a failed call to the native SDK. The native side puts the
  /// HTTP status (and, for `query_not_allowed`, the fields) in
  /// [PlatformException.details].
  factory RiviumSyncError.fromPlatformException(PlatformException e) {
    final details = e.details;
    final map = details is Map ? details : const {};
    final statusCode = (map['statusCode'] as num?)?.toInt();
    return RiviumSyncError(
      code: _errorCodeOf(e.code, statusCode),
      message: e.message ??
          (e.code == RiviumSyncListenerError.queryNotAllowed
              ? 'This query is not allowed by the security rules.'
              : 'Unknown error'),
      fields: _stringList(map['fields']),
      statusCode: statusCode,
    );
  }

  @override
  String toString() {
    final extra = [
      if (statusCode != null) 'statusCode: $statusCode',
      if (fields.isNotEmpty) 'fields: $fields',
    ];
    return extra.isEmpty
        ? 'RiviumSyncError(code: $code, message: $message)'
        : 'RiviumSyncError(code: $code, message: $message, ${extra.join(', ')})';
  }
}

/// The [RiviumSyncErrorCode] for an error code the native side sent (an enum
/// name such as `connectionError`, a channel code such as `DOCUMENT_ERROR`, or
/// `query_not_allowed`) and the HTTP status, when there was one. A 401 or 403
/// wins over the channel code: it says why the call failed.
RiviumSyncErrorCode _errorCodeOf(String code, int? statusCode) {
  if (code == RiviumSyncListenerError.queryNotAllowed) {
    return RiviumSyncErrorCode.queryNotAllowed;
  }
  if (statusCode == 403) return RiviumSyncErrorCode.permissionError;
  if (statusCode == 401) return RiviumSyncErrorCode.authenticationError;
  for (final value in RiviumSyncErrorCode.values) {
    if (value.name == code) return value;
  }
  switch (code) {
    case 'DOCUMENT_ERROR':
      return RiviumSyncErrorCode.documentError;
    case 'COLLECTION_ERROR':
      return RiviumSyncErrorCode.collectionError;
    case 'DATABASE_ERROR':
    case 'QUERY_ERROR':
    case 'BATCH_ERROR':
      return RiviumSyncErrorCode.databaseError;
    case 'CONNECTION_ERROR':
      return RiviumSyncErrorCode.connectionError;
    case 'NOT_INITIALIZED':
      return RiviumSyncErrorCode.notInitialized;
    default:
      return RiviumSyncErrorCode.unknown;
  }
}

/// The error a realtime listener's `onError` receives.
///
/// After an error the listener receives nothing more. [code] is one of:
/// - [queryNotAllowed] (`query_not_allowed`): the security rules do not allow
///   the query; [fields] names the filters that would make it allowed, when
///   the server knows them.
/// - [listenerRevoked] (`listener_revoked`): the rules stopped allowing the
///   listener (the rules or the data changed).
/// - [permissionDenied] (`permission_denied`): the rules do not allow reading
///   what the listener listens to.
/// - another server code (for example `too_many_listeners`), or
///   `UNKNOWN_ERROR`.
class RiviumSyncListenerError implements Exception {
  /// `query_not_allowed`
  static const String queryNotAllowed = 'query_not_allowed';

  /// `listener_revoked`
  static const String listenerRevoked = 'listener_revoked';

  /// `permission_denied`
  static const String permissionDenied = 'permission_denied';

  final String code;
  final String message;

  /// For [queryNotAllowed]: the fields to filter on (may be empty).
  final List<String> fields;

  /// The HTTP status of the server's answer, when there was one.
  final int? statusCode;

  RiviumSyncListenerError({
    required this.code,
    required this.message,
    this.fields = const [],
    this.statusCode,
  });

  /// Reads the error map the native side sends with a listener event.
  factory RiviumSyncListenerError.fromMap(Map<dynamic, dynamic> map) {
    return RiviumSyncListenerError(
      code: map['code'] as String? ?? 'UNKNOWN_ERROR',
      message: map['message'] as String? ?? 'Unknown error',
      fields: _stringList(map['fields']),
      statusCode: (map['statusCode'] as num?)?.toInt(),
    );
  }

  /// True for `query_not_allowed`.
  bool get isQueryNotAllowed => code == queryNotAllowed;

  /// True for `listener_revoked`.
  bool get isListenerRevoked => code == listenerRevoked;

  @override
  String toString() => fields.isEmpty
      ? 'RiviumSyncListenerError($code): $message'
      : 'RiviumSyncListenerError($code): $message (fields: ${fields.join(', ')})';
}

/// The strings in [value] when it is a list, otherwise empty.
List<String> _stringList(Object? value) =>
    value is List ? value.whereType<String>().toList() : const [];
