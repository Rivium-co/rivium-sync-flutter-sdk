import 'dart:async';

import 'package:flutter/services.dart';

/// Delivers realtime events to listeners.
///
/// Flutter keeps one active stream per [EventChannel], so every listener of a
/// kind (collection, document or query) shares one subscription to its
/// channel. The native side tags each event with the listener's id and this
/// hub hands it to that listener. The subscription opens with the first
/// listener and closes with the last one.
class ListenerEvents {
  ListenerEvents._();

  static final Map<String, _ChannelHub> _hubs = {};
  static int _counter = 0;

  /// A listener id that is unique within this app run.
  static String newListenerId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_counter++}';

  /// Routes the events of [channelName] tagged with [listenerId] to [onData].
  /// Call the returned function to stop.
  static void Function() listen(
    String channelName,
    String listenerId,
    void Function(Map<dynamic, dynamic> data) onData,
    void Function(Object error)? onError,
  ) {
    final hub = _hubs.putIfAbsent(channelName, () => _ChannelHub(channelName));
    hub.add(listenerId, onData, onError);
    return () {
      hub.remove(listenerId);
      if (hub.isEmpty) _hubs.remove(channelName);
    };
  }

  /// Number of channels with an open subscription (for tests).
  static int get openChannelCount => _hubs.length;
}

class _Listener {
  _Listener(this.onData, this.onError);
  final void Function(Map<dynamic, dynamic> data) onData;
  final void Function(Object error)? onError;
}

class _ChannelHub {
  _ChannelHub(String name) : _channel = EventChannel(name);

  final EventChannel _channel;
  final Map<String, _Listener> _listeners = {};
  StreamSubscription<dynamic>? _subscription;

  bool get isEmpty => _listeners.isEmpty;

  void add(
    String listenerId,
    void Function(Map<dynamic, dynamic> data) onData,
    void Function(Object error)? onError,
  ) {
    _listeners[listenerId] = _Listener(onData, onError);
    _subscription ??= _channel.receiveBroadcastStream().listen(
      _dispatch,
      onError: (Object error) {
        // A channel-level error has no listener id: tell every listener.
        for (final l in List.of(_listeners.values)) {
          l.onError?.call(error);
        }
      },
    );
  }

  void remove(String listenerId) {
    _listeners.remove(listenerId);
    if (_listeners.isEmpty) {
      _subscription?.cancel();
      _subscription = null;
    }
  }

  void _dispatch(dynamic data) {
    if (data is! Map) return;
    final id = data['listenerId'];
    if (id is! String) return;
    _listeners[id]?.onData(data);
  }
}
