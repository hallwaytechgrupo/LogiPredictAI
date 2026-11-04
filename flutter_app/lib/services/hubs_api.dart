/// Gerenciamento de hubs logísticos.
///
/// Fornece:
/// - Modelo [LogisticHub] com dados completos do hub (coordenadas, cobertura, OSM).
/// - Cliente [HubsApi] para CRUD completo via REST.
/// - Suporte a importação em lote, aprovação em massa e análise de cobertura.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;

/// Representa um hub logístico no sistema.
///
/// Contém informações de localização, cobertura (UFs atendidas),
/// status de validação e metadados do OpenStreetMap (quando disponível).
class LogisticHub {
  const LogisticHub({
    required this.id,
    required this.code,
    required this.name,
    required this.city,
    required this.state,
    required this.status,
    this.createdAt,
    this.updatedAt,
    this.validationStatus = 'APROVADO',
    this.osmId,
    this.latitude,
    this.longitude,
    this.provisionalCategory,
    this.osmTags,
    this.operatorName,
    this.owner,
    this.brand,
    this.osmUrl,
    this.classification,
    this.justification,
    this.statesServed,
  });

  final String id;
  final String code;
  final String name;
  final String city;
  final String state;
  final String status;
  final String? createdAt;
  final String? updatedAt;
  final String validationStatus;
  final String? osmId;
  final double? latitude;
  final double? longitude;
  final String? provisionalCategory;
  final String? osmTags;
  final String? operatorName;
  final String? owner;
  final String? brand;
  final String? osmUrl;
  final String? classification;
  final String? justification;
  final List<String>? statesServed;

  /// Returns effective coverage: explicit statesServed or fallback to hub.state.
  List<String> get effectiveStatesServed {
    if (statesServed != null && statesServed!.isNotEmpty) {
      return statesServed!;
    }
    return state.isNotEmpty ? [state] : [];
  }

  /// True if the hub has no explicit statesServed configured.
  bool get hasPendingCoverage => statesServed == null || statesServed!.isEmpty;

  bool get isActive => status == 'active';
  String get label => '$name — $city/$state';
  bool get hasValidCoordinates =>
      latitude != null &&
      longitude != null &&
      latitude!.isFinite &&
      longitude!.isFinite &&
      latitude! >= -90 &&
      latitude! <= 90 &&
      longitude! >= -180 &&
      longitude! <= 180;

  factory LogisticHub.fromJson(Map<String, dynamic> json) {
    double? coordinate(dynamic value) {
      final parsed = value is num
          ? value.toDouble()
          : value is String
              ? double.tryParse(value)
              : null;
      return parsed != null && parsed.isFinite ? parsed : null;
    }

    List<String>? parseStatesServed(dynamic value) {
      if (value == null) return null;
      if (value is List<dynamic>) {
        final list = value.whereType<String>().map((e) => e.trim().toUpperCase()).toList();
        return list.isNotEmpty ? list : null;
      }
      return null;
    }

    return LogisticHub(
      id: json['id'] as String,
      code: json['code'] as String,
      name: json['name'] as String,
      city: json['city'] as String,
      state: json['state'] as String,
      status: json['status'] as String,
      createdAt: json['createdAt'] as String?,
      updatedAt: json['updatedAt'] as String?,
      validationStatus: json['validationStatus'] as String? ?? 'APROVADO',
      osmId: json['osmId'] as String?,
      latitude: coordinate(json['latitude']),
      longitude: coordinate(json['longitude']),
      provisionalCategory: json['provisionalCategory'] as String?,
      osmTags: json['osmTags'] as String?,
      operatorName: json['operator'] as String?,
      owner: json['owner'] as String?,
      brand: json['brand'] as String?,
      osmUrl: json['osmUrl'] as String?,
      classification: json['classification'] as String?,
      justification: json['justification'] as String?,
      statesServed: parseStatesServed(json['statesServed']),
    );
  }
}

/// Exceção personalizada para erros da API de hubs.
class HubsApiException implements Exception {
  HubsApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

/// Cliente HTTP para o CRUD de hubs logísticos.
///
/// Suporta injeção de [http.Client] para testes.
/// URL base configurável via dart-define: LOGIPREDICT_API_URL.
class HubsApi {
  static const String _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3001',
  );

  HubsApi({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = (baseUrl ??
                const String.fromEnvironment(
                  'LOGIPREDICT_API_URL',
                  defaultValue: _apiBaseUrl,
                ))
            .replaceFirst(RegExp(r'/$'), '');

  final http.Client _client;
  final String _baseUrl;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$_baseUrl$path').replace(queryParameters: query);

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final uri = _uri(path, query);
    final headers = {
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json'
    };
    late http.Response response;
    try {
      switch (method) {
        case 'GET':
          response = await _client.get(uri, headers: headers);
          break;
        case 'POST':
          response =
              await _client.post(uri, headers: headers, body: jsonEncode(body));
          break;
        case 'PUT':
          response =
              await _client.put(uri, headers: headers, body: jsonEncode(body));
          break;
        case 'PATCH':
          response = await _client.patch(uri,
              headers: headers, body: jsonEncode(body));
          break;
        case 'DELETE':
          response = await _client.delete(uri,
              headers: headers, body: body == null ? null : jsonEncode(body));
          break;
        default:
          throw HubsApiException('Método HTTP não suportado.');
      }
    } catch (_) {
      throw HubsApiException(
          'Não foi possível conectar à API de hubs. Verifique se o serviço está ativo.');
    }
    if (response.statusCode == 204) return <String, dynamic>{};
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw HubsApiException('A API retornou uma resposta inválida.',
          statusCode: response.statusCode);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final details = payload['details'];
      final message = payload['message'] ??
          (details is List && details.isNotEmpty
              ? details.first['message']
              : null) ??
          payload['error'] ??
          'Falha na API.';
      throw HubsApiException(message.toString(),
          statusCode: response.statusCode);
    }
    return payload;
  }

  Future<List<LogisticHub>> list(
      {bool includeInactive = false,
      String? query,
      String? validationStatus}) async {
    final params = <String, String>{
      'status': includeInactive ? 'all' : 'active'
    };
    if (query != null && query.trim().isNotEmpty) params['q'] = query.trim();
    if (validationStatus != null && validationStatus != 'all') {
      params['validationStatus'] = validationStatus;
    }
    final payload = await _request('GET', '/api/v1/hubs', query: params);
    return (payload['data'] as List<dynamic>)
        .map((item) => LogisticHub.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, int>> importCandidates(
      List<Map<String, dynamic>> candidates) async {
    final payload = await _request('POST', '/api/v1/hubs/import',
        body: {'candidates': candidates});
    return {
      'added': payload['added'] as int? ?? 0,
      'updated': payload['updated'] as int? ?? 0,
      'unchanged': payload['unchanged'] as int? ?? 0,
      'total': payload['total'] as int? ?? candidates.length,
    };
  }

  Future<Map<String, int>> approveMany(List<String> ids) async {
    final payload = await _request(
      'PATCH',
      '/api/v1/hubs/bulk/validation',
      body: {'ids': ids},
    );
    return {
      'added': payload['added'] as int? ?? 0,
      'skipped': payload['skipped'] as int? ?? 0,
      'total': payload['total'] as int? ?? ids.length,
    };
  }

  Future<int> deleteMany(List<String> ids) async {
    final payload =
        await _request('DELETE', '/api/v1/hubs/bulk', body: {'ids': ids});
    return payload['deleted'] as int? ?? 0;
  }

  Future<LogisticHub> create(
      {required String code,
      required String name,
      required String city,
      required String state,
      List<String>? statesServed}) async {
    final body = <String, dynamic>{
      'code': code,
      'name': name,
      'city': city,
      'state': state,
    };
    if (statesServed != null && statesServed.isNotEmpty) {
      body['statesServed'] = statesServed;
    }
    final payload = await _request('POST', '/api/v1/hubs', body: body);
    return LogisticHub.fromJson(payload['data'] as Map<String, dynamic>);
  }

  Future<LogisticHub> update(LogisticHub hub,
      {required String code,
      required String name,
      required String city,
      required String state,
      List<String>? statesServed}) async {
    final body = <String, dynamic>{
      'code': code,
      'name': name,
      'city': city,
      'state': state,
    };
    if (statesServed != null) {
      body['statesServed'] = statesServed;
    }
    final payload = await _request('PUT', '/api/v1/hubs/${hub.id}', body: body);
    return LogisticHub.fromJson(payload['data'] as Map<String, dynamic>);
  }

  Future<LogisticHub> updateStatesServed(
    LogisticHub hub,
    List<String>? statesServed,
  ) async {
    final body = <String, dynamic>{'statesServed': statesServed};
    final payload = await _request(
      'PATCH',
      '/api/v1/hubs/${hub.id}/states-served',
      body: body,
    );
    return LogisticHub.fromJson(payload['data'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> getCoverage() async {
    return await _request('GET', '/api/v1/hubs/coverage');
  }

  Future<LogisticHub> setActive(LogisticHub hub, bool active) async {
    final payload = await _request('PATCH', '/api/v1/hubs/${hub.id}/status',
        body: {'active': active});
    return LogisticHub.fromJson(payload['data'] as Map<String, dynamic>);
  }

  Future<LogisticHub> setValidationStatus(
    LogisticHub hub,
    String validationStatus,
  ) async {
    final payload = await _request(
      'PATCH',
      '/api/v1/hubs/${hub.id}/validation',
      body: {'validationStatus': validationStatus},
    );
    return LogisticHub.fromJson(payload['data'] as Map<String, dynamic>);
  }

  Future<void> delete(String id) async {
    await _request('DELETE', '/api/v1/hubs/$id');
  }
}
