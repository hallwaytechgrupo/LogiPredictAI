/// Gerenciamento de pedidos no backend.
///
/// Fornece:
/// - Importação de pedidos em lote com associação a hubs.
/// - Consulta individual de pedido.
/// - Atualização do hub associado a um pedido.
/// - Alocação automática de hubs por estado do cliente.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'logipredict_api.dart';

/// Exceção personalizada para erros da API de pedidos.
class OrdersApiException implements Exception {
  const OrdersApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Cliente HTTP para operações com pedidos.
///
/// Suporta injeção de [http.Client] para testes.
class OrdersApi {
  static const int importBatchLimit = 2000;

  OrdersApi({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl =
            (baseUrl ?? LogiPredictApi.baseUrl).replaceFirst(RegExp(r'/$'), '');

  final http.Client _client;
  final String _baseUrl;

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    final headers = {
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
    };
    late final http.Response response;
    try {
      if (method == 'POST') {
        response = await _client
            .post(uri, headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 20));
      } else if (method == 'PATCH') {
        response = await _client
            .patch(uri, headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 20));
      } else {
        response = await _client
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 15));
      }
    } catch (error) {
      throw OrdersApiException(
          'Não foi possível acessar a API de pedidos: $error');
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw OrdersApiException(
        'A API de pedidos retornou uma resposta inválida (HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map<String, dynamic>
          ? decoded['message'] ?? decoded['error'] ?? 'Erro desconhecido'
          : 'HTTP ${response.statusCode}';
      throw OrdersApiException(message.toString(),
          statusCode: response.statusCode);
    }
    if (decoded is! Map<String, dynamic>) {
      throw const OrdersApiException(
          'Formato de resposta da API de pedidos inválido.');
    }
    return decoded;
  }

  Future<List<Map<String, dynamic>>> importOrders(
    List<String> orderIds, {
    String? defaultHubId,
    String? source,
  }) async {
    final response = await _request(
      'POST',
      '/api/v1/orders/import',
      body: {
        'orders': orderIds.map((id) => {'order_id': id}).toList(),
        if (defaultHubId != null) 'default_hub_id': defaultHubId,
        if (source != null) 'source': source,
      },
    );
    final data = response['data'];
    if (data is! List) {
      throw const OrdersApiException(
          'A resposta da importação não contém pedidos.');
    }
    return data.whereType<Map<String, dynamic>>().toList();
  }

  Future<Map<String, dynamic>> getOrder(String orderId) async {
    final response = await _request(
      'GET',
      '/api/v1/orders/${Uri.encodeComponent(orderId)}',
    );
    final data = response['data'];
    if (data is! Map<String, dynamic>) {
      throw const OrdersApiException('A resposta não contém o pedido.');
    }
    return data;
  }

  Future<Map<String, dynamic>> setHub(String orderId, String? hubId) async {
    final response = await _request(
      'PATCH',
      '/api/v1/orders/${Uri.encodeComponent(orderId)}/hub',
      body: {'hub_id': hubId},
    );
    final data = response['data'];
    if (data is! Map<String, dynamic>) {
      throw const OrdersApiException(
          'A resposta não contém o vínculo atualizado.');
    }
    return data;
  }

  /// Distributes orders across hubs based on the destination state.
  /// When [dryRun] is true, no data is modified — only a preview is returned.
  Future<Map<String, dynamic>> assignHubsByState(
    List<Map<String, dynamic>> orders, {
    bool dryRun = true,
  }) async {
    final response = await _request(
      'POST',
      '/api/v1/orders/assign-hubs-by-state',
      body: {
        'dry_run': dryRun,
        'orders': orders,
      },
    );
    return response;
  }
}
