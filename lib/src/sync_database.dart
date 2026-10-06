import 'dart:async';
import 'package:flutter/services.dart';
import 'sync_collection.dart';
import 'sync_document.dart';
import 'write_batch.dart';

/// Represents a database in RiviumSync
class SyncDatabase {
  final MethodChannel _channel;

  /// The identifier this database is addressed by.
  ///
  /// For a reference obtained with `RiviumSync.database(name)` this is the
  /// database NAME you passed (as shown in Rivium Console).
  final String id;

  /// Database name
  final String name;

  SyncDatabase(this._channel, this.id, this.name);

  /// Create a new WriteBatch for atomic operations.
  ///
  /// A WriteBatch is used to perform multiple writes as a single atomic unit.
  /// None of the writes will be committed until `commit()` is called.
  ///
  /// Usage:
  /// ```dart
  /// final batch = database.batch();
  /// batch.set(usersCollection, 'user1', {'name': 'John'});
  /// batch.update(ordersCollection, 'order1', {'status': 'shipped'});
  /// batch.delete(tempCollection, 'temp1');
  /// await batch.commit();
  /// ```
  ///
  /// Returns a new WriteBatch instance.
  WriteBatch batch() {
    return WriteBatch(_channel);
  }

  /// Get a collection reference by its [name].
  ///
  /// Pass the collection NAME exactly as shown in Rivium Console (for example
  /// `'todos'`), not its UUID. Realtime updates are published per collection
  /// name, so `listen` only receives changes when you address the collection
  /// by name; a UUID would still work for plain reads and writes but live
  /// updates would never arrive.
  SyncCollection collection(String name) {
    return SyncCollection(_channel, id, name, name);
  }

  /// List all collections in this database
  Future<List<CollectionInfo>> listCollections() async {
    final result = await _channel.invokeMethod<List<dynamic>>(
      'listCollections',
      {'databaseId': id},
    );

    if (result == null) return [];

    return result
        .map((item) => CollectionInfo.fromMap(item as Map))
        .toList();
  }

  /// Create a new collection in this database
  Future<SyncCollection> createCollection(String name) async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'createCollection',
      {
        'databaseId': id,
        'name': name,
      },
    );

    if (result == null) {
      throw Exception('Failed to create collection');
    }

    final info = CollectionInfo.fromMap(result);
    // Keyed by name, like collection(): realtime topics carry names, so a
    // UUID-keyed collection would never receive live updates.
    return SyncCollection(_channel, id, info.name, info.name);
  }

  /// Delete a collection
  Future<void> deleteCollection(String collectionId) async {
    await _channel.invokeMethod(
      'deleteCollection',
      {'collectionId': collectionId},
    );
  }
}
