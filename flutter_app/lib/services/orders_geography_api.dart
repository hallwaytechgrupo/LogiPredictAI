/// Análise geográfica de pedidos por cidade e UF.
///
/// Fornece:
/// - [OrderRiskBand]: enum com as faixas de risco de atraso.
/// - [OrderGeographyRecord]: registro com estatísticas por cidade.
/// - [OrdersGeographyApi]: cliente HTTP para GET /api/v1/analytics/orders-geography.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Faixas de risco de atraso com base na taxa observada.
enum OrderRiskBand { semDados, baixo, medio, alto, muitoAlto }

/// Converte a string de risco do backend para o enum [OrderRiskBand].
OrderRiskBand orderRiskBand(String riskLevel) {
  switch (riskLevel) {
    case 'sem_dados':
      return OrderRiskBand.semDados;
    case 'baixo':
      return OrderRiskBand.baixo;
    case 'medio':
      return OrderRiskBand.medio;
    case 'alto':
      return OrderRiskBand.alto;
    case 'muito_alto':
      return OrderRiskBand.muitoAlto;
    default:
      return OrderRiskBand.semDados;
  }
}

class OrderGeographyRecord {
  const OrderGeographyRecord({
    required this.city,
    required this.state,
    required this.totalOrders,
    required this.ordersWithValidDates,
    required this.delayedOrders,
    required this.ordersWithoutDeliveryDate,
    required this.delayRate,
    required this.riskLevel,
    required this.latitude,
    required this.longitude,
  });

  final String city;
  final String state;
  final int totalOrders;
  final int ordersWithValidDates;
  final int delayedOrders;
  final int ordersWithoutDeliveryDate;
  final double delayRate;
  final String riskLevel;
  final double latitude;
  final double longitude;

  OrderRiskBand get riskBand => orderRiskBand(riskLevel);

  factory OrderGeographyRecord.fromJson(Map<String, dynamic> json) {
    final city = json['city'];
    final state = json['state'];
    final totalOrders = json['total_orders'];
    final ordersWithValidDates = json['orders_with_valid_dates'];
    final delayedOrders = json['delayed_orders'];
    final ordersWithoutDeliveryDate = json['orders_without_delivery_date'];
    final delayRate = json['delay_rate'];
    final riskLevel = json['risk_level'];
    final latitude = json['latitude'];
    final longitude = json['longitude'];

    if (city is! String ||
        city.isEmpty ||
        state is! String ||
        state.isEmpty ||
        totalOrders is! int ||
        totalOrders <= 0 ||
        ordersWithValidDates is! int ||
        ordersWithValidDates < 0 ||
        delayedOrders is! int ||
        delayedOrders < 0 ||
        delayedOrders > totalOrders ||
        ordersWithoutDeliveryDate is! int ||
        ordersWithoutDeliveryDate < 0 ||
        delayRate is! num ||
        delayRate < 0 ||
        delayRate > 100 ||
        riskLevel is! String ||
        riskLevel.isEmpty ||
        latitude is! num ||
        latitude < -90 ||
        latitude > 90 ||
        longitude is! num ||
        longitude < -180 ||
        longitude > 180) {
      throw const FormatException('Registro de geografia de pedidos inválido.');
    }

    return OrderGeographyRecord(
      city: city,
      state: state,
      totalOrders: totalOrders,
      ordersWithValidDates: ordersWithValidDates,
      delayedOrders: delayedOrders,
      ordersWithoutDeliveryDate: ordersWithoutDeliveryDate,
      delayRate: delayRate.toDouble(),
      riskLevel: riskLevel,
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
    );
  }
}

class OrdersGeographyFilters {
  const OrdersGeographyFilters({this.state});

  final String? state;

  factory OrdersGeographyFilters.fromJson(Map<String, dynamic> json) =>
      OrdersGeographyFilters(state: json['state'] as String?);
}

class OrdersGeographyResponse {
  const OrdersGeographyResponse({
    required this.data,
    required this.total,
    required this.filters,
  });

  final List<OrderGeographyRecord> data;
  final int total;
  final OrdersGeographyFilters filters;

  factory OrdersGeographyResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    final total = json['total'];
    final filters = json['filters'];
    if (data is! List || total is! int || filters is! Map<String, dynamic>) {
      throw const FormatException(
          'Resposta de geografia de pedidos inválida.');
    }
    return OrdersGeographyResponse(
      data: data
          .map((item) => OrderGeographyRecord.fromJson(
              Map<String, dynamic>.from(item as Map)))
          .toList(growable: false),
      total: total,
      filters: OrdersGeographyFilters.fromJson(filters),
    );
  }
}

class OrdersGeographyApi {
  static const String _defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:3001',
  );

  OrdersGeographyApi({
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

  Future<OrdersGeographyResponse> list({String? state}) async {
    final uri = Uri.parse('$_baseUrl/api/v1/analytics/orders-geography')
        .replace(queryParameters: {
      if (state != null && state.isNotEmpty) 'state': state,
    });
    final response = await _client.get(uri, headers: {
      'Accept': 'application/json',
    }).timeout(_timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'Erro ao carregar geografia de pedidos: HTTP ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
          'Resposta de geografia de pedidos inválida.');
    }
    return OrdersGeographyResponse.fromJson(decoded);
  }
}
