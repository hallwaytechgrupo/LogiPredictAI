/// Widgets e utilitários para camada de risco no mapa.
///
/// Fornece:
/// - [HubRiskBand]: enum com as faixas de risco por hub.
/// - Cores e rótulos para risco de pedidos e de hubs.
/// - [HubRiskLayerUnavailable]: toggle para ativar/desativar a camada de risco.
/// - Cores fixas por região brasileira para identificação geográfica.
library;

import 'package:flutter/material.dart';

import '../services/hub_analytics_api.dart';
import '../services/orders_geography_api.dart';

/// Faixas de risco de atraso por hub, baseadas na porcentagem de previsões com risco.
enum HubRiskBand { noRisk, low, elevated, allRisk, unavailable }

/* ---- Order geography risk helpers ---- */

/* ---- Fixed region colors (geographic identity, independent of risk) ---- */

const Map<String, Color> REGION_FIXED_COLORS = {
  'Norte': Color(0xFF2E7D32),       // Green
  'Nordeste': Color(0xFFC62828),    // Red
  'Centro-Oeste': Color(0xFF1565C0), // Blue
  'Sudeste': Color(0xFFEF6C00),     // Orange
  'Sul': Color(0xFF6A1B9A),         // Purple
};

String regionFixedLabel(String region) => switch (region) {
      'Norte' => 'Norte',
      'Nordeste' => 'Nordeste',
      'Centro-Oeste' => 'Centro-Oeste',
      'Sudeste' => 'Sudeste',
      'Sul' => 'Sul',
      _ => region,
    };

/* ---- Order geography risk helpers (for badges/text, NOT for region fill) ---- */

Color orderRiskColor(OrderRiskBand band) => switch (band) {
      OrderRiskBand.semDados => const Color(0xFF6B7280),
      OrderRiskBand.baixo => const Color(0xFF15803D),
      OrderRiskBand.medio => const Color(0xFFCA8A04),
      OrderRiskBand.alto => const Color(0xFFEA580C),
      OrderRiskBand.muitoAlto => const Color(0xFFB91C1C),
    };

String orderRiskLabel(OrderRiskBand band) => switch (band) {
      OrderRiskBand.semDados => 'Sem dados: sem pedidos com datas válidas',
      OrderRiskBand.baixo => 'Baixo: taxa de atraso de 0% a 10%',
      OrderRiskBand.medio => 'Médio: taxa de atraso acima de 10% até 20%',
      OrderRiskBand.alto => 'Alto: taxa de atraso acima de 20% até 30%',
      OrderRiskBand.muitoAlto => 'Muito alto: taxa de atraso acima de 30%',
    };

/* Short risk label for badges */
String orderRiskShortLabel(OrderRiskBand band) => switch (band) {
      OrderRiskBand.semDados => 'Sem dados',
      OrderRiskBand.baixo => 'Baixo',
      OrderRiskBand.medio => 'Médio',
      OrderRiskBand.alto => 'Alto',
      OrderRiskBand.muitoAlto => 'Muito alto',
    };

HubRiskBand hubRiskBand(double? percentage) {
  if (percentage == null ||
      !percentage.isFinite ||
      percentage < 0 ||
      percentage > 100) {
    return HubRiskBand.unavailable;
  }
  if (percentage == 0) return HubRiskBand.noRisk;
  if (percentage < 50) return HubRiskBand.low;
  if (percentage < 100) return HubRiskBand.elevated;
  return HubRiskBand.allRisk;
}

Color hubRiskColor(HubRiskBand band) => switch (band) {
      HubRiskBand.noRisk => const Color(0xFF15803D),
      HubRiskBand.low => const Color(0xFFCA8A04),
      HubRiskBand.elevated => const Color(0xFFEA580C),
      HubRiskBand.allRisk => const Color(0xFFB91C1C),
      HubRiskBand.unavailable => const Color(0xFF2563EB),
    };

String hubRiskLabel(HubRiskBand band) => switch (band) {
      HubRiskBand.noRisk => '0%: nenhuma previsão classificada como risco',
      HubRiskBand.low =>
        'Acima de 0% e abaixo de 50%: baixo percentual agregado',
      HubRiskBand.elevated =>
        'De 50% a menos de 100%: percentual agregado intermediário/alto',
      HubRiskBand.allRisk =>
        '100%: todas as previsões classificadas como risco',
      HubRiskBand.unavailable => 'Sem previsões associadas',
    };

class HubRiskLayerUnavailable extends StatelessWidget {
  const HubRiskLayerUnavailable({
    super.key,
    required this.enabled,
    required this.onChanged,
    required this.loading,
    required this.total,
    this.error,
  });

  final bool enabled;
  final ValueChanged<bool> onChanged;
  final bool loading;
  final int total;
  final String? error;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile.adaptive(
            key: const ValueKey('risk-layer-toggle'),
            contentPadding: EdgeInsets.zero,
            value: enabled,
            onChanged: loading ? null : onChanged,
            title: const Text('Camada de risco experimental'),
            subtitle: Text(loading
                ? 'Carregando agregados de previsões…'
                : error == null
                    ? 'Agregação de previsões individuais reais por hub.'
                    : 'Não foi possível carregar os agregados. Os hubs continuam disponíveis.'),
          ),
          if (loading) const LinearProgressIndicator(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (!loading && error == null && total == 0)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                  'Nenhuma previsão elegível associada a hubs foi retornada pela API.'),
            ),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: HubRiskBand.values
                .map((band) => _LegendItem(
                      color: hubRiskColor(band),
                      label: hubRiskLabel(band),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          Text(
            'As faixas descrevem o percentual observado no conjunto de previsões; não são novos thresholds do modelo nem uma previsão geográfica do hub. Resultado experimental.',
            style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      );
}

class HubRiskDetails extends StatelessWidget {
  const HubRiskDetails({super.key, required this.aggregate});

  final HubRiskAggregate? aggregate;

  String _date(String? value) {
    if (value == null) return 'indisponível';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    return '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final data = aggregate;
    if (data == null) {
      return const Text('Sem previsões associadas a este hub.');
    }
    final threshold = data.thresholdsConsistent && data.threshold != null
        ? data.threshold!.toString()
        : data.thresholds.isEmpty
            ? 'indisponível'
            : 'variável (${data.thresholds.join(', ')})';
    final model = data.modelVersionsConsistent && data.modelVersion != null
        ? data.modelVersion!
        : data.modelVersions.isEmpty
            ? 'indisponível'
            : 'variável (${data.modelVersions.join(', ')})';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Previsões analisadas: ${data.predictionsCount}'),
        Text('Classificadas como risco: ${data.riskCount}'),
        Text('Percentual agregado: ${data.riskPercentage.toStringAsFixed(1)}%'),
        Text(
            'Faixa descritiva: ${hubRiskLabel(hubRiskBand(data.riskPercentage))}'),
        Text('Período: ${_date(data.periodStart)} a ${_date(data.periodEnd)}'),
        Text('Threshold retornado: $threshold'),
        Text('Versão do modelo: $model'),
        const SizedBox(height: 8),
        const Text(
            'Agregação experimental de previsões individuais; não representa um modelo de risco geográfico do hub.'),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 14, color: color),
          const SizedBox(width: 5),
          SizedBox(
              width: 190,
              child: Text(label, style: const TextStyle(fontSize: 11))),
        ],
      );
}
