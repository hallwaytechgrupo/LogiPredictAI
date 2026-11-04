/// Serviço de comunicação com a API LogiPredictAI.
///
/// Fornece métodos estáticos para:
/// - Previsão de risco de atraso (POST /api/v1/predictions).
/// - Resolução de rota por CEP (POST /api/v1/geolocation/route).
/// - Análise histórica por UF (GET /api/v1/analytics/states).
///
/// A URL base pode ser configurada via argumento do compilador:
/// `--dart-define=API_BASE_URL=http://seu-servidor:3001`
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Cliente HTTP para a API LogiPredictAI.
///
/// Todos os métodos são estáticos e realizam chamadas HTTP diretamente
/// ao backend Node.js, que por sua vez encaminha as previsões ao serviço ML.
class LogiPredictApi {
  /// URL base do backend, configurável via dart-define.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:3001',
  );

  /// Constrói a URI do endpoint de previsão com order_id opcional.
  static Uri predictionUri({String? orderId}) =>
      Uri.parse('$baseUrl/api/v1/predictions').replace(
        queryParameters: orderId == null ? null : {'order_id': orderId},
      );

  /// Envia um pedido para previsão de risco de atraso.
  ///
  /// O backend encaminha os dados ao serviço ML FastAPI, que retorna
  /// a probabilidade de atraso e a classificação binária.
  ///
  /// Args:
  ///   shipment: Dados do pedido no formato esperado pelo modelo ML.
  ///   orderId: ID opcional do pedido para associação com o hub.
  ///
  /// Returns:
  ///   Mapa com delay_probability, predicted_late, threshold e warnings.
  ///
  /// Throws:
  ///   Exception se a API retornar erro HTTP ou resposta inválida.
  static Future<Map<String, dynamic>> predict(
    Map<String, dynamic> shipment, {
    String? orderId,
  }) async {
    final uri = predictionUri(orderId: orderId);

    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(shipment),
        )
        .timeout(const Duration(seconds: 30));

    final dynamic decoded;

    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw Exception(
        'A API retornou uma resposta que não é JSON válido '
        '(HTTP ${response.statusCode}).',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (decoded is Map<String, dynamic>) {
        final message =
            decoded['message'] ?? decoded['error'] ?? 'Erro desconhecido';
        throw Exception('Erro na previsão: $message '
            '(HTTP ${response.statusCode})');
      }

      throw Exception(
        'Erro na previsão: HTTP ${response.statusCode}',
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw Exception('Formato da resposta de previsão inválido.');
    }

    return decoded;
  }

  /// Calcula a distância e informações de rota entre CEPs de origem e destino.
  ///
  /// Usa o índice de geolocalização da Olist carregado pelo backend.
  ///
  /// Args:
  ///   originCeps: Lista de CEPs de origem (vendedores).
  ///   destinationCep: CEP de destino (cliente).
  ///
  /// Returns:
  ///   Mapa com distance_km, origin_coords e destination_coords.
  ///
  /// Throws:
  ///   Exception se a API retornar erro ou CEPs inválidos.
  static Future<Map<String, dynamic>> resolveRoute({
    required List<String> originCeps,
    required String destinationCep,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/geolocation/route');
    final http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'origin_ceps': originCeps,
              'destination_cep': destinationCep,
            }),
          )
          .timeout(const Duration(seconds: 30));
    } catch (error) {
      throw Exception('Não foi possível resolver os CEPs: $error');
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw Exception(
        'A API de localização retornou uma resposta inválida '
        '(HTTP ${response.statusCode}).',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map<String, dynamic>
          ? decoded['message'] ?? decoded['error'] ?? 'Erro desconhecido'
          : 'HTTP ${response.statusCode}';
      throw Exception(message.toString());
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['data'] is! Map<String, dynamic>) {
      throw Exception('Formato de resposta de localização inválido.');
    }
    return decoded['data'] as Map<String, dynamic>;
  }

  /// Retorna a taxa de atraso histórica observada por UF do cliente.
  ///
  /// Dados calculados durante o treino a partir dos registros reais da Olist.
  ///
  /// Returns:
  ///   Lista de mapas, cada um com customer_state, orders, late_orders e late_rate.
  ///
  /// Throws:
  ///   Exception se a API retornar erro ou formato inválido.
  static Future<List<Map<String, dynamic>>> fetchStateAnalytics() async {
    final uri = Uri.parse('$baseUrl/api/v1/analytics/states');

    final response = await http.get(uri).timeout(const Duration(seconds: 15));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Erro ao carregar analytics: HTTP ${response.statusCode}',
      );
    }

    final dynamic decoded = jsonDecode(response.body);

    if (decoded is! Map<String, dynamic> || decoded['states'] is! List) {
      throw Exception('Formato dos dados analíticos inválido.');
    }

    return (decoded['states'] as List)
        .whereType<Map<String, dynamic>>()
        .toList();
  }
}
