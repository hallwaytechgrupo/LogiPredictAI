/// Agregação geográfica de pedidos por região brasileira.
///
/// Agrupa os dados por UF e mapeia para as 5 regiões oficiais:
/// Norte, Nordeste, Centro-Oeste, Sudeste e Sul.
///
/// [RegionStateRecord]: estatísticas de uma UF dentro de uma região.
/// [RegionOrderRecord]: agregação de uma região com suas UFs.
/// [OrdersRegionApi]: cliente HTTP para GET /api/v1/analytics/orders-geography/regions.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'orders_geography_api.dart';

/// Estatísticas de pedidos de uma UF dentro de uma região.
class RegionStateRecord {
  const RegionStateRecord({
    required this.state,
    required this.totalOrders,
    required this.ordersWithValidDates,
    required this.delayedOrders,
    required this.ordersWithoutDeliveryDate,
    required this.delayRate,
    required this.riskLevel,
  });

  final String state;
  final int totalOrders;
  final int ordersWithValidDates;
  final int delayedOrders;
  final int ordersWithoutDeliveryDate;
  final double delayRate;
  final String riskLevel;

  OrderRiskBand get riskBand => orderRiskBand(riskLevel);

  factory RegionStateRecord.fromJson(Map<String, dynamic> json) {
    return RegionStateRecord(
      state: (json['state'] as String).toUpperCase(),
      totalOrders: json['total_orders'] as int,
      ordersWithValidDates: json['orders_with_valid_dates'] as int,
      delayedOrders: json['delayed_orders'] as int,
      ordersWithoutDeliveryDate: json['orders_without_delivery_date'] as int,
      delayRate: (json['delay_rate'] as num).toDouble(),
      riskLevel: json['risk_level'] as String,
    );
  }
}

class RegionOrderRecord {
  const RegionOrderRecord({
    required this.region,
    required this.totalOrders,
    required this.ordersWithValidDates,
    required this.delayedOrders,
    required this.ordersWithoutDeliveryDate,
    required this.delayRate,
    required this.riskLevel,
    required this.states,
  });

  final String region;
  final int totalOrders;
  final int ordersWithValidDates;
  final int delayedOrders;
  final int ordersWithoutDeliveryDate;
  final double delayRate;
  final String riskLevel;
  final List<RegionStateRecord> states;

  OrderRiskBand get riskBand => orderRiskBand(riskLevel);

  factory RegionOrderRecord.fromJson(Map<String, dynamic> json) {
    final statesJson = json['states'] as List;
    return RegionOrderRecord(
      region: json['region'] as String,
      totalOrders: json['total_orders'] as int,
      ordersWithValidDates: json['orders_with_valid_dates'] as int,
      delayedOrders: json['delayed_orders'] as int,
      ordersWithoutDeliveryDate: json['orders_without_delivery_date'] as int,
      delayRate: (json['delay_rate'] as num).toDouble(),
      riskLevel: json['risk_level'] as String,
      states: statesJson
          .map((e) => RegionStateRecord.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false),
    );
  }
}

class OrdersRegionApi {
  static const String _defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:3001',
  );

  OrdersRegionApi({
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

  Future<List<RegionOrderRecord>> list() async {
    final uri = Uri.parse('$_baseUrl/api/v1/analytics/orders-geography/regions');
    final response = await _client.get(uri, headers: {
      'Accept': 'application/json',
    }).timeout(_timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'Erro ao carregar regiões: HTTP ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Resposta de regiões inválida.');
    }
    final data = decoded['data'] as List;
    return data
        .map((item) => RegionOrderRecord.fromJson(
            Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }
}
