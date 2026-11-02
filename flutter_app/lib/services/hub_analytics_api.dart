/// Análise de risco por hub logístico.
///
/// Fornece:
/// - [HubRiskAggregate]: agregação de previsões por hub (contagem, risco, limiares).
/// - [HubAnalyticsFilters]: filtros de período e hub.
/// - [HubAnalyticsResponse]: resposta completa da API de analytics.
/// - [HubAnalyticsApi]: cliente HTTP para GET /api/v1/analytics/hubs.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Agregação de previsões de risco para um hub específico.
///
/// Contém contagem de previsões, taxa de risco, limiares usados,
/// versões do modelo e período coberto.
class HubRiskAggregate {
  const HubRiskAggregate({
    required this.hubId,
    required this.predictionsCount,
    required this.riskCount,
    required this.riskPercentage,
    required this.periodStart,
    required this.periodEnd,
    required this.threshold,
    required this.thresholds,
    required this.thresholdsConsistent,
    required this.modelVersion,
    required this.modelVersions,
    required this.modelVersionsConsistent,
    required this.lastPredictionAt,
  });

  final String hubId;
  final int predictionsCount;
  final int riskCount;
  final double riskPercentage;
  final String? periodStart;
  final String? periodEnd;
  final double? threshold;
  final List<double> thresholds;
  final bool thresholdsConsistent;
  final String? modelVersion;
  final List<String> modelVersions;
  final bool modelVersionsConsistent;
  final String? lastPredictionAt;

  factory HubRiskAggregate.fromJson(Map<String, dynamic> json) {
    double? number(dynamic value) =>
        value is num && value.isFinite ? value.toDouble() : null;
    List<double> numbers(dynamic value) => value is List
        ? value.map(number).whereType<double>().toList(growable: false)
        : const [];
    List<String> strings(dynamic value) => value is List
        ? value.whereType<String>().toList(growable: false)
        : const [];

    final id = json['hub_id'];
    final predictions = json['predictions_count'];
    final risks = json['risk_count'];
    final percentage = number(json['risk_percentage']);
    if (id is! String ||
        id.isEmpty ||
        predictions is! int ||
        predictions <= 0 ||
        risks is! int ||
        risks < 0 ||
        risks > predictions ||
        percentage == null ||
        percentage < 0 ||
        percentage > 100) {
      throw const FormatException('Agregado de risco de hub inválido.');
    }

    return HubRiskAggregate(
      hubId: id,
      predictionsCount: predictions,
      riskCount: risks,
      riskPercentage: percentage,
      periodStart: json['period_start'] as String?,
      periodEnd: json['period_end'] as String?,
      threshold: number(json['threshold']),
      thresholds: numbers(json['thresholds']),
      thresholdsConsistent: json['thresholds_consistent'] == true,
      modelVersion: json['model_version'] as String?,
      modelVersions: strings(json['model_versions']),
      modelVersionsConsistent: json['model_versions_consistent'] == true,
      lastPredictionAt: json['last_prediction_at'] as String?,
    );
  }
}

/// Filtros aplicáveis à consulta de analytics por hub.
class HubAnalyticsFilters {
  const HubAnalyticsFilters({this.startDate, this.endDate, this.hubId});

  final String? startDate;
  final String? endDate;
  final String? hubId;

  factory HubAnalyticsFilters.fromJson(Map<String, dynamic> json) =>
      HubAnalyticsFilters(
        startDate: json['start_date'] as String?,
        endDate: json['end_date'] as String?,
        hubId: json['hub_id'] as String?,
      );
}

/// Resposta completa da API de analytics por hub.
///
/// Contém a lista de agregados, total de hubs e filtros aplicados.
class HubAnalyticsResponse {
  const HubAnalyticsResponse({
    required this.data,
    required this.total,
    required this.filters,
  });

  final List<HubRiskAggregate> data;
  final int total;
  final HubAnalyticsFilters filters;

  factory HubAnalyticsResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    final total = json['total'];
    final filters = json['filters'];
    if (data is! List || total is! int || filters is! Map<String, dynamic>) {
      throw const FormatException('Resposta de analytics de hubs inválida.');
    }
    return HubAnalyticsResponse(
      data: data
          .map((item) =>
              HubRiskAggregate.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(growable: false),
      total: total,
      filters: HubAnalyticsFilters.fromJson(filters),
    );
  }
}

/// Cria um índice de agregados de risco por hub_id para consulta rápida.
Map<String, HubRiskAggregate> indexHubRiskAggregates(
        Iterable<HubRiskAggregate> aggregates) =>
    {for (final aggregate in aggregates) aggregate.hubId: aggregate};

/// Cliente HTTP para análise de risco por hub logístico.
///
/// Consulta GET /api/v1/analytics/hubs e retorna [HubAnalyticsResponse].
class HubAnalyticsApi {
  static const String _defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:3001',
  );

  HubAnalyticsApi({
    http.Client? client,
    String? baseUrl,
    Duration timeout = const Duration(seconds: 15),
  })  : _client = client ?? http.Client(),
        _timeout = timeout,
        _baseUrl = (baseUrl ??
                const String.fromEnvironment(
                  'LOGIPREDICT_API_URL',
                  defaultValue: _defaultBaseUrl,
                ))
            .replaceFirst(RegExp(r'/$'), '');

  final http.Client _client;
  final Duration _timeout;
  final String _baseUrl;

  Future<HubAnalyticsResponse> list() async {
    final response = await _client
        .get(Uri.parse('$_baseUrl/api/v1/analytics/hubs'), headers: {
      'Accept': 'application/json',
    }).timeout(_timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'Erro ao carregar risco por hub: HTTP ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Resposta de analytics de hubs inválida.');
    }
    return HubAnalyticsResponse.fromJson(decoded);
  }
}
