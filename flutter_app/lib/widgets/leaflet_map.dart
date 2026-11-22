/// Leaflet no navegador; o mapa nativo mantém a mesma entrada de dados.
library;

import 'package:flutter/material.dart';
import 'leaflet_map_native.dart'
    if (dart.library.js_interop) 'leaflet_map_web.dart' as surface;

class LeafletMap extends StatelessWidget {
  const LeafletMap({super.key, required this.config, this.blocked = false});
  final Map<String, dynamic> config;
  final bool blocked;

  @override
  Widget build(BuildContext context) =>
      surface.LeafletSurface(config: config, blocked: blocked);
}
