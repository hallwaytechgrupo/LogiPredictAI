import 'dart:convert';

import 'package:http/http.dart' as http;

class LogiPredictApi {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:3001',
  );

  static Future<Map<String, dynamic>> predict(
    Map<String, dynamic> shipment,
  ) async {
    final uri = Uri.parse('$baseUrl/api/v1/predictions');

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
