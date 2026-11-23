import 'dart:convert';
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
  }, () => MockClient((request) async {
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

  testWidgets('future form needs no imported order and survives switching maps',
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
    expect(find.textContaining('Natal (25/12)'), findsOneWidget);
    await tester.tap(find.text('Histórico por região'));
    await tester.pumpAndSettle();
    expect(find.text('Histórico exibido'), findsOneWidget);
    expect(find.byType(LeafletMap, skipOffstage: false), findsNothing);
    await tester.tap(find.text('Simular nova entrega'));
    await tester.pumpAndSettle();
    expect(find.text('Risco alto'), findsOneWidget);
    expect(find.byType(LeafletMap), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  testWidgets(
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
}
