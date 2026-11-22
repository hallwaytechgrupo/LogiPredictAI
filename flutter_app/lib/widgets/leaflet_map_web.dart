/// Um iframe por mapa visível, sem enviar movimentos do mouse ao Flutter.
library;

import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class LeafletSurface extends StatefulWidget {
  const LeafletSurface(
      {super.key, required this.config, required this.blocked});
  final Map<String, dynamic> config;
  final bool blocked;
  @override
  State<LeafletSurface> createState() => _LeafletSurfaceState();
}

class _LeafletSurfaceState extends State<LeafletSurface> {
  static int _sequence = 0;
  late final String _channel = 'logipredict-${++_sequence}';
  web.HTMLIFrameElement? _frame;
  late final JSFunction _listener;
  bool _ready = false;
  String? _sent;

  @override
  void initState() {
    super.initState();
    _listener = ((web.MessageEvent event) {
      if (event.origin != web.window.location.origin ||
          event.source != _frame?.contentWindow ||
          event.data == null) {
        return;
      }
      final dynamic message;
      try {
        message = jsonDecode((event.data as JSString).toDart);
      } catch (_) {
        return;
      }
      if (message is Map &&
          message['channel'] == _channel &&
          message['type'] == 'ready') {
        _ready = true;
        _send();
      }
    }).toJS;
    web.window.addEventListener('message', _listener);
  }

  void _send() {
    _frame?.style.pointerEvents = widget.blocked ? 'none' : 'auto';
    if (!_ready) return;
    final encoded = jsonEncode(
        {'channel': _channel, 'type': 'update', 'config': widget.config});
    if (encoded == _sent) return;
    _sent = encoded;
    _frame?.contentWindow
        ?.postMessage(encoded.toJS, web.window.location.origin.toJS);
  }

  @override
  void didUpdateWidget(covariant LeafletSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _send();
  }

  @override
  void dispose() {
    web.window.removeEventListener('message', _listener);
    _frame?.src = 'about:blank';
    _frame?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
        tagName: 'iframe',
        onElementCreated: (element) {
          _frame = element as web.HTMLIFrameElement;
          _frame!
            ..title = 'Mapa Leaflet LogiPredict'
            ..src = Uri.base
                .resolve('maps/leaflet.html')
                .replace(queryParameters: {'channel': _channel}).toString()
            ..style.width = '100%'
            ..style.height = '100%'
            ..style.border = '0'
            ..style.display = 'block';
          _send();
        },
      );
}
