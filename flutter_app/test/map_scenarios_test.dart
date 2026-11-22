import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logipredict_ai/screens/prediction_map_screen.dart';
import 'package:logipredict_ai/services/map_scenarios_api.dart';

const shipment = {
  'purchase_at': '2018-06-01T10:00:00',
  'dispatched_at': '2018-06-02T10:00:00',
  'estimated_delivery_at': '2018-06-15T00:00:00',
  'seller_state': 'SP',
  'customer_state': 'RJ',
  'distance_km': 350.0,
  'total_weight_g': 500.0,
  'total_volume_cm3': 1200.0,
  'items_count': 1,
  'sellers_count': 1,
  'price': 89.9,
  'freight_value': 15.0,
  'seller_id': 'real-seller-fixture',
  'origin_prefix5': '01001',
  'destination_prefix5': '20040',
};
const record = {
  'order_id': 'order-fixture',
  'purchase_at': '2018-06-01T10:00:00',
  'dispatched_at': '2018-06-02T10:00:00',
  'estimated_delivery_at': '2018-06-15T00:00:00',
  'origin': {
    'prefix5': '01001',
    'state': 'SP',
    'latitude': -23.55,
    'longitude': -46.63
  },
  'destination': {
    'prefix5': '20040',
    'state': 'RJ',
    'latitude': -22.90,
    'longitude': -43.17
  },
  'risk': 'Alto',
  'score': .1,
  'already_overdue': false,
};
const catalog = {
  'start_date': '2018-04-25',
  'end_date': '2018-08-29',
  'states': ['SP', 'RJ'],
  'regions': ['Sudeste'],
  'risk_definitions': {'Baixo': 'Sem alerta inicial.'},
  'limitations': ['Score não calibrado.'],
  'metrics': {'TP': 564, 'FP': 4358, 'FN': 140, 'known_overdue_TP': 130},
};
const result = {
  'risk': 'Alto',
  'score': .1,
  'base_score': .6,
  'base_threshold': .37,
  'filter_score': .1,
  'threshold': .03386,
  'predicted_late': true,
  'already_overdue': false,
  'remaining_days': 13,
  'purchase_at': '2018-06-01T10:00:00',
  'dispatched_at': '2018-06-02T10:00:00',
  'estimated_delivery_at': '2018-06-15T00:00:00',
  'history': {
    'seller_orders': 150,
    'route_orders': 6000,
    'history_asof': '2018-06-02T10:00:00'
  },
};

http.Response jsonResponse(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  test(
      'API preserves encoded filters and reports validation and malformed responses',
      () async {
    final calls = <http.Request>[];
    final api = MapScenariosApi(
        baseUrl: 'http://localhost:3001',
        client: MockClient((req) async {
          calls.add(req);
          if (req.url.path.endsWith('simulate')) {
            return jsonResponse({
              'message': 'Revise as datas.',
              'details': [
                {'message': 'Despacho anterior à compra.'}
              ]
            }, 422);
          }
          if (req.url.path.endsWith('catalog')) {
            return http.Response('<html>erro</html>', 502);
          }
          return jsonResponse({'total': 0, 'data': []});
        }));
    await api.get(
        'orders', {'risk': 'Médio', 'region': 'Centro-Oeste', 'offset': '30'});
    expect(calls.single.url.queryParameters['risk'], 'Médio');
    expect(calls.single.url.queryParameters['offset'], '30');
    await expectLater(api.simulate({'order_id': 'abc'}),
        throwsA(predicate((e) => e.toString().contains('Despacho anterior'))));
    expect(jsonDecode(calls.last.body), {'order_id': 'abc'});
    await expectLater(api.get('catalog'),
        throwsA(predicate((e) => e.toString().contains('resposta inválida'))));
    api.close();
  });

  testWidgets(
      'map sends real form values and shows the server classification and comparisons',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, dynamic>? submitted;
    final queries = <Map<String, String>>[];
    final api = MapScenariosApi(client: MockClient((req) async {
      if (req.url.path.endsWith('/catalog')) return jsonResponse(catalog);
      if (req.url.path.endsWith('/orders')) {
        queries.add(req.url.queryParameters);
        return jsonResponse({
          'total': 1,
          'counts': {'Alto': 1},
          'data': [record]
        });
      }
      if (req.url.path.endsWith('/order')) {
        return jsonResponse(
            {...record, 'shipment': shipment, 'observed_late': true});
      }
      if (req.url.path.endsWith('/simulate')) {
        submitted = jsonDecode(req.body) as Map<String, dynamic>;
        return jsonResponse({
          'model_version': 'modelo_564_filter',
          'shipment': shipment,
          'origin': record['origin'],
          'destination': record['destination'],
          'result': result,
          'calendar': {
            'fixed_national_holidays': [],
            'dispatch_holiday': null,
            'dispatch_weekend': true,
            'coverage': 'Somente feriados fixos.'
          },
          'alternatives': [
            {
              ...result,
              'label': 'Despachar um dia antes',
              'risk': 'Baixo',
              'lower_risk': true
            }
          ],
          'suggestions': [
            'Antecipar o despacho reduziu a faixa nesta simulação.'
          ],
          'warnings': ['Score não calibrado.'],
          'comparison_policy': 'Histórico congelado no despacho informado.',
        });
      }
      return jsonResponse({'data': []});
    }));
    await tester.pumpWidget(MaterialApp(
        home: DefaultTabController(
      length: 2,
      child: Scaffold(
          body: Column(children: [
        const TabBar(tabs: [Tab(text: 'Pesquisa'), Tab(text: 'Histórico')]),
        Expanded(
            child: TabBarView(children: [
          PredictionMapScreen(api: api),
          const Text('Histórico exibido')
        ])),
      ])),
    )));
    await tester.pumpAndSettle();
    expect(find.text('1 pedidos encontrados'), findsOneWidget);
    await tester.tap(find.text('Exemplos: Alto'));
    await tester.pumpAndSettle();
    expect(queries.last['risk'], 'Alto');
    await tester
        .ensureVisible(find.byKey(const ValueKey('order-order-fixture')));
    await tester.tap(find.byKey(const ValueKey('order-order-fixture')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('scenario-destination')), '20040-002');
    await tester.ensureVisible(find.byKey(const ValueKey('map-simulate')));
    await tester.tap(find.byKey(const ValueKey('map-simulate')));
    await tester.pumpAndSettle();
    expect(submitted!['order_id'], 'order-fixture');
    expect(submitted!['total_weight_g'],
        500.0); // O formulário exibe kg, a API recebe g.
    expect(submitted!['destination_prefix5'], '20040');
    expect(submitted!.containsKey('observed_late'), isFalse);
    expect(find.text('Resultado do cenário informado'), findsOneWidget);
    expect(find.text('Faixa de risco menor nesta simulação.'), findsOneWidget);
    expect(find.text('Score não calibrado.'),
        findsNothing); // Está identificado como aviso, não como probabilidade.
    expect(find.text('Aviso: Score não calibrado.'), findsOneWidget);
    await tester.tap(find.text('Histórico'));
    await tester.pumpAndSettle();
    expect(find.text('Histórico exibido'), findsOneWidget);
    await tester.tap(find.text('Pesquisa'));
    await tester.pumpAndSettle();
    expect(find.text('Resultado do cenário informado'), findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(
                find.byKey(const ValueKey('scenario-destination')))
            .controller!
            .text,
        '20040-002');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  testWidgets('map shows an unavailable service and allows a retry',
      (tester) async {
    var attempts = 0;
    final api = MapScenariosApi(client: MockClient((req) async {
      if (req.url.path.endsWith('/catalog')) {
        attempts++;
        return attempts == 1
            ? jsonResponse({'message': 'Serviço Python indisponível.'}, 503)
            : jsonResponse(catalog);
      }
      return jsonResponse({'total': 0, 'counts': {}, 'data': []});
    }));
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: PredictionMapScreen(api: api))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Serviço Python indisponível.'), findsOneWidget);
    await tester.tap(find.text('Tentar carregar novamente'));
    await tester.pumpAndSettle();
    expect(find.text('Pesquisar pedidos reais'), findsOneWidget);
    expect(attempts, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
}
