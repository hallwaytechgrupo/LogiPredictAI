import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logipredict_ai/screens/dashboard_screen.dart';
import 'package:logipredict_ai/screens/orders_screen.dart';

const order = <String, dynamic>{
  'order_id': 'DEMO-FE04-001',
  'origin_zip_code': '01001000',
  'destination_zip_code': '20040002',
  'purchase_at': '2026-11-01T09:00:00',
  'dispatched_at': '2026-11-02T10:00:00',
  'estimated_delivery_at': '2026-11-12T18:00:00',
  'seller_state': 'SP',
  'customer_state': 'RJ',
  'items_count': 1,
  'sellers_count': 1,
  'price': 89.9,
  'freight_value': 15.0,
  'total_weight_g': 500,
  'total_volume_cm3': 1200,
  'status': 'shipped',
};

http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

http.Response defaultResponse(http.Request request) {
  switch (request.url.path) {
    case '/api/v1/orders/summary':
      return jsonResponse({
        'data': {'total': 1, 'withHub': 0, 'withoutHub': 1, 'withPrediction': 0}
      });
    case '/api/v1/orders':
      return jsonResponse({
        'data': [order],
        'total': 1,
        'page': 1,
        'total_pages': 1
      });
    case '/api/v1/analytics/states':
      return jsonResponse({'states': []});
    default:
      return jsonResponse({'data': [], 'total': 0});
  }
}

Finder field(String label) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label);

String fieldText(WidgetTester tester, String label) =>
    tester.widget<TextField>(field(label)).controller!.text;

void main() {
  testWidgets(
      'orders table and details display server status and promised date',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await http.runWithClient(() async {
      await tester
          .pumpWidget(const MaterialApp(home: Scaffold(body: OrdersScreen())));
      await tester.pumpAndSettle();
      expect(find.text('Entrega prometida'), findsOneWidget);
      expect(find.text('12/11/2026'), findsOneWidget);
      expect(find.text('Em transporte'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Ver detalhes'));
      await tester.tap(find.byTooltip('Ver detalhes'));
      await tester.pumpAndSettle();
      expect(find.text('Entrega prometida'), findsNWidgets(2));
      expect(find.text('Em transporte'), findsNWidgets(2));
      expect(find.text('0.5'), findsOneWidget);
    }, () => MockClient((request) async => defaultResponse(request)));
  });

  testWidgets(
      'simulator loads complete order, sends model payload and clears missing values on next selection',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final pendingDetails = Completer<http.Response>();
    var detailCalls = 0;
    Map<String, dynamic>? prediction;
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
          home: DashboardScreen(isDarkMode: false, onThemeToggle: () {})));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      await tester.enterText(field('Pesquisar por order_id'), 'DEMO');
      await tester.pumpAndSettle();
      await tester.tap(find.text('DEMO-FE04-001').first);
      await tester.pump();
      expect(find.text('Carregando dados do pedido...'), findsOneWidget);
      pendingDetails.complete(jsonResponse({'data': order}));
      await tester.pumpAndSettle();
      expect(fieldText(tester, 'Peso total do pedido (kg)'), '0.5');
      expect(
          fieldText(tester, 'Volume total do pedido (cm³, opcional)'), '1200');
      await tester.ensureVisible(find.text('Simular operação logística'));
      await tester.tap(find.text('Simular operação logística'));
      await tester.pumpAndSettle();
      expect(prediction!['total_weight_g'], 500);
      expect(prediction!['total_volume_cm3'], 1200);
      expect(prediction!.containsKey('status'), isFalse);
      expect(find.text('O modelo classificou risco de atraso'), findsOneWidget);

      await tester.ensureVisible(field('Pesquisar por order_id'));
      await tester.enterText(field('Pesquisar por order_id'), 'DEMO');
      await tester.pumpAndSettle();
      await tester.tap(find.text('DEMO-FE04-001').first);
      await tester.pumpAndSettle();
      expect(detailCalls, 2);
      expect(fieldText(tester, 'Peso total do pedido (kg)'), isEmpty);
      expect(
          fieldText(tester, 'Volume total do pedido (cm³, opcional)'), isEmpty);
    },
        () => MockClient((request) async {
              switch (request.url.path) {
                case '/api/v1/orders/DEMO-FE04-001':
                  detailCalls++;
                  if (detailCalls == 1) return pendingDetails.future;
                  return jsonResponse({
                    'data': {
                      ...order,
                      'total_weight_g': null,
                      'total_volume_cm3': null
                    }
                  });
                case '/api/v1/geolocation/route':
                  return jsonResponse({
                    'data': {
                      'origins': [
                        {'cep': '01001000', 'city': 'São Paulo', 'state': 'SP'}
                      ],
                      'destination': {
                        'cep': '20040002',
                        'city': 'Rio de Janeiro',
                        'state': 'RJ'
                      },
                      'seller_state': 'SP',
                      'customer_state': 'RJ',
                      'distance_km': 360,
                    }
                  });
                case '/api/v1/predictions':
                  prediction = jsonDecode(request.body) as Map<String, dynamic>;
                  expect(
                      request.url.queryParameters['order_id'], 'DEMO-FE04-001');
                  return jsonResponse({
                    'delay_probability': 0.7,
                    'predicted_late': true,
                    'threshold': 0.37,
                    'model_version': 'test-model',
                    'source': 'olist',
                    'synthetic': false,
                    'warnings': [],
                  });
                case '/api/v1/dispatch/simulate':
                  return jsonResponse({
                    'error': 'NO_HUBS_AVAILABLE',
                    'message': 'Sem hubs para este teste.'
                  }, 422);
                default:
                  return defaultResponse(request);
              }
            }));
  });

  testWidgets('orders show API error and retry successfully', (tester) async {
    var fail = true;
    await tester.binding.setSurfaceSize(const Size(1500, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await http.runWithClient(() async {
      await tester
          .pumpWidget(const MaterialApp(home: Scaffold(body: OrdersScreen())));
      await tester.pumpAndSettle();
      expect(find.text('Erro ao carregar pedidos'), findsOneWidget);
      expect(find.textContaining('Erro ao carregar resumo'), findsOneWidget);
      fail = false;
      await tester.ensureVisible(find.text('Tentar novamente'));
      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();
      expect(find.text('DEMO-FE04-001'), findsOneWidget);
      expect(find.text('Em transporte'), findsOneWidget);
    },
        () => MockClient((request) async {
              if (fail && request.url.path.startsWith('/api/v1/orders')) {
                return jsonResponse(
                    {'message': 'Servidor de teste indisponível.'}, 503);
              }
              return defaultResponse(request);
            }));
  });

  testWidgets('orders paginate on the server and ignore stale search responses',
      (tester) async {
    final staleSearch = Completer<http.Response>();
    final requests = <Uri>[];
    await tester.binding.setSurfaceSize(const Size(1500, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final search = find.byWidgetPredicate((widget) =>
        widget is TextField &&
        widget.decoration?.hintText == 'Buscar por ID...');
    await http.runWithClient(() async {
      await tester
          .pumpWidget(const MaterialApp(home: Scaffold(body: OrdersScreen())));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Próxima'));
      await tester.tap(find.text('Próxima'));
      await tester.pumpAndSettle();
      expect(find.text('Página 2 de 2'), findsOneWidget);
      expect(find.text('page-2'), findsOneWidget);
      await tester.ensureVisible(search);
      await tester.enterText(search, 'A');
      await tester.pump();
      await tester.enterText(search, 'AB');
      await tester.pumpAndSettle();
      expect(find.text('AB-result'), findsOneWidget);
      staleSearch.complete(jsonResponse({
        'data': [
          {...order, 'order_id': 'stale-result'}
        ],
        'total': 1,
        'page': 1,
        'total_pages': 1
      }));
      await tester.pumpAndSettle();
      expect(find.text('AB-result'), findsOneWidget);
      expect(find.text('stale-result'), findsNothing);
      expect(requests.any((uri) => uri.queryParameters['page'] == '2'), isTrue);
      expect(requests.last.queryParameters['source'], 'operational');
    },
        () => MockClient((request) async {
              if (request.url.path != '/api/v1/orders') {
                return defaultResponse(request);
              }
              requests.add(request.url);
              final query = request.url.queryParameters['q'];
              if (query == 'A') return staleSearch.future;
              final page = int.parse(request.url.queryParameters['page']!);
              return jsonResponse({
                'data': [
                  {
                    ...order,
                    'order_id': query == 'AB' ? 'AB-result' : 'page-$page'
                  }
                ],
                'total': query == null ? 21 : 1,
                'page': page,
                'total_pages': query == null ? 2 : 1,
              });
            }));
  });
}
