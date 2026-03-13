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
  unknown,
}

/// Error class for RiviumSync SDK
class RiviumSyncError implements Exception {
  final RiviumSyncErrorCode code;
  final String message;
  final String? details;

  const RiviumSyncError({
    required this.code,
    required this.message,
    this.details,
  });

  factory RiviumSyncError.fromMap(Map<dynamic, dynamic> map) {
    final codeString = map['code'] as String? ?? 'unknown';
    final code = RiviumSyncErrorCode.values.firstWhere(
      (e) => e.name == codeString,
      orElse: () => RiviumSyncErrorCode.unknown,
    );

    return RiviumSyncError(
      code: code,
      message: map['message'] as String? ?? 'Unknown error',
      details: map['details'] as String?,
    );
  }

  @override
  String toString() => 'RiviumSyncError(code: $code, message: $message)';
}
