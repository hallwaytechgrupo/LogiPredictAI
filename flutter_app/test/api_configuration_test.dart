import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logipredict_ai/services/api_configuration.dart';
import 'package:logipredict_ai/services/hubs_api.dart';
import 'package:logipredict_ai/services/logipredict_api.dart';
import 'package:logipredict_ai/services/map_scenarios_api.dart';
import 'package:logipredict_ai/services/orders_api.dart';
import 'package:logipredict_ai/services/orders_region_api.dart';
import 'package:logipredict_ai/services/server_connection.dart';

class MemoryPreferences implements SharedPreferencesAsync {
  final Map<String, String> _values = {};
  String? get value => _values['logipredict.server_url'];
  @override
  Future<String?> getString(String key) async => _values[key];
  @override
  Future<void> setString(String key, String value) async =>
      _values[key] = value;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryPreferences preferences;
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    preferences = MemoryPreferences();
    await ApiConfiguration.initialize(storage: preferences);
  });
  tearDown(() async {
    await ApiConfiguration.initialize(storage: MemoryPreferences());
    debugDefaultTargetPlatformOverride = null;
  });

  test('normaliza os enderecos de USB, Wi-Fi e servidor com prefixo', () {
    expect(ApiConfiguration.normalize(' 192.168.0.31:3001/ '),
        'http://192.168.0.31:3001');
    expect(ApiConfiguration.normalize('https://servidor.example/logi/'),
        'https://servidor.example/logi');
    expect(ApiConfiguration.normalize(ApiConfiguration.defaultUrl),
        ApiConfiguration.defaultUrl);
    for (final value in [
      '',
      'ftp://servidor',
      'http://bad host:3001',
      'http://user:password@servidor',
      'http://servidor?token=1',
      'http://servidor#parte',
      'http://servidor:0',
      'http://servidor:70000'
    ]) {
      expect(() => ApiConfiguration.normalize(value), throwsFormatException,
          reason: value);
    }
  });

  test('endereco Android persiste e e carregado na proxima inicializacao',
      () async {
    await ApiConfiguration.save('192.168.0.31:3015/');
    expect(preferences.value, 'http://192.168.0.31:3015');
    await ApiConfiguration.initialize(storage: preferences);
    expect(ApiConfiguration.baseUrl, preferences.value);
    expect(ApiConfiguration.legacyBaseUrl(), preferences.value);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await ApiConfiguration.initialize(storage: preferences);
    expect(ApiConfiguration.canConfigure, isFalse);
    expect(ApiConfiguration.baseUrl, ApiConfiguration.defaultUrl);
  });

  test('todos os clientes usam o servidor Android salvo', () async {
    await ApiConfiguration.save('http://192.168.0.31:3015');
    final seen = <String>[];
    final client = MockClient((request) async {
      expect(request.url.host, '192.168.0.31');
      expect(request.url.port, 3015);
      seen.add(request.url.path);
      return http.Response(
          jsonEncode({'data': [], 'total': 0, 'page': 1, 'total_pages': 1}),
          200);
    });
    await OrdersApi(client: client).listOrders();
    await HubsApi(client: client).list();
    await OrdersRegionApi(client: client).list();
    await MapScenariosApi(client: client).get('locations', {'q': '01001'});
    expect(LogiPredictApi.predictionUri().host, '192.168.0.31');
    expect(
        seen,
        containsAll([
          '/api/v1/orders',
          '/api/v1/hubs',
          '/api/v1/analytics/orders-geography/regions',
          '/api/v1/map/locations'
        ]));
  });

  test('conexao distingue servidor valido de previsao indisponivel', () async {
    var readyCode = 503;
    final client = MockClient((request) async => request.url.path == '/health'
        ? http.Response('{"status":"ok","service":"logipredict-api"}', 200)
        : http.Response('{"status":"ok"}', readyCode));
    expect(
        (await ServerConnection.check('http://servidor', client: client))
            .predictionReady,
        isFalse);
    readyCode = 200;
    expect(
        (await ServerConnection.check('http://servidor', client: client))
            .predictionReady,
        isTrue);
    final wrongServer =
        MockClient((_) async => http.Response('{"status":"ok"}', 200));
    await expectLater(
        ServerConnection.check('http://servidor', client: wrongServer),
        throwsFormatException);
  });
}
