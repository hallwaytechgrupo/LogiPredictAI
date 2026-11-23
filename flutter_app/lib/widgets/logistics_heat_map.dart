/// Histórico observado em cinco regiões; Leaflet cuida das interações no Web.
library;

import 'package:flutter/material.dart';
import '../services/orders_region_api.dart';
import '../services/hubs_api.dart';
import 'leaflet_map.dart';

typedef RegionTapCallback = void Function(RegionOrderRecord record);
typedef HubTapCallback = void Function(LogisticHub hub);

class LogisticsHeatMap extends StatefulWidget {
  const LogisticsHeatMap(
      {super.key,
      required this.regionOrderData,
      required this.mapHubs,
      required this.showHubLayer,
      required this.loading,
      required this.error,
      required this.onRegionTap,
      required this.onHubTap,
      required this.onRefresh,
      required this.onToggleHubLayer,
      this.active = true});
  final List<RegionOrderRecord> regionOrderData;
  final List<LogisticHub> mapHubs;
  final bool showHubLayer, loading, active;
  final String? error;
  final RegionTapCallback onRegionTap;
  final HubTapCallback onHubTap;
  final VoidCallback onRefresh;
  final ValueChanged<bool> onToggleHubLayer;
  @override
  State<LogisticsHeatMap> createState() => _LogisticsHeatMapState();
}

class _LogisticsHeatMapState extends State<LogisticsHeatMap> {
  String? _focus;
  int _fit = 0;
  Color _color(double r) => r > 30
      ? const Color(0xFFB91C1C)
      : r > 20
          ? const Color(0xFFEA580C)
          : r > 10
              ? const Color(0xFFD97706)
              : const Color(0xFF15803D);

  Map<String, dynamic> get _config => {
        'mode': 'history',
        'fitToken': _fit,
        'focus': _focus,
        'regions': [
          for (final r in widget.regionOrderData)
            {
              'name': r.region,
              'total': r.totalOrders,
              'valid': r.ordersWithValidDates,
              'delayed': r.delayedOrders,
              'rate': r.delayRate,
              'states': [
                for (final s in r.states)
                  {
                    'state': s.state,
                    'totalOrders': s.totalOrders,
                    'delayRate': s.delayRate
                  }
              ],
            }
        ],
        'hubs': widget.showHubLayer
            ? [
                for (final h
                    in widget.mapHubs.where((h) => h.hasValidCoordinates))
                  {
                    'name': h.name,
                    'code': h.code,
                    'city': h.city,
                    'state': h.state,
                    'latitude': h.latitude,
                    'longitude': h.longitude,
                  }
              ]
            : [],
      };

  Widget _sidebar() => SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Histórico por região',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
              'Entregas reais da Olist. As taxas abaixo são atrasos observados, não previsões de novos pedidos.',
              style: TextStyle(color: Color(0xFF64748B), height: 1.5)),
          const SizedBox(height: 18),
          for (final r in widget.regionOrderData)
            Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: _focus == r.region
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surface,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Theme.of(context).dividerColor)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() {
                      _focus = r.region;
                      _fit++;
                    }),
                    child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Expanded(
                                    child: Text(r.region,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700))),
                                Text(
                                    r.ordersWithValidDates == 0
                                        ? 'Sem dados'
                                        : '${r.delayRate.toStringAsFixed(1)}%',
                                    style: TextStyle(
                                        color: _color(r.delayRate),
                                        fontWeight: FontWeight.w800,
                                        fontSize: 19))
                              ]),
                              const SizedBox(height: 4),
                              Text(
                                  '${r.delayedOrders} atrasos · ${r.ordersWithValidDates} entregas avaliáveis',
                                  style: const TextStyle(fontSize: 12)),
                            ])),
                  ),
                )),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Exibir hubs'),
              subtitle: Text(
                  '${widget.mapHubs.where((h) => h.hasValidCoordinates).length} locais com coordenadas'),
              value: widget.showHubLayer,
              onChanged: widget.onToggleHubLayer),
          const Divider(height: 28),
          const Text(
              'Clique no nome da região no mapa para consultar os estados. Os pontos azuis são hubs cadastrados.',
              style: TextStyle(
                  fontSize: 12, color: Color(0xFF64748B), height: 1.5)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
              onPressed: widget.loading ? null : widget.onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Atualizar histórico')),
        ],
      ));

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    Widget map;
    if (!widget.active) {
      map = const SizedBox.shrink();
    } else if (widget.loading) {
      map = const Center(child: CircularProgressIndicator());
    } else if (widget.error != null) {
      map = Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(widget.error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                    onPressed: widget.onRefresh,
                    child: const Text('Tentar novamente'))
              ])));
    } else {
      map = LeafletMap(key: const ValueKey('history-leaflet'), config: _config);
    }
    return LayoutBuilder(
        builder: (context, c) => c.maxWidth >= 850
            ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(
                    width: 310,
                    child: ColoredBox(
                        color: surface,
                        child: Material(
                            color: Colors.transparent, child: _sidebar()))),
                const VerticalDivider(width: 1),
                Expanded(child: map)
              ])
            : SingleChildScrollView(
                child: Column(children: [
                SizedBox(height: 370, child: map),
                _sidebar()
              ])));
  }
}
