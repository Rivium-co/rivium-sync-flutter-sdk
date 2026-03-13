import 'dart:async';
import 'package:flutter/services.dart';
import 'sync_document.dart';
import 'sync_query.dart';

/// Represents a collection in a RiviumSync database
class SyncCollection {
  final MethodChannel _channel;
  final String _databaseId;

  /// Collection ID
  final String id;

  /// Collection name
  final String name;

  SyncCollection(this._channel, this._databaseId, this.id, this.name);

  /// Database ID this collection belongs to
  String get databaseId => _databaseId;

  // ==================== CRUD Operations ====================

  /// Add a new document to the collection
  Future<SyncDocument> add(Map<String, dynamic> data) async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'addDocument',
      {
        'databaseId': _databaseId,
        'collectionId': id,
        'data': data,
      },
    );

    if (result == null) {
      throw Exception('Failed to add document');
    }

    return SyncDocument.fromMap(result);
  }

  /// Get a document by ID
  Future<SyncDocument?> get(String documentId) async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getDocument',
      {
        'databaseId': _databaseId,
        'collectionId': id,
        'documentId': documentId,
      },
    );

    if (result == null) return null;
    return SyncDocument.fromMap(result);
  }

  /// Get all documents in the collection
  Future<List<SyncDocument>> getAll() async {
    final result = await _channel.invokeMethod<List<dynamic>>(
      'getAllDocuments',
      {
        'databaseId': _databaseId,
        'collectionId': id,
      },
    );

    if (result == null) return [];

    return result.map((item) => SyncDocument.fromMap(item as Map)).toList();
  }

  /// Update a document (partial update)
  Future<SyncDocument> update(
      String documentId, Map<String, dynamic> data) async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'updateDocument',
      {
        'databaseId': _databaseId,
        'collectionId': id,
        'documentId': documentId,
        'data': data,
      },
    );

    if (result == null) {
      throw Exception('Failed to update document');
    }

    return SyncDocument.fromMap(result);
  }

  /// Set a document (replace entire data)
  Future<SyncDocument> set(
      String documentId, Map<String, dynamic> data) async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'setDocument',
      {
        'databaseId': _databaseId,
        'collectionId': id,
        'documentId': documentId,
        'data': data,
      },
    );

    if (result == null) {
      throw Exception('Failed to set document');
    }

    return SyncDocument.fromMap(result);
  }

  /// Delete a document
  Future<void> delete(String documentId) async {
    await _channel.invokeMethod(
      'deleteDocument',
      {
        'databaseId': _databaseId,
        'collectionId': id,
        'documentId': documentId,
      },
    );
  }

  // ==================== Query Operations ====================

  /// Create a query builder
  SyncQuery query() {
    return SyncQuery(_channel, _databaseId, id);
  }

  /// Create a query with a where clause
  SyncQuery where(String field, QueryOperator op, dynamic value) {
    return query().where(field, op, value);
  }

  // ==================== Realtime Listeners ====================

  /// Listen to all changes in the collection
  ///
  /// [callback] is called whenever documents in the collection change
  /// [onError] is called when an error occurs (optional)
  ListenerRegistration listen(
    void Function(List<SyncDocument> documents) callback, {
    void Function(Object error)? onError,
  }) {
    final listenerId =
        'collection_${id}_${DateTime.now().millisecondsSinceEpoch}';

    // IMPORTANT: Set up event channel subscription BEFORE calling native method
    // This prevents race condition where native sends events before Flutter is listening
    final subscription = const EventChannel('co.rivium.sync/collection_events')
        .receiveBroadcastStream(listenerId)
        .listen(
      (data) {
        if (data is Map) {
          // Check for error
          if (data['error'] != null) {
            onError?.call(RiviumSyncListenerError(
              code: data['error']['code'] as String? ?? 'UNKNOWN_ERROR',
              message: data['error']['message'] as String? ?? 'Unknown error',
            ));
            return;
          }
          // Extract documents from the wrapped response {listenerId: ..., documents: [...]}
          final documentsList = data['documents'];
          if (documentsList is List) {
            final documents = documentsList
                .map((item) => SyncDocument.fromMap(item as Map))
                .toList();
            callback(documents);
          }
        }
      },
      onError: (error) {
        onError?.call(error);
      },
    );

    // Now start the native listener after event channel is ready
    _channel.invokeMethod('listenCollection', {
      'databaseId': _databaseId,
      'collectionId': id,
      'listenerId': listenerId,
    });

    return ListenerRegistration(() {
      subscription.cancel();
      _channel
          .invokeMethod('removeCollectionListener', {'listenerId': listenerId});
    });
  }

  /// Listen to changes in a specific document
  ///
  /// [documentId] is the ID of the document to listen to
  /// [callback] is called whenever the document changes (null if deleted)
  /// [onError] is called when an error occurs (optional)
  ListenerRegistration listenDocument(
    String documentId,
    void Function(SyncDocument? document) callback, {
    void Function(Object error)? onError,
  }) {
    final listenerId =
        'doc_${id}_${documentId}_${DateTime.now().millisecondsSinceEpoch}';

    // IMPORTANT: Set up event channel subscription BEFORE calling native method
    // This prevents race condition where native sends events before Flutter is listening
    final subscription = const EventChannel('co.rivium.sync/document_events')
        .receiveBroadcastStream(listenerId)
        .listen(
      (data) {
        if (data == null) {
          callback(null);
        } else if (data is Map) {
          // Check for error
          if (data['error'] != null) {
            onError?.call(RiviumSyncListenerError(
              code: data['error']['code'] as String? ?? 'UNKNOWN_ERROR',
              message: data['error']['message'] as String? ?? 'Unknown error',
            ));
            return;
          }
          // Extract document from the wrapped response {listenerId: ..., document: ...}
          final documentData = data['document'];
          if (documentData == null) {
            callback(null);
          } else if (documentData is Map) {
            callback(SyncDocument.fromMap(documentData));
          } else {
            callback(null);
          }
        }
      },
      onError: (error) {
        onError?.call(error);
      },
    );

    // Now start the native listener after event channel is ready
    _channel.invokeMethod('listenDocument', {
      'databaseId': _databaseId,
      'collectionId': id,
      'documentId': documentId,
      'listenerId': listenerId,
    });

    return ListenerRegistration(() {
      subscription.cancel();
      _channel
          .invokeMethod('removeDocumentListener', {'listenerId': listenerId});
    });
  }
}

/// Error class for listener errors
class RiviumSyncListenerError implements Exception {
  final String code;
  final String message;

  RiviumSyncListenerError({required this.code, required this.message});

  @override
  String toString() => 'RiviumSyncListenerError($code): $message';
}
