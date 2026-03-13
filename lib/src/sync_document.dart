/// Represents a document in a RiviumSync collection
class SyncDocument {
  /// Unique document ID
  final String id;

  /// Document data
  final Map<String, dynamic> data;

  /// Creation timestamp (milliseconds since epoch)
  final int createdAt;

  /// Last update timestamp (milliseconds since epoch)
  final int updatedAt;

  /// Document version for conflict resolution
  final int version;

  const SyncDocument({
    required this.id,
    required this.data,
    required this.createdAt,
    required this.updatedAt,
    this.version = 1,
  });

  factory SyncDocument.fromMap(Map<dynamic, dynamic> map) {
    return SyncDocument(
      id: map['id'] as String? ?? '',
      data: Map<String, dynamic>.from(map['data'] as Map? ?? {}),
      createdAt: (map['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (map['updatedAt'] as num?)?.toInt() ?? 0,
      version: (map['version'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'data': data,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'version': version,
      };

  /// Get a value from document data
  T? get<T>(String field) => data[field] as T?;

  /// Get a string value
  String? getString(String field) => data[field] as String?;

  /// Get an integer value
  int? getInt(String field) => (data[field] as num?)?.toInt();

  /// Get a double value
  double? getDouble(String field) => (data[field] as num?)?.toDouble();

  /// Get a boolean value
  bool? getBool(String field) => data[field] as bool?;

  /// Get a list value
  List<T>? getList<T>(String field) => (data[field] as List?)?.cast<T>();

  /// Get a map value
  Map<String, dynamic>? getMap(String field) =>
      data[field] != null ? Map<String, dynamic>.from(data[field] as Map) : null;

  /// Check if field exists
  bool contains(String field) => data.containsKey(field);

  /// Check if document exists (has valid ID)
  bool get exists => id.isNotEmpty;

  @override
  String toString() => 'SyncDocument(id: $id, data: $data)';
}

/// Database info from server
class DatabaseInfo {
  final String id;
  final String name;
  final int createdAt;
  final int updatedAt;

  const DatabaseInfo({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DatabaseInfo.fromMap(Map<dynamic, dynamic> map) {
    return DatabaseInfo(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      createdAt: (map['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (map['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Collection info from server
class CollectionInfo {
  final String id;
  final String name;
  final String databaseId;
  final int documentCount;
  final int createdAt;
  final int updatedAt;

  const CollectionInfo({
    required this.id,
    required this.name,
    required this.databaseId,
    required this.documentCount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CollectionInfo.fromMap(Map<dynamic, dynamic> map) {
    return CollectionInfo(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      databaseId: map['databaseId'] as String? ?? '',
      documentCount: (map['documentCount'] as num?)?.toInt() ?? 0,
      createdAt: (map['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (map['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }
}
