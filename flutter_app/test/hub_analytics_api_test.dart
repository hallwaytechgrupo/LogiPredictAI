import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logipredict_ai/services/hub_analytics_api.dart';

Map<String, dynamic> _aggregate(String hubId, double percentage) => {
      'hub_id': hubId,
      'predictions_count': 2,
      'risk_count': percentage == 0 ? 0 : 1,
      'risk_percentage': percentage,
      'period_start': '2026-10-01T00:00:00.000Z',
      'period_end': '2026-10-31T23:59:59.999Z',
      'threshold': 0.37,
      'thresholds': [0.37],
      'thresholds_consistent': true,
      'model_version': 'rf-real-version',
      'model_versions': ['rf-real-version'],
      'model_versions_consistent': true,
      'last_prediction_at': '2026-10-31T10:00:00.000Z',
    };

void main() {
  test('parses the analytics response and retains filters and model metadata',
      () {
    final parsed = HubAnalyticsResponse.fromJson({
      'data': [_aggregate('hub-a', 50)],
      'total': 24,
      'filters': {'start_date': null, 'end_date': null, 'hub_id': null},
    });
    expect(parsed.total, 24);
    expect(parsed.filters.hubId, isNull);
    expect(parsed.data.single.riskPercentage, 50);
    expect(parsed.data.single.thresholdsConsistent, isTrue);
    expect(parsed.data.single.modelVersion, 'rf-real-version');
  });

  test('indexes metrics exclusively by hub_id', () {
    final parsed = HubAnalyticsResponse.fromJson({
      'data': [_aggregate('stable-id-1', 0), _aggregate('stable-id-2', 100)],
      'total': 2,
      'filters': {'start_date': null, 'end_date': null, 'hub_id': null},
    });
    final indexed = indexHubRiskAggregates(parsed.data);
    expect(indexed.keys, containsAll(['stable-id-1', 'stable-id-2']));
    expect(indexed['stable-id-1']!.riskPercentage, 0);
    expect(indexed['stable-id-2']!.riskPercentage, 100);
    expect(indexed.containsKey('Hub name'), isFalse);
  });

  test('accepts an empty response', () {
    final parsed = HubAnalyticsResponse.fromJson({
      'data': [],
      'total': 0,
      'filters': {'start_date': null, 'end_date': null, 'hub_id': null},
    });
    expect(parsed.data, isEmpty);
    expect(parsed.total, 0);
  });

  test('calls the configured endpoint and reports HTTP errors', () async {
    Uri? requested;
    final client = MockClient((request) async {
      requested = request.url;
      return http.Response(
          jsonEncode({
            'data': [],
            'total': 0,
            'filters': {'start_date': null, 'end_date': null, 'hub_id': null},
          }),
          200);
    });
    final response = await HubAnalyticsApi(
      client: client,
      baseUrl: 'https://api.example.test/',
    ).list();
    expect(
        requested.toString(), 'https://api.example.test/api/v1/analytics/hubs');
    expect(response.data, isEmpty);

    final failing = HubAnalyticsApi(
      client: MockClient((_) async => http.Response('{}', 503)),
      baseUrl: 'https://api.example.test',
    );
    await expectLater(failing.list(), throwsA(isA<Exception>()));
  });

  test('surfaces request timeouts', () async {
    final api = HubAnalyticsApi(
      client: MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return http.Response('{}', 200);
      }),
      baseUrl: 'https://api.example.test',
      timeout: const Duration(milliseconds: 1),
    );
    await expectLater(api.list(), throwsA(isA<TimeoutException>()));
  });

  test('rejects invalid risk percentages instead of displaying them', () {
    expect(
      () => HubRiskAggregate.fromJson(_aggregate('hub-a', 101)),
      throwsFormatException,
    );
  });
}
