/// Pesquisa e simulação no mapa com os artefatos preservados do modelo 564.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'logipredict_api.dart';

class MapScenariosApi {
  MapScenariosApi({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? LogiPredictApi.baseUrl;

  final http.Client _client;
  final String _baseUrl;

  void close() => _client.close();

  Future<Map<String, dynamic>> get(String resource,
          [Map<String, String> query = const {}]) =>
      _request(resource, query: query);

  Future<Map<String, dynamic>> simulate(Map<String, dynamic> shipment) =>
      _request('simulate', body: shipment);

  Future<Map<String, dynamic>> _request(String resource,
      {Map<String, String> query = const {},
      Map<String, dynamic>? body}) async {
    final uri = Uri.parse('$_baseUrl/api/v1/map/$resource')
        .replace(queryParameters: query.isEmpty ? null : query);
    final http.Response response;
    try {
      response = await (body == null
              ? _client.get(uri)
              : _client.post(uri,
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode(body)))
          .timeout(const Duration(seconds: 40));
    } catch (_) {
      throw Exception(
          'Não foi possível consultar o mapa. Confira os serviços Node e Python.');
    }
    final dynamic data;
    try {
      data = jsonDecode(response.body);
    } catch (_) {
      throw Exception('O serviço do mapa retornou uma resposta inválida.');
    }
    if (data is! Map<String, dynamic>) {
      throw Exception('Formato de resposta do mapa inválido.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final details = data['details'];
      final fields = details is List
          ? details.map((e) => e is Map ? e['message'] : e).join(' ')
          : '';
      throw Exception(
          '${data['message'] ?? data['detail'] ?? 'Falha no mapa'} $fields'
              .trim());
    }
    if (resource == 'catalog' &&
        (data['start_date'] is! String ||
            data['end_date'] is! String ||
            data['states'] is! List ||
            data['regions'] is! List ||
            data['risk_definitions'] is! Map ||
            data['limitations'] is! List ||
            data['metrics'] is! Map)) {
      throw Exception(
          'O serviço do mapa retornou um catálogo incompleto. Atualize o backend e tente novamente.');
    }
    return data;
  }
}
