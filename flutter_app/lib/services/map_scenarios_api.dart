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

  Future<Map<String, dynamic>> forecast(Map<String, dynamic> shipment) =>
      _request('forecast', body: shipment);

  Future<Map<String, dynamic>> roadRoute(
      Map<String, dynamic> origin, Map<String, dynamic> destination) async {
    final response = await _request('route', body: {
      'origin': {
        'latitude': origin['latitude'],
        'longitude': origin['longitude']
      },
      'destination': {
        'latitude': destination['latitude'],
        'longitude': destination['longitude']
      },
    });
    final data = response['data'];
    final geometry = data is Map ? data['geometry'] : null;
    final coordinates = geometry is Map ? geometry['coordinates'] : null;
    bool coordinate(dynamic p) =>
        p is List &&
        p.length >= 2 &&
        p[0] is num &&
        (p[0] as num).isFinite &&
        (p[0] as num).abs() <= 180 &&
        p[1] is num &&
        (p[1] as num).isFinite &&
        (p[1] as num).abs() <= 90;
    if (data is! Map<String, dynamic> ||
        geometry is! Map ||
        geometry['type'] != 'LineString' ||
        coordinates is! List ||
        coordinates.length < 2 ||
        !coordinates.every(coordinate) ||
        data['distance_km'] is! num ||
        !(data['distance_km'] as num).isFinite ||
        (data['distance_km'] as num) < 0 ||
        data['duration_seconds'] is! num ||
        !(data['duration_seconds'] as num).isFinite ||
        (data['duration_seconds'] as num) < 0) {
      throw Exception('O serviço retornou um trajeto rodoviário inválido.');
    }
    return data;
  }

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
    if (resource == 'forecast' &&
        (data['result'] is! Map ||
            data['shipment'] is! Map ||
            data['calendar'] is! Map ||
            data['origin'] is! Map ||
            data['destination'] is! Map ||
            data['alternatives'] is! List ||
            data['suggestions'] is! List ||
            data['warnings'] is! List)) {
      throw Exception(
          'O serviço retornou uma análise incompleta. Tente calcular novamente.');
    }
    return data;
  }
}
