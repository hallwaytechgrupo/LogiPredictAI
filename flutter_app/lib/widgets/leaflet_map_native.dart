/// Fallback para execução Flutter nativa e testes, com poucos elementos vetoriais.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class LeafletSurface extends StatelessWidget {
  const LeafletSurface(
      {super.key, required this.config, required this.blocked});
  final Map<String, dynamic> config;
  final bool blocked;
  @override
  Widget build(BuildContext context) {
    LatLng? point(dynamic p) =>
        p is Map && p['latitude'] is num && p['longitude'] is num
            ? LatLng((p['latitude'] as num).toDouble(),
                (p['longitude'] as num).toDouble())
            : null;
    final a = point(config['origin']), b = point(config['destination']);
    return IgnorePointer(
        ignoring: blocked,
        child: FlutterMap(
          options:
              const MapOptions(initialCenter: LatLng(-15, -51), initialZoom: 4),
          children: [
            TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'br.edu.fatec.logipredict'),
            if (a != null && b != null)
              PolylineLayer(polylines: [
                Polyline(points: [a, b], color: Colors.blue, strokeWidth: 3)
              ]),
            MarkerLayer(markers: [
              for (final p in [a, b])
                if (p != null)
                  Marker(
                      point: p,
                      child: const Icon(Icons.location_on, color: Colors.blue))
            ]),
            const RichAttributionWidget(attributions: [
              TextSourceAttribution('© OpenStreetMap contributors')
            ]),
          ],
        ));
  }
}
