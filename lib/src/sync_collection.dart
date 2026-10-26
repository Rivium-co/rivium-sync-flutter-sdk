import 'dart:async';
import 'package:flutter/services.dart';
import 'listener_events.dart';
import 'platform_errors.dart';
import 'sync_document.dart';
import 'sync_query.dart';

/// Represents a collection in a RiviumSync database
class SyncCollection {
  final MethodChannel _channel;
  final String _databaseId;

  /// The identifier this collection is addressed by.
  ///
  /// For a reference obtained with `database.collection(name)` this is the
  /// collection NAME you passed (as shown in Rivium Console).
  final String id;

  /// Collection name
  final String name;

  SyncCollection(this._channel, this._databaseId, this.id, this.name);

  /// The database this collection belongs to, as it was addressed - the
  /// database NAME passed to `RiviumSync.database(name)`.
  String get databaseId => _databaseId;

  // ==================== CRUD Operations ====================

  /// Add a new document to the collection
  Future<SyncDocument> add(Map<String, dynamic> data) async {
    final result = await withTypedErrors(() => _channel.invokeMethod<Map<dynamic, dynamic>>(
      'addDocument',
      {
        'databaseId': _databaseId,
        'collectionId': id,
        'data': data,
      },
    ));

    if (result == null) {
      throw Exception('Failed to add document');
    }

    return SyncDocument.fromMap(result);
  }

  /// Get a document by ID
  Future<SyncDocument?> get(String documentId) async {
    final result = await withTypedErrors(() => _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getDocument',
      {
        'databaseId': _databaseId,
        'collectionId': id,
        'documentId': documentId,
      },
    ));

    if (result == null) return null;
    return SyncDocument.fromMap(result);
  }

  /// Get all documents in the collection
  Future<List<SyncDocument>> getAll() async {
    final result = await withTypedErrors(() => _channel.invokeMethod<List<dynamic>>(
      'getAllDocuments',
      {
        'databaseId': _databaseId,
        'collectionId': id,
      },
    ));

    if (result == null) return [];

    return result.map((item) => SyncDocument.fromMap(item as Map)).toList();
  }

  /// Update a document (partial update)
  Future<SyncDocument> update(
      String documentId, Map<String, dynamic> data) async {
    final result = await withTypedErrors(() => _channel.invokeMethod<Map<dynamic, dynamic>>(
      'updateDocument',
      {
        'databaseId': _databaseId,
        'collectionId': id,
        'documentId': documentId,
        'data': data,
      },
    ));

    if (result == null) {
      throw Exception('Failed to update document');
    }

    return SyncDocument.fromMap(result);
  }

  /// Write a document, creating it if it does not exist.
  ///
  /// By default the document becomes exactly [data]: fields left out are
  /// removed. With [merge] `true`, [data] is merged into the document instead
  /// and its other fields are kept.
  ///
  /// ```dart
  /// await todos.set('todo-1', {'title': 'Buy milk', 'completed': false});
  /// await todos.set('todo-1', {'completed': true}, merge: true);
  /// ```
  Future<SyncDocument> set(
    String documentId,
    Map<String, dynamic> data, {
    bool merge = false,
  }) async {
    final result = await withTypedErrors(() => _channel.invokeMethod<Map<dynamic, dynamic>>(
      'setDocument',
      {
        'databaseId': _databaseId,
        'collectionId': id,
        'documentId': documentId,
        'data': data,
        'merge': merge,
      },
    ));

    if (result == null) {
      throw Exception('Failed to set document');
    }

    return SyncDocument.fromMap(result);
  }

  /// Delete a document
  Future<void> delete(String documentId) async {
    await withTypedErrors(() => _channel.invokeMethod(
      'deleteDocument',
      {
        'databaseId': _databaseId,
        'collectionId': id,
        'documentId': documentId,
      },
    ));
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
  /// [callback] is called with the current documents, then whenever documents
  /// in the collection change.
  /// [onError] (optional) gets a [RiviumSyncListenerError] when the security
  /// rules do not allow the listener or stop allowing it
  /// (`listener_revoked`); after an error the listener receives nothing more.
  ListenerRegistration listen(
    void Function(List<SyncDocument> documents) callback, {
    void Function(Object error)? onError,
  }) {
    final listenerId = ListenerEvents.newListenerId('collection_$id');

    // Subscribe BEFORE calling the native method, so no event is sent before Flutter listens.
    final stop = ListenerEvents.listen(
      'co.rivium.sync/collection_events',
      listenerId,
      (data) {
        // The listener stopped: the security rules refused or revoked it.
        final error = listenerErrorOf(data);
        if (error != null) {
          onError?.call(error);
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
      },
      onError,
    );

    // Now start the native listener after event channel is ready
    _channel.invokeMethod('listenCollection', {
      'databaseId': _databaseId,
      'collectionId': id,
      'listenerId': listenerId,
    });

    return ListenerRegistration(() {
      stop();
      _channel
          .invokeMethod('removeCollectionListener', {'listenerId': listenerId});
    });
  }

  /// Listen to changes in a specific document
  ///
  /// [documentId] is the ID of the document to listen to
  /// [callback] is called with the current document (null when it does not
  /// exist), then whenever it changes (null when it is deleted).
  /// [onError] (optional): as for [listen].
  ListenerRegistration listenDocument(
    String documentId,
    void Function(SyncDocument? document) callback, {
    void Function(Object error)? onError,
  }) {
    final listenerId = ListenerEvents.newListenerId('doc_${id}_$documentId');

    // Subscribe BEFORE calling the native method, so no event is sent before Flutter listens.
    final stop = ListenerEvents.listen(
      'co.rivium.sync/document_events',
      listenerId,
      (data) {
        // The listener stopped: the security rules refused or revoked it.
        final error = listenerErrorOf(data);
        if (error != null) {
          onError?.call(error);
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
      },
      onError,
    );

    // Now start the native listener after event channel is ready
    _channel.invokeMethod('listenDocument', {
      'databaseId': _databaseId,
      'collectionId': id,
      'documentId': documentId,
      'listenerId': listenerId,
    });

    return ListenerRegistration(() {
      stop();
      _channel
          .invokeMethod('removeDocumentListener', {'listenerId': listenerId});
    });
  }
}
