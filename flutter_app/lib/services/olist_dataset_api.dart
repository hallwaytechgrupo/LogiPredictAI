/// Importação de dados Olist a partir do CSV processado.
///
/// [OlistDatasetApi] carrega o CSV de pedidos Olist preparado
/// a partir do endpoint GET /api/v1/datasets/olist.
library;

import 'package:http/http.dart' as http;

import 'logipredict_api.dart';

/// Cliente para carregar o CSV de pedidos Olist processados.
class OlistDatasetApi {
  OlistDatasetApi({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl =
            (baseUrl ?? LogiPredictApi.baseUrl).replaceFirst(RegExp(r'/$'), '');

  final http.Client _client;
  final String _baseUrl;

  Future<String> loadPreparedCsv() async {
    final response = await _client
        .get(Uri.parse('$_baseUrl/api/v1/datasets/olist'), headers: {
      'Accept': 'text/csv',
    }).timeout(const Duration(minutes: 2));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'Não foi possível carregar o CSV Olist: HTTP ${response.statusCode}.');
    }
    final content = response.body;
    if (content.trim().isEmpty) {
      throw const FormatException('O CSV Olist preparado está vazio.');
    }
    return content;
  }
}
