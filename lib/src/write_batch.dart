import 'package:flutter/services.dart';
import 'sync_collection.dart';

/// A write batch is used to perform multiple writes as a single atomic unit.
///
/// A WriteBatch object can be acquired by calling `RiviumSync.batch()`. It provides
/// methods for adding writes to the batch. None of the writes will be committed
/// (or visible locally) until `commit()` is called.
///
/// Unlike transactions, write batches are persisted offline and therefore are
/// preferable when you don't need to condition your writes on read data.
///
/// Usage:
/// ```dart
/// final batch = RiviumSync.batch();
///
/// // Set a document
/// batch.set(usersCollection, 'user1', {'name': 'John', 'age': 30});
///
/// // Update a document
/// batch.update(usersCollection, 'user2', {'status': 'active'});
///
/// // Delete a document
/// batch.delete(usersCollection, 'user3');
///
/// // Commit the batch
/// await batch.commit();
/// ```
class WriteBatch {
  final MethodChannel _channel;
  final List<Map<String, dynamic>> _operations = [];
  bool _committed = false;

  WriteBatch(this._channel);

  /// Writes to the document referred to by the provided collection and document ID.
  /// If the document does not exist yet, it will be created.
  /// If the document exists, its contents will be overwritten.
  ///
  /// Returns this WriteBatch instance for chaining.
  WriteBatch set(SyncCollection collection, String documentId, Map<String, dynamic> data) {
    _checkNotCommitted();
    _operations.add({
      'type': 'set',
      'databaseId': collection.databaseId,
      'collectionId': collection.id,
      'documentId': documentId,
      'data': data,
    });
    return this;
  }

  /// Updates fields in the document referred to by the provided collection and document ID.
  /// The document must exist. Fields not specified in the update are not modified.
  ///
  /// Returns this WriteBatch instance for chaining.
  WriteBatch update(SyncCollection collection, String documentId, Map<String, dynamic> data) {
    _checkNotCommitted();
    _operations.add({
      'type': 'update',
      'databaseId': collection.databaseId,
      'collectionId': collection.id,
      'documentId': documentId,
      'data': data,
    });
    return this;
  }

  /// Deletes the document referred to by the provided collection and document ID.
  ///
  /// Returns this WriteBatch instance for chaining.
  WriteBatch delete(SyncCollection collection, String documentId) {
    _checkNotCommitted();
    _operations.add({
      'type': 'delete',
      'databaseId': collection.databaseId,
      'collectionId': collection.id,
      'documentId': documentId,
    });
    return this;
  }

  /// Creates a new document with an auto-generated ID in the specified collection.
  ///
  /// Returns this WriteBatch instance for chaining.
  WriteBatch create(SyncCollection collection, Map<String, dynamic> data) {
    _checkNotCommitted();
    _operations.add({
      'type': 'create',
      'databaseId': collection.databaseId,
      'collectionId': collection.id,
      'data': data,
    });
    return this;
  }

  /// Commits all of the writes in this write batch as a single atomic unit.
  ///
  /// Throws an exception if the batch commit fails or if the batch has already been committed.
  Future<void> commit() async {
    _checkNotCommitted();
    _committed = true;

    if (_operations.isEmpty) {
      return;
    }

    try {
      await _channel.invokeMethod('executeBatch', {
        'operations': _operations,
      });
    } catch (e) {
      _committed = false; // Allow retry
      rethrow;
    }
  }

  /// Returns the number of operations in this batch.
  int get size => _operations.length;

  /// Returns true if this batch has no operations.
  bool get isEmpty => _operations.isEmpty;

  void _checkNotCommitted() {
    if (_committed) {
      throw StateError('WriteBatch has already been committed');
    }
  }
}
