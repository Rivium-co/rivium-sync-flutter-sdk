import 'dart:async';
import 'package:flutter/services.dart';
import 'listener_events.dart';
import 'platform_errors.dart';
import 'sync_document.dart';

/// Query operators for filtering
enum QueryOperator {
  equal,
  notEqual,
  greaterThan,
  greaterThanOrEqual,
  lessThan,
  lessThanOrEqual,
  arrayContains,
  isIn,
  notIn,
}

/// Order direction for queries
enum OrderDirection {
  ascending,
  descending,
}

/// Listener registration for unsubscribing from realtime updates
class ListenerRegistration {
  final void Function() _onRemove;

  ListenerRegistration(this._onRemove);

  /// Remove the listener
  void remove() => _onRemove();
}

/// Query builder for collections
class SyncQuery {
  final MethodChannel _channel;
  final String _databaseId;
  final String _collectionId;
  final List<Map<String, dynamic>> _filters = [];
  String? _orderByField;
  String _orderDirection = 'asc';
  int? _limitCount;
  int? _offsetCount;

  SyncQuery(this._channel, this._databaseId, this._collectionId);

  /// Add a where clause to the query
  SyncQuery where(String field, QueryOperator op, dynamic value) {
    String opString;
    switch (op) {
      case QueryOperator.equal:
        opString = '==';
        break;
      case QueryOperator.notEqual:
        opString = '!=';
        break;
      case QueryOperator.greaterThan:
        opString = '>';
        break;
      case QueryOperator.greaterThanOrEqual:
        opString = '>=';
        break;
      case QueryOperator.lessThan:
        opString = '<';
        break;
      case QueryOperator.lessThanOrEqual:
        opString = '<=';
        break;
      case QueryOperator.arrayContains:
        opString = 'array-contains';
        break;
      case QueryOperator.isIn:
        opString = 'in';
        break;
      case QueryOperator.notIn:
        opString = 'not-in';
        break;
    }

    _filters.add({
      'field': field,
      'operator': opString,
      'value': value,
    });
    return this;
  }

  /// Set order by clause
  SyncQuery orderBy(String field,
      {OrderDirection direction = OrderDirection.ascending}) {
    _orderByField = field;
    _orderDirection = direction == OrderDirection.ascending ? 'asc' : 'desc';
    return this;
  }

  /// Set limit on results
  SyncQuery limit(int count) {
    _limitCount = count;
    return this;
  }

  /// Set offset for pagination
  SyncQuery offset(int count) {
    _offsetCount = count;
    return this;
  }

  Map<String, dynamic> _buildQueryParams() {
    final params = <String, dynamic>{
      'databaseId': _databaseId,
      'collectionId': _collectionId,
    };

    if (_filters.isNotEmpty) {
      params['filters'] = _filters;
    }
    if (_orderByField != null) {
      params['orderBy'] = {
        'field': _orderByField,
        'direction': _orderDirection,
      };
    }
    if (_limitCount != null) {
      params['limit'] = _limitCount;
    }
    if (_offsetCount != null) {
      params['offset'] = _offsetCount;
    }

    return params;
  }

  /// Execute the query and get results.
  ///
  /// Throws a [RiviumSyncError] with [RiviumSyncErrorCode.queryNotAllowed]
  /// when the security rules do not allow the query; its `fields` name the
  /// filters that would make it allowed.
  Future<List<SyncDocument>> get() async {
    final result = await withTypedErrors(() => _channel.invokeMethod<List<dynamic>>(
          'queryDocuments',
          _buildQueryParams(),
        ));

    if (result == null) return [];

    return result.map((item) => SyncDocument.fromMap(item as Map)).toList();
  }

  /// Listen to query results in realtime
  ///
  /// [callback] is called with the current results, then whenever they change.
  /// [onError] (optional) gets a [RiviumSyncListenerError]: `query_not_allowed`
  /// (with `fields`) when the security rules do not allow the query, or
  /// `listener_revoked` when they stop allowing it. After an error the
  /// listener receives nothing more.
  ListenerRegistration listen(
    void Function(List<SyncDocument> documents) callback, {
    void Function(Object error)? onError,
  }) {
    final listenerId = ListenerEvents.newListenerId('query');

    // Subscribe BEFORE calling the native method, so no event is sent before Flutter listens.
    final stop = ListenerEvents.listen(
      'co.rivium.sync/query_events',
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
    _channel.invokeMethod('listenQuery', {
      ..._buildQueryParams(),
      'listenerId': listenerId,
    });

    return ListenerRegistration(() {
      stop();
      _channel.invokeMethod('removeQueryListener', {'listenerId': listenerId});
    });
  }
}
