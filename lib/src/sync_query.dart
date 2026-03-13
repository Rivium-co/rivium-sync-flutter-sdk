import 'dart:async';
import 'package:flutter/services.dart';
import 'sync_document.dart';
import 'sync_collection.dart';

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

  /// Execute the query and get results
  Future<List<SyncDocument>> get() async {
    final result = await _channel.invokeMethod<List<dynamic>>(
      'queryDocuments',
      _buildQueryParams(),
    );

    if (result == null) return [];

    return result.map((item) => SyncDocument.fromMap(item as Map)).toList();
  }

  /// Listen to query results in realtime
  ///
  /// [callback] is called whenever query results change
  /// [onError] is called when an error occurs (optional)
  ListenerRegistration listen(
    void Function(List<SyncDocument> documents) callback, {
    void Function(Object error)? onError,
  }) {
    // Create a unique listener ID
    final listenerId = 'query_${DateTime.now().millisecondsSinceEpoch}';

    // IMPORTANT: Set up event channel subscription BEFORE calling native method
    // This prevents race condition where native sends events before Flutter is listening
    final subscription = const EventChannel('co.rivium.sync/query_events')
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
    _channel.invokeMethod('listenQuery', {
      ..._buildQueryParams(),
      'listenerId': listenerId,
    });

    return ListenerRegistration(() {
      subscription.cancel();
      _channel.invokeMethod('removeQueryListener', {'listenerId': listenerId});
    });
  }
}
