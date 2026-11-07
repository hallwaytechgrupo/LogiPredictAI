/// Simulação de despacho entre hubs.
///
/// Fornece:
/// - Simulação automática de despacho entre dois CEPs.
/// - Seleção automática dos hubs mais próximos.
/// - Cálculo de rota via OpenRouteService.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'logipredict_api.dart';

/// Exceção personalizada para erros da API de despacho.
class DispatchApiException implements Exception {
  const DispatchApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Cliente HTTP para simulação de despacho.
class DispatchApi {
  DispatchApi({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl =
            (baseUrl ?? LogiPredictApi.baseUrl).replaceFirst(RegExp(r'/$'), '');

  final http.Client _client;
  final String _baseUrl;

  /// Simula despacho entre dois CEPs.
  ///
  /// [originCep] é o CEP de origem (formato 00000-000).
  /// [destinationCep] é o CEP de destino (formato 00000-000).
  /// Retorna os hubs selecionados automaticamente, distâncias e rota.
  Future<Map<String, dynamic>> simulate(
    String originCep,
    String destinationCep,
  ) async {
    final uri = Uri.parse('$_baseUrl/api/v1/dispatch/simulate');
    final headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    final body = jsonEncode({
      'origin_cep': originCep,
      'destination_cep': destinationCep,
    });

    late final http.Response response;
    try {
      response = await _client
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 30));
    } catch (error) {
      throw DispatchApiException(
          'Não foi possível acessar a API de despacho: $error');
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw DispatchApiException(
        'A API de despacho retornou uma resposta inválida (HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map<String, dynamic>
          ? decoded['message'] ?? decoded['error'] ?? 'Erro desconhecido'
          : 'HTTP ${response.statusCode}';
      throw DispatchApiException(message.toString(),
          statusCode: response.statusCode);
    }
    if (decoded is! Map<String, dynamic>) {
      throw const DispatchApiException(
          'Formato de resposta da API de despacho inválido.');
    }
    return decoded;
  }

  /// Encontra o hub mais próximo de um CEP.
  ///
  /// [cep] é o CEP no formato 00000-000.
  /// Retorna o hub mais próximo com informações de distância.
  Future<Map<String, dynamic>> nearestHub({required String cep}) async {
    final uri = Uri.parse('$_baseUrl/api/v1/geolocation/nearest-hub');
    final headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    final body = jsonEncode({'cep': cep});

    late final http.Response response;
    try {
      response = await _client
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 15));
    } catch (error) {
      throw DispatchApiException(
          'Não foi possível acessar a API de geolocalização: $error');
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw DispatchApiException(
        'A API de geolocalização retornou uma resposta inválida (HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map<String, dynamic>
          ? decoded['message'] ?? decoded['error'] ?? 'Erro desconhecido'
          : 'HTTP ${response.statusCode}';
      throw DispatchApiException(message.toString(),
          statusCode: response.statusCode);
    }
    if (decoded is! Map<String, dynamic>) {
      throw const DispatchApiException(
          'Formato de resposta da API de geolocalização inválido.');
    }
    return decoded;
  }
}
