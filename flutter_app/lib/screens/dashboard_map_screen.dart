part of 'dashboard_screen.dart';

extension _DashboardMapScreen on _DashboardScreenState {
  Map<String, RegionOrderRecord> get _regionMap {
    final map = <String, RegionOrderRecord>{};
    for (final r in _regionOrderData) {
      map[r.region] = r;
    }
    return map;
  }

  // Approximate centroids for region labels
  static const Map<String, LatLng> _regionCentroids = {
    'Norte': LatLng(-5, -55),
    'Nordeste': LatLng(-8, -39),
    'Centro-Oeste': LatLng(-14, -50),
    'Sudeste': LatLng(-21, -45),
    'Sul': LatLng(-28, -52),
  };

  List<Marker> _buildRegionLabels(Map<String, RegionOrderRecord> regionMap) {
    return _regionCentroids.entries.map((entry) {
      final name = entry.key;
      final center = entry.value;
      final record = regionMap[name];
      final band = record?.riskBand ?? OrderRiskBand.semDados;
      final riskColor = orderRiskColor(band);
      final riskLabel = orderRiskShortLabel(band);
      final regionColor = REGION_FIXED_COLORS[name] ?? const Color(0xFF6B7280);

      // Build percentage text from real delay rate
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
                // Region name
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
                // Risk badge
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
                // Delay rate percentage
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

  Widget _buildMapPage() {
    Widget mapContent;
    if (_loadingRegions) {
      mapContent = const Center(child: CircularProgressIndicator());
    } else if (_regionError != null) {
      mapContent = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 38),
              const SizedBox(height: 10),
              Text(_regionError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _loadRegions(),
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    } else if (_regionOrderData.isEmpty) {
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
      // Build hub markers once, outside the hover-sensitive builder
      final hubMarkers = <Marker>[];
      if (_showHubLayer) {
        for (final hub in _mapHubs.where((h) => h.hasValidCoordinates)) {
          if (hub.latitude != null && hub.longitude != null) {
            hubMarkers.add(
              Marker(
                point: LatLng(hub.latitude!, hub.longitude!),
                width: 36,
                height: 36,
                child: GestureDetector(
                  onTap: () {
                    if (mounted) _showHubDetails(hub);
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
      // Build region labels once, outside the hover-sensitive builder
      final regionLabels = _buildRegionLabels(regionMap);

      // Keep FlutterMap stable — do NOT wrap it in ListenableBuilder.
      // Wrapping FlutterMap in a builder that rebuilds on hover triggers
      // MouseTracker assertions on Flutter Desktop because MouseRegion
      // widgets are destroyed/recreated while pointer events are active.
      mapContent = FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: const LatLng(-14.4, -51),
          initialZoom: 4,
          maxZoom: 6,
          onTap: (_, __) {
            final result = _regionHitNotifier.value;
            if (result != null) {
              for (final hitValue in result.hitValues) {
                final record = regionMap[hitValue];
                if (record != null && mounted) {
                  _showRegionDetails(record);
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
              // Use fixed region color for fill and border
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
          // Hub markers — single MarkerLayer, stable across hover events
          if (hubMarkers.isNotEmpty)
            MarkerLayer(markers: hubMarkers),
          // Region name labels at centroid positions
          MarkerLayer(markers: regionLabels),
          const RichAttributionWidget(
            attributions: [
              TextSourceAttribution('© OpenStreetMap contributors'),
              TextSourceAttribution(
                'Regiões: IBGE (Malha Territorial)',
              ),
            ],
          ),
        ],
      );

      // Fit camera to Brazil bounds
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _mapController.move(const LatLng(-14.4, -51), 4);
      });
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: _card(
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
                // Hub layer visibility toggle
                Tooltip(
                  message: 'Mostrar hubs logísticos',
                  child: Switch(
                    value: _showHubLayer,
                    onChanged: _loadingRegions
                        ? null
                        : (value) => setState(() => _showHubLayer = value),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Atualizar dados',
                  onPressed: _loadingRegions
                      ? null
                      : () => _loadRegions(),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Region legend — fixed colors for geographic identity
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
                        color: REGION_FIXED_COLORS[name] ?? const Color(0xFF6B7280),
                        label: name,
                      ))
                  .toList(),
            ),
            const SizedBox(height: 8),
            // Risk badge legend — for the small badges on labels
            const Text(
              'Risco (badge):',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _RiskLegendItem(band: OrderRiskBand.baixo, label: 'Baixo (0–10%)'),
                _RiskLegendItem(band: OrderRiskBand.medio, label: 'Médio (>10–20%)'),
                _RiskLegendItem(band: OrderRiskBand.alto, label: 'Alto (>20–30%)'),
                _RiskLegendItem(band: OrderRiskBand.muitoAlto, label: 'Muito alto (>30%)'),
                _RiskLegendItem(band: OrderRiskBand.semDados, label: 'Sem dados'),
              ],
            ),
            const SizedBox(height: 8),
            // Hub layer legend
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.local_shipping, size: 16, color: Color(0xFF1565C0)),
                const SizedBox(width: 5),
                const Text(
                  'Hubs logísticos (simulados)',
                  style: TextStyle(fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              height: 470,
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _border),
              ),
              child: mapContent,
            ),
            const SizedBox(height: 10),
          ],
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
