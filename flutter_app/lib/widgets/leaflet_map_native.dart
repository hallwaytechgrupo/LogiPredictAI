/// Mapa nativo de rotas, regiões e hubs, com o mesmo contrato do mapa Web.
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

const _regionCenters = {
  'Norte': LatLng(-5, -55),
  'Nordeste': LatLng(-8, -39),
  'Centro-Oeste': LatLng(-14, -50),
  'Sudeste': LatLng(-21, -45),
  'Sul': LatLng(-28, -52),
};
const _regionColors = {
  'Norte': Color(0xFF22C55E),
  'Nordeste': Color(0xFFEF4444),
  'Centro-Oeste': Color(0xFF3B82F6),
  'Sudeste': Color(0xFFF97316),
  'Sul': Color(0xFFA855F7),
};

class _RegionShape {
  const _RegionShape(this.name, this.outline, this.holes);
  final String name;
  final List<LatLng> outline;
  final List<List<LatLng>> holes;
}

Future<List<_RegionShape>> _readRegions(
    [Future<String> Function()? loader]) async {
  final document = jsonDecode(await (loader?.call() ??
      rootBundle.loadString('assets/geojson/brazil_regions.geojson'))) as Map;
  final shapes = <_RegionShape>[];
  List<LatLng> points(List ring) => [
        for (final p in ring)
          LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble())
      ];
  for (final feature in document['features'] as List) {
    final geometry = feature['geometry'] as Map;
    final coordinates = geometry['coordinates'] as List;
    final parts =
        geometry['type'] == 'MultiPolygon' ? coordinates : [coordinates];
    for (final rings in parts.cast<List>()) {
      if (rings.isEmpty) continue;
      shapes.add(_RegionShape(
          feature['properties']['name'] as String,
          points(rings.first as List),
          [for (final hole in rings.skip(1)) points(hole as List)]));
    }
  }
  return shapes;
}

class LeafletSurface extends StatefulWidget {
  const LeafletSurface(
      {super.key,
      required this.config,
      required this.blocked,
      this.geometryLoader});
  final Map<String, dynamic> config;
  final bool blocked;
  final Future<String> Function()? geometryLoader;
  @override
  State<LeafletSurface> createState() => _LeafletSurfaceState();
}

class _LeafletSurfaceState extends State<LeafletSurface> {
  static Future<List<_RegionShape>>? _cachedShapes;
  final _controller = MapController();
  final _tileProvider = NetworkTileProvider();
  List<_RegionShape> _shapes = [];
  bool _ready = false, _fitScheduled = false, _geometryUnavailable = false;
  bool get _history => widget.config['mode'] == 'history';

  static LatLng? _point(dynamic p) => p is Map &&
          p['latitude'] is num &&
          p['longitude'] is num
      ? LatLng(
          (p['latitude'] as num).toDouble(), (p['longitude'] as num).toDouble())
      : null;
  static Color _riskColor(dynamic risk) => switch (risk) {
        'Alto' => const Color(0xFFDC2626),
        'Médio' => const Color(0xFFD97706),
        'Baixo' => const Color(0xFF15803D),
        _ => const Color(0xFF2563EB),
      };

  List<LatLng> _roadPoints() {
    final route = widget.config['roadRoute'];
    final geometry = route is Map ? route['geometry'] : null;
    final coordinates = geometry is Map ? geometry['coordinates'] : null;
    if (geometry is! Map ||
        geometry['type'] != 'LineString' ||
        coordinates is! List) {
      return [];
    }
    final points = <LatLng>[];
    for (final p in coordinates) {
      if (p is! List ||
          p.length < 2 ||
          p[0] is! num ||
          p[1] is! num ||
          !(p[0] as num).isFinite ||
          !(p[1] as num).isFinite ||
          (p[0] as num).abs() > 180 ||
          (p[1] as num).abs() > 90) {
        return [];
      }
      points.add(LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()));
    }
    return points.length >= 2 ? points : [];
  }

  @override
  void initState() {
    super.initState();
    if (_history) _loadRegions();
  }

  Future<void> _loadRegions() async {
    try {
      final shapes = await (widget.geometryLoader != null
          ? _readRegions(widget.geometryLoader)
          : (_cachedShapes ??= _readRegions()));
      if (!mounted) return;
      setState(() => _shapes = shapes);
      _queueFit();
    } catch (error) {
      debugPrint('Não foi possível carregar os contornos do mapa: $error');
      _cachedShapes = null;
      if (mounted) setState(() => _geometryUnavailable = true);
    }
  }

  @override
  void didUpdateWidget(covariant LeafletSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_history && oldWidget.config['mode'] != 'history') _loadRegions();
    if (oldWidget.config['fitToken'] != widget.config['fitToken'] ||
        oldWidget.config['roadRoute'] != widget.config['roadRoute']) {
      _queueFit();
    }
  }

  void _queueFit() {
    if (_fitScheduled) return;
    _fitScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fitScheduled = false;
      if (mounted && _ready) _fit();
    });
  }

  void _fit() {
    final a = _point(widget.config['origin']),
        b = _point(widget.config['destination']);
    final focus = widget.config['focus'];
    if (a != null && b != null) {
      if ((a.latitude - b.latitude).abs() < .00001 &&
          (a.longitude - b.longitude).abs() < .00001) {
        _controller.move(a, 11);
      } else {
        _controller.fitCamera(CameraFit.bounds(
            bounds: LatLngBounds.fromPoints([a, b, ..._roadPoints()]),
            padding: const EdgeInsets.all(48),
            maxZoom: 11));
      }
    } else if (_history && _shapes.any((r) => r.name == focus)) {
      final outline = _shapes
          .where((r) => r.name == focus)
          .expand((r) => r.outline)
          .toList();
      _controller.fitCamera(CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(outline),
          padding: const EdgeInsets.all(30),
          maxZoom: 8));
    } else if (a != null || b != null) {
      _controller.move(a ?? b!, 10);
    } else {
      _controller.move(const LatLng(-15, -51), 3.3);
    }
  }

  void _details(String title, List<String> lines) {
    showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => SafeArea(
            child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 12),
                      for (final line in lines)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(line)),
                    ]))));
  }

  Marker _location(Map p, String label, Color color) => Marker(
      point: _point(p)!,
      width: 44,
      height: 44,
      child: Tooltip(
          message: label == 'O' ? 'Origem' : 'Destino',
          child: GestureDetector(
              onTap: () => _details(label == 'O' ? 'Origem' : 'Destino', [
                    '${p['city']} / ${p['state']}',
                    'Prefixo CEP: ${p['prefix5']}'
                  ]),
              child: Center(
                  child: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3)),
                      child: Text(label,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800)))))));

  List<Marker> _markers() {
    if (!_history) {
      final a = widget.config['origin'], b = widget.config['destination'];
      return [
        if (_point(a) != null)
          _location(a as Map, 'O', const Color(0xFF2563EB)),
        if (_point(b) != null)
          _location(b as Map, 'D', _riskColor(widget.config['risk'])),
      ];
    }
    return [
      for (final h in (widget.config['hubs'] as List? ?? []).cast<Map>())
        if (_point(h) != null)
          Marker(
              point: _point(h)!,
              width: 44,
              height: 44,
              child: GestureDetector(
                  onTap: () => _details(h['name'].toString(),
                      ['${h['city']} / ${h['state']}', h['code'].toString()]),
                  child: Center(
                      child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                              color: const Color(0xFF2563EB),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white, width: 1.5)))))),
      for (final r in (widget.config['regions'] as List? ?? []).cast<Map>())
        if (_regionCenters.containsKey(r['name']))
          Marker(
              point: _regionCenters[r['name']]!,
              width: 158,
              height: 44,
              child: Center(
                  child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(7),
                      child: InkWell(
                          borderRadius: BorderRadius.circular(7),
                          onTap: () =>
                              _details('${r['name']} — histórico Olist', [
                                '${r['total']} pedidos',
                                '${r['delayed']} atrasos em ${r['valid']} entregas avaliáveis',
                                if ((r['valid'] as num) > 0)
                                  'Taxa observada: ${(r['rate'] as num).toStringAsFixed(1)}%',
                                for (final s
                                    in (r['states'] as List).cast<Map>())
                                  '${s['state']}: ${(s['delayRate'] as num).toStringAsFixed(1)}% · ${s['totalOrders']} pedidos',
                              ]),
                          child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 8),
                              decoration: BoxDecoration(
                                  border: Border(
                                      left: BorderSide(
                                          color: _regionColors[r['name']]!,
                                          width: 4))),
                              child: Text(
                                  '${r['name']} · ${(r['valid'] as num) > 0 ? '${(r['rate'] as num).toStringAsFixed(1)}%' : 'Sem dados'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Color(0xFF334155),
                                      fontSize: 11))))))),
    ];
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roadPoints = _roadPoints();
    return IgnorePointer(
        ignoring: widget.blocked,
        child: Stack(children: [
          FlutterMap(
              mapController: _controller,
              options: MapOptions(
                  initialCenter: const LatLng(-15, -51),
                  initialZoom: 3.3,
                  minZoom: 3,
                  maxZoom: 18,
                  onMapReady: () {
                    _ready = true;
                    _queueFit();
                  }),
              children: [
                TileLayer(
                    tileProvider: _tileProvider,
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.hallwaytech.logipredict'),
                if (_history && _shapes.isNotEmpty)
                  PolygonLayer<Object>(polygons: [
                    for (final r in _shapes)
                      Polygon<Object>(
                          points: r.outline,
                          holePointsList: r.holes,
                          color: _regionColors[r.name]!.withValues(alpha: .15),
                          borderColor: const Color(0xFF64748B),
                          borderStrokeWidth: 1),
                  ]),
                if (!_history && roadPoints.length >= 2)
                  PolylineLayer(polylines: [
                    Polyline(
                        points: roadPoints,
                        color: _riskColor(widget.config['risk']),
                        strokeWidth: 4)
                  ]),
                MarkerLayer(markers: _markers()),
                RichAttributionWidget(attributions: [
                  const TextSourceAttribution('OpenStreetMap contributors'),
                  if (!_history && roadPoints.length >= 2)
                    const TextSourceAttribution(
                        'openrouteservice.org by HeiGIT'),
                ]),
              ]),
          Positioned(
              top: _history ? null : 10,
              right: _history ? null : 10,
              bottom: _history ? 10 : null,
              left: _history ? 10 : null,
              child: Card(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                    tooltip: 'Aumentar zoom',
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      if (_ready) {
                        _controller.move(_controller.camera.center,
                            (_controller.camera.zoom + 1).clamp(3, 18));
                      }
                    }),
                IconButton(
                    tooltip: 'Diminuir zoom',
                    icon: const Icon(Icons.remove),
                    onPressed: () {
                      if (_ready) {
                        _controller.move(_controller.camera.center,
                            (_controller.camera.zoom - 1).clamp(3, 18));
                      }
                    }),
                IconButton(
                    tooltip: 'Centralizar mapa',
                    icon: const Icon(Icons.center_focus_strong),
                    onPressed: () {
                      if (_ready) _fit();
                    }),
              ]))),
          if (_geometryUnavailable && _history)
            const Positioned(
                bottom: 32,
                left: 12,
                child: Text(
                    'Contornos indisponíveis. Os pontos continuam disponíveis.')),
        ]));
  }
}
