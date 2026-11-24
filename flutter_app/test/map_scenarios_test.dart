import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logipredict_ai/screens/map_workspace_screen.dart';
import 'package:logipredict_ai/services/map_scenarios_api.dart';
import 'package:logipredict_ai/widgets/leaflet_map.dart';

const origin = {
  'prefix5': '01001',
  'city': 'sao paulo',
  'state': 'SP',
  'latitude': -23.55,
  'longitude': -46.63
};
const destination = {
  'prefix5': '20040',
  'city': 'rio de janeiro',
  'state': 'RJ',
  'latitude': -22.90,
  'longitude': -43.17
};
const road = {
  'distance_km': 435.8,
  'duration_seconds': 19800,
  'source': 'openrouteservice',
  'geometry': {
    'type': 'LineString',
    'coordinates': [
      [-46.63, -23.55],
      [-45.9, -23.1],
      [-43.17, -22.90]
    ],
  },
};
http.Response jsonResponse(Object body, [int code = 200]) =>
    http.Response(jsonEncode(body), code,
        headers: {'content-type': 'application/json; charset=utf-8'});
Map<String, dynamic> forecastResult(Map<String, dynamic> input) => {
      'model_version': 'modelo_564_filter',
      'origin': origin,
      'destination': destination,
      'shipment': {...input, 'distance_km': 350},
      'result': {
        'risk': 'Alto',
        'predicted_late': true,
        'remaining_days': 11,
        'score': .2,
        'threshold': .03386,
        'history': {'route_orders': 500, 'seller_orders': 0},
        'already_overdue': false
      },
      'calendar': {
        'fixed_national_holidays': [
          {'name': 'Natal', 'date': '2026-12-25'}
        ]
      },
      'alternatives': [
        {
          'label': 'Despachar um dia antes',
          'risk': 'Médio',
          'dispatched_at': '2026-12-23T15:00:00',
          'estimated_delivery_at': '2027-01-04T18:00:00'
        }
      ],
      'suggestions': ['Uma alternativa reduziu a faixa de risco.'],
      'warnings': ['Base histórica Olist.'],
    };

Future<void> mount(WidgetTester tester, MapScenariosApi api) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await http.runWithClient(() async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MapWorkspaceScreen(
                active: true,
                api: api,
                historyBuilder: (active) => active
                    ? const Text('Histórico exibido')
                    : const SizedBox.shrink()))));
    await tester.pumpAndSettle();
  },
      () => MockClient((request) async {
            if (request.url.host == 'tile.openstreetmap.org') {
              return http.Response.bytes(
                base64Decode(
                    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='),
                200,
                headers: {'content-type': 'image/png'},
              );
            }
            return http.Response('', 404);
          }));
}

void mapTestWidgets(
    String description, Future<void> Function(WidgetTester) body) {
  testWidgets(
      description,
      (tester) => http.runWithClient(
          () => body(tester),
          () => MockClient((request) async => http.Response.bytes(
              base64Decode(
                  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='),
              200,
              headers: {'content-type': 'image/png'}))));
}

void main() {
  test(
      'future endpoint receives a complete new order and preserves HTTP errors',
      () async {
    http.Request? sent;
    final api = MapScenariosApi(client: MockClient((req) async {
      sent = req;
      return jsonResponse({'message': 'Confira as datas.'}, 422);
    }));
    await expectLater(
        api.forecast(
            {'purchase_at': '2026-12-23T09:00:00', 'origin_prefix5': '01001'}),
        throwsA(predicate((e) => e.toString().contains('Confira as datas'))));
    expect(sent!.url.path, '/api/v1/map/forecast');
    expect(jsonDecode(sent!.body)['origin_prefix5'], '01001');
    api.close();
  });

  mapTestWidgets(
      'future form needs no imported order and survives switching maps',
      (tester) async {
    final calls = <http.Request>[];
    Map<String, dynamic>? sent;
    final api = MapScenariosApi(client: MockClient((req) async {
      calls.add(req);
      if (req.url.path.endsWith('/locations')) {
        return jsonResponse({
          'data': [
            req.url.queryParameters['q'] == '01001' ? origin : destination
          ]
        });
      }
      if (req.url.path.endsWith('/forecast')) {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return jsonResponse(forecastResult(sent!));
      }
      if (req.url.path.endsWith('/route')) return jsonResponse({'data': road});
      throw StateError('The future form must not request historical orders.');
    }));
    await mount(tester, api);
    expect(calls, isEmpty);
    expect(find.byType(LeafletMap), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('future-example')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('map-simulate')));
    await tester.tap(find.byKey(const ValueKey('map-simulate')));
    await tester.pumpAndSettle();
    expect(sent!['origin_prefix5'], '01001');
    expect(sent!['destination_prefix5'], '20040');
    expect(sent!['total_weight_g'], 500.0);
    expect(sent!.containsKey('order_id'), isFalse);
    expect(sent!.containsKey('seller_id'), isFalse);
    expect(sent!['purchase_at'].toString().contains('-12-23T09:00'), isTrue);
    expect(find.text('Risco alto'), findsOneWidget);
    expect(find.textContaining('435,8 km por estrada'), findsOneWidget);
    final config = tester.widget<LeafletMap>(find.byType(LeafletMap)).config;
    expect(config['roadRoute'], road);
    expect(calls.where((request) => request.url.path.endsWith('/route')),
        hasLength(1));
    expect(sent!.containsKey('distance_km'), isFalse);
    expect(find.textContaining('Natal (25/12)'), findsOneWidget);
    await tester.tap(find.text('Histórico por região'));
    await tester.pumpAndSettle();
    expect(find.text('Histórico exibido'), findsOneWidget);
    expect(find.byType(LeafletMap, skipOffstage: false), findsNothing);
    await tester.tap(find.text('Simular nova entrega'));
    await tester.pumpAndSettle();
    expect(find.text('Risco alto'), findsOneWidget);
    expect(find.byType(LeafletMap), findsOneWidget);
    expect(calls.where((request) => request.url.path.endsWith('/route')),
        hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  mapTestWidgets(
      'form errors do not send invalid future dates and API failure can be retried',
      (tester) async {
    var attempts = 0;
    final api = MapScenariosApi(client: MockClient((req) async {
      if (req.url.path.endsWith('/locations')) {
        return jsonResponse({
          'data': [
            req.url.queryParameters['q'] == '01001' ? origin : destination
          ]
        });
      }
      if (req.url.path.endsWith('/route')) return jsonResponse({'data': road});
      attempts++;
      return attempts == 1
          ? jsonResponse({'message': 'Serviço indisponível.'}, 503)
          : jsonResponse(
              forecastResult(jsonDecode(req.body) as Map<String, dynamic>));
    }));
    await mount(tester, api);
    await tester.tap(find.byKey(const ValueKey('future-example')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('future-purchase')));
    await tester.enterText(
        find.byKey(const ValueKey('future-purchase')), '31/02/2026 09:00');
    await tester.ensureVisible(find.byKey(const ValueKey('map-simulate')));
    await tester.tap(find.byKey(const ValueKey('map-simulate')));
    await tester.pumpAndSettle();
    expect(attempts, 0);
    expect(find.text('Use DD/MM/AAAA HH:mm.'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('future-purchase')));
    await tester.enterText(
        find.byKey(const ValueKey('future-purchase')), '23/12/2026 09:00');
    await tester.ensureVisible(find.byKey(const ValueKey('map-simulate')));
    await tester.tap(find.byKey(const ValueKey('map-simulate')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Serviço indisponível.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('map-simulate')));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('Risco alto'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  mapTestWidgets(
      'a road failure does not prevent prediction and can be retried',
      (tester) async {
    var routes = 0;
    final api = MapScenariosApi(client: MockClient((req) async {
      if (req.url.path.endsWith('/locations')) {
        return jsonResponse({
          'data': [
            req.url.queryParameters['q'] == '01001' ? origin : destination
          ]
        });
      }
      if (req.url.path.endsWith('/route')) {
        routes++;
        return routes == 1
            ? jsonResponse(
                {'message': 'Rotas temporariamente indisponíveis.'}, 503)
            : jsonResponse({'data': road});
      }
      return jsonResponse(
          forecastResult(jsonDecode(req.body) as Map<String, dynamic>));
    }));
    await mount(tester, api);
    await tester.tap(find.byKey(const ValueKey('future-example')));
    await tester.pumpAndSettle();
    expect(find.text('Trajeto pelas estradas indisponível.'), findsOneWidget);
    expect(
        tester.widget<LeafletMap>(find.byType(LeafletMap)).config['roadRoute'],
        isNull);
    await tester.ensureVisible(find.byKey(const ValueKey('map-simulate')));
    await tester.tap(find.byKey(const ValueKey('map-simulate')));
    await tester.pumpAndSettle();
    expect(find.text('Risco alto'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('retry-road-route')));
    await tester.tap(find.byKey(const ValueKey('retry-road-route')));
    await tester.pumpAndSettle();
    expect(find.textContaining('435,8 km por estrada'), findsOneWidget);
    expect(routes, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  mapTestWidgets('an old route response cannot replace a newer selection',
      (tester) async {
    final first = Completer<http.Response>();
    var routes = 0;
    final api = MapScenariosApi(client: MockClient((req) async {
      if (req.url.path.endsWith('/locations')) {
        return jsonResponse({
          'data': [
            req.url.queryParameters['q'] == '01001' ? origin : destination
          ]
        });
      }
      routes++;
      if (routes == 1) return first.future;
      return jsonResponse({'data': road});
    }));
    await mount(tester, api);
    await tester.tap(find.byKey(const ValueKey('future-example')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.ensureVisible(find.byKey(const ValueKey('future-example')));
    await tester.tap(find.byKey(const ValueKey('future-example')));
    await tester.pumpAndSettle();
    expect(find.textContaining('435,8 km por estrada'), findsOneWidget);
    first.complete(jsonResponse({
      'data': {...road, 'distance_km': 999}
    }));
    await tester.pumpAndSettle();
    expect(
        tester.widget<LeafletMap>(find.byType(LeafletMap)).config['roadRoute']
            ?['distance_km'],
        435.8);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  test('the road API rejects a malformed geometry', () async {
    final api = MapScenariosApi(
        client: MockClient((req) async => jsonResponse({
              'data': {
                ...road,
                'geometry': {
                  'type': 'Point',
                  'coordinates': [0, 0]
                }
              }
            })));
    await expectLater(api.roadRoute(origin, destination), throwsException);
    api.close();
  });
}
