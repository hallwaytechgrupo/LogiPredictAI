/// Standalone widget for the logistics heat map.
///
/// Extracted from [_DashboardScreenState] so that the FlutterMap is NOT
/// recreated on every dashboard `setState`. This prevents the expensive
/// hit-testing and pointer-event processing cascade that freezes the app
/// when the user changes the browser zoom (Ctrl + scroll).
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_geojson2/flutter_map_geojson2.dart';
import 'package:latlong2/latlong.dart';
import '../services/orders_region_api.dart';
import '../services/orders_geography_api.dart';
import '../services/hubs_api.dart';
import '../widgets/hub_risk_layer_unavailable.dart';

/// Callback invoked when the user taps a region polygon.
typedef RegionTapCallback = void Function(RegionOrderRecord record);

/// Callback invoked when the user taps a hub marker.
typedef HubTapCallback = void Function(LogisticHub hub);

class LogisticsHeatMap extends StatefulWidget {
  const LogisticsHeatMap({
    super.key,
    required this.regionOrderData,
    required this.mapHubs,
    required this.showHubLayer,
    required this.loading,
    required this.error,
    required this.onRegionTap,
    required this.onHubTap,
    required this.onRefresh,
    required this.onToggleHubLayer,
  });

  final List<RegionOrderRecord> regionOrderData;
  final List<LogisticHub> mapHubs;
  final bool showHubLayer;
  final bool loading;
  final String? error;
  final RegionTapCallback onRegionTap;
  final HubTapCallback onHubTap;
  final VoidCallback onRefresh;
  final ValueChanged<bool> onToggleHubLayer;

  @override
  State<LogisticsHeatMap> createState() => _LogisticsHeatMapState();
}

class _LogisticsHeatMapState extends State<LogisticsHeatMap> {
  final MapController _mapController = MapController();
  final LayerHitNotifier<String> _regionHitNotifier =
      LayerHitNotifier<String>(null);

  // Approximate centroids for region labels
  static const Map<String, LatLng> _regionCentroids = {
    'Norte': LatLng(-5, -55),
    'Nordeste': LatLng(-8, -39),
    'Centro-Oeste': LatLng(-14, -50),
    'Sudeste': LatLng(-21, -45),
    'Sul': LatLng(-28, -52),
  };

  @override
  void dispose() {
    _mapController.dispose();
    _regionHitNotifier.dispose();
    super.dispose();
  }

  Map<String, RegionOrderRecord> get _regionMap {
    final map = <String, RegionOrderRecord>{};
    for (final r in widget.regionOrderData) {
      map[r.region] = r;
    }
    return map;
  }

  List<Marker> _buildRegionLabels(Map<String, RegionOrderRecord> regionMap) {
    return _regionCentroids.entries.map((entry) {
      final name = entry.key;
      final center = entry.value;
      final record = regionMap[name];
      final band = record?.riskBand ?? OrderRiskBand.semDados;
      final riskColor = orderRiskColor(band);
      final riskLabel = orderRiskShortLabel(band);
      final regionColor =
          REGION_FIXED_COLORS[name] ?? const Color(0xFF6B7280);

      final percentText = record != null && record.ordersWithValidDates > 0
          ? '${record.delayRate.toStringAsFixed(1)}%'
          : 'Sem dados';

      return Marker(
        point: center,
        width: 220,
        height: 40,
        child: Align(
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: regionColor.withValues(alpha: 0.6),
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF212121),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: riskColor.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    riskLabel,
                    style: const TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '($percentText)',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF555555),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0F172A);
    const blue = Color(0xFF2563EB);
    const muted = Color(0xFF64748B);
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget mapContent;
    if (widget.loading) {
      mapContent = const Center(child: CircularProgressIndicator());
    } else if (widget.error != null) {
      mapContent = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 38),
              const SizedBox(height: 10),
              Text(widget.error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: widget.onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    } else if (widget.regionOrderData.isEmpty) {
      mapContent = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_off_outlined, size: 38),
              const SizedBox(height: 10),
              const Text(
                'Nenhum dado de regiões disponível.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    } else {
      final regionMap = _regionMap;

      // Build hub markers
      final hubMarkers = <Marker>[];
      if (widget.showHubLayer) {
        for (final hub
            in widget.mapHubs.where((h) => h.hasValidCoordinates)) {
          if (hub.latitude != null && hub.longitude != null) {
            hubMarkers.add(
              Marker(
                point: LatLng(hub.latitude!, hub.longitude!),
                width: 36,
                height: 36,
                child: GestureDetector(
                  onTap: () {
                    widget.onHubTap(hub);
                  },
                  child: Icon(
                    Icons.local_shipping,
                    size: 28,
                    color: hub.isActive
                        ? const Color(0xFF1565C0)
                        : muted,
                  ),
                ),
              ),
            );
          }
        }
      }

      // Build region labels
      final regionLabels = _buildRegionLabels(regionMap);

      mapContent = FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: const LatLng(-14.4, -51),
          initialZoom: 4,
          minZoom: 3,
          maxZoom: 16,
          onTap: (_, __) {
            final result = _regionHitNotifier.value;
            if (result != null) {
              for (final hitValue in result.hitValues) {
                final record = regionMap[hitValue];
                if (record != null) {
                  widget.onRegionTap(record);
                  break;
                }
              }
            }
          },
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.logipredict_ai',
          ),
          GeoJsonLayer.asset(
            'assets/geojson/brazil_regions.geojson',
            hitNotifier: _regionHitNotifier,
            onPolygon: (points, holes, props) {
              final name = props['name'] as String?;
              final regionColor = name != null
                  ? REGION_FIXED_COLORS[name]?.withValues(alpha: 0.35)
                  : const Color(0xFF6B7280).withValues(alpha: 0.35);
              final borderColor = name != null
                  ? REGION_FIXED_COLORS[name] ?? const Color(0xFF6B7280)
                  : const Color(0xFF6B7280);
              return Polygon<String>(
                points: points,
                holePointsList: holes,
                color: regionColor,
                borderColor: borderColor,
                borderStrokeWidth: 2.5,
                hitValue: name,
              );
            },
          ),
          // Hub markers — always render MarkerLayer even if empty,
          // so the layer is stable across rebuilds
          MarkerLayer(markers: hubMarkers),
          MarkerLayer(markers: regionLabels),
          const RichAttributionWidget(
            attributions: [
              TextSourceAttribution('© OpenStreetMap contributors'),
              TextSourceAttribution('Regiões: IBGE (Malha Territorial)'),
            ],
          ),
        ],
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: _buildCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mapa de Retenção e Gargalos Logísticos',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Visualização de manchas de risco por região, destacando a concentração de pedidos e atrasos identificados no dataset Olist.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Tooltip(
                  message: 'Mostrar hubs logísticos',
                  child: Switch(
                    value: widget.showHubLayer,
                    onChanged: widget.loading
                        ? null
                        : (value) => widget.onToggleHubLayer(value),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Atualizar dados',
                  onPressed: widget.loading ? null : widget.onRefresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Regiões:',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: _regionCentroids.keys
                  .map((name) => _GeographyLegendItem(
                        color:
                            REGION_FIXED_COLORS[name] ?? const Color(0xFF6B7280),
                        label: name,
                      ))
                  .toList(),
            ),
            const SizedBox(height: 8),
            const Text(
              'Risco (badge):',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _RiskLegendItem(
                    band: OrderRiskBand.baixo, label: 'Baixo (0–10%)'),
                _RiskLegendItem(
                    band: OrderRiskBand.medio, label: 'Médio (>10–20%)'),
                _RiskLegendItem(
                    band: OrderRiskBand.alto, label: 'Alto (>20–30%)'),
                _RiskLegendItem(
                    band: OrderRiskBand.muitoAlto, label: 'Muito alto (>30%)'),
                _RiskLegendItem(band: OrderRiskBand.semDados, label: 'Sem dados'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.local_shipping, size: 16,
                    color: isDark ? colors.primary : const Color(0xFF1565C0)),
                const SizedBox(width: 5),
                Text(
                  'Hubs logísticos: ${widget.mapHubs.where((h) => h.hasValidCoordinates).length} com coordenadas',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              height: 470,
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: isDark
                    ? colors.surfaceContainerLow
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: isDark
                        ? colors.outlineVariant
                        : const Color(0xFFE2E8F0)),
              ),
              child: mapContent,
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? colors.surface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isDark ? colors.outlineVariant : const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: colors.onSurface),
        child: IconTheme.merge(
          data: IconThemeData(color: colors.onSurfaceVariant),
          child: child,
        ),
      ),
    );
  }
}

class _GeographyLegendItem extends StatelessWidget {
  const _GeographyLegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 14, color: color),
          const SizedBox(width: 5),
          SizedBox(
              width: 220,
              child: Text(label, style: const TextStyle(fontSize: 11))),
        ],
      );
}

class _RiskLegendItem extends StatelessWidget {
  const _RiskLegendItem({required this.band, required this.label});

  final OrderRiskBand band;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 14, color: orderRiskColor(band)),
          const SizedBox(width: 5),
          SizedBox(
              width: 160,
              child: Text(label, style: const TextStyle(fontSize: 11))),
        ],
      );
}
