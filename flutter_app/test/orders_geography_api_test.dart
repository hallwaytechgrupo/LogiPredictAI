import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:logipredict_ai/services/orders_geography_api.dart';

void main() {
  group('OrderGeographyRecord', () {
    test('parses valid JSON correctly', () {
      final json = {
        'city': 'sao paulo',
        'state': 'SP',
        'total_orders': 1234,
        'orders_with_valid_dates': 1100,
        'delayed_orders': 120,
        'orders_without_delivery_date': 134,
        'delay_rate': 10.91,
        'risk_level': 'medio',
        'latitude': -23.55,
        'longitude': -46.63,
      };

      final record = OrderGeographyRecord.fromJson(json);

      expect(record.city, 'sao paulo');
      expect(record.state, 'SP');
      expect(record.totalOrders, 1234);
      expect(record.ordersWithValidDates, 1100);
      expect(record.delayedOrders, 120);
      expect(record.ordersWithoutDeliveryDate, 134);
      expect(record.delayRate, 10.91);
      expect(record.riskLevel, 'medio');
      expect(record.latitude, -23.55);
      expect(record.longitude, -46.63);
      expect(record.riskBand, OrderRiskBand.medio);
    });

    test('throws on invalid data', () {
      final invalidJson = {
        'city': '',
        'state': 'SP',
        'total_orders': 0,
        'orders_with_valid_dates': 0,
        'delayed_orders': 0,
        'orders_without_delivery_date': 0,
        'delay_rate': 0,
        'risk_level': 'baixo',
        'latitude': -23.55,
        'longitude': -46.63,
      };

      expect(
        () => OrderGeographyRecord.fromJson(invalidJson),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('orderRiskBand', () {
    test('classifies sem_dados', () {
      expect(orderRiskBand('sem_dados'), OrderRiskBand.semDados);
    });

    test('classifies baixo', () {
      expect(orderRiskBand('baixo'), OrderRiskBand.baixo);
    });

    test('classifies medio', () {
      expect(orderRiskBand('medio'), OrderRiskBand.medio);
    });

    test('classifies alto', () {
      expect(orderRiskBand('alto'), OrderRiskBand.alto);
    });

    test('classifies muito_alto', () {
      expect(orderRiskBand('muito_alto'), OrderRiskBand.muitoAlto);
    });

    test('defaults to semDados for unknown values', () {
      expect(orderRiskBand('unknown'), OrderRiskBand.semDados);
    });
  });

  group('OrdersGeographyResponse', () {
    test('parses valid response', () {
      final json = {
        'data': [
          {
            'city': 'sao paulo',
            'state': 'SP',
            'total_orders': 100,
            'orders_with_valid_dates': 90,
            'delayed_orders': 10,
            'orders_without_delivery_date': 10,
            'delay_rate': 11.11,
            'risk_level': 'medio',
            'latitude': -23.55,
            'longitude': -46.63,
          },
        ],
        'total': 1,
        'filters': {'state': 'SP'},
      };

      final response = OrdersGeographyResponse.fromJson(json);

      expect(response.total, 1);
      expect(response.data.length, 1);
      expect(response.data[0].city, 'sao paulo');
      expect(response.filters.state, 'SP');
    });

    test('throws on invalid response structure', () {
      expect(
        () => OrdersGeographyResponse.fromJson({'data': 'invalid'}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('OrdersGeographyApi', () {
    test('list makes correct request and parses response', () async {
      final mockClient = _MockHttpClient((request) async {
        expect(request.url.path, '/api/v1/analytics/orders-geography');
        return http.Response(jsonEncode({
          'data': [
            {
              'city': 'sao paulo',
              'state': 'SP',
              'total_orders': 100,
              'orders_with_valid_dates': 90,
              'delayed_orders': 10,
              'orders_without_delivery_date': 10,
              'delay_rate': 11.11,
              'risk_level': 'medio',
              'latitude': -23.55,
              'longitude': -46.63,
            },
          ],
          'total': 1,
          'filters': {'state': null},
        }), 200);
      });

      final api = OrdersGeographyApi(
        client: mockClient,
        baseUrl: 'http://test.local',
      );
      final response = await api.list();

      expect(response.total, 1);
      expect(response.data[0].city, 'sao paulo');
    });

    test('list with state filter includes query param', () async {
      String? capturedState;
      final mockClient = _MockHttpClient((request) async {
        capturedState = request.url.queryParameters['state'];
        return http.Response(jsonEncode({
          'data': [],
          'total': 0,
          'filters': {'state': 'SP'},
        }), 200);
      });

      final api = OrdersGeographyApi(
        client: mockClient,
        baseUrl: 'http://test.local',
      );
      await api.list(state: 'SP');

      expect(capturedState, 'SP');
    });

    test('list throws on HTTP error', () async {
      final mockClient = _MockHttpClient((request) async {
        return http.Response('Not found', 404);
      });

      final api = OrdersGeographyApi(
        client: mockClient,
        baseUrl: 'http://test.local',
      );

      expect(api.list(), throwsA(isA<Exception>()));
    });

    test('list throws on invalid JSON', () async {
      final mockClient = _MockHttpClient((request) async {
        return http.Response('not json', 200);
      });

      final api = OrdersGeographyApi(
        client: mockClient,
        baseUrl: 'http://test.local',
      );

      expect(api.list(), throwsA(anyOf(isA<FormatException>(), isA<Exception>())));
    });
  });
}

class _MockHttpClient implements http.Client {
  _MockHttpClient(this._handler);

  final Future<http.Response> Function(http.Request request) _handler;

  @override
  Future<http.Response> send(http.BaseRequest request) async {
    return _handler(request as http.Request);
  }
}
