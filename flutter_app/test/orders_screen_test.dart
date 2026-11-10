import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logipredict_ai/screens/orders_screen.dart';
import 'package:logipredict_ai/services/hubs_api.dart';
import 'package:logipredict_ai/services/orders_api.dart';

void main() {
  for (final entry in {
    'pending': 'Pendente',
    'shipped': 'Em transporte',
    'delivered': 'Entregue',
    'canceled': 'Cancelado',
  }.entries) {
    testWidgets('active orders screen shows ${entry.value} and promised date', (tester) async {
      tester.view.physicalSize = const Size(2000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/summary')) {
          return http.Response(jsonEncode({'data': {
            'total': 1, 'withHub': 0, 'withoutHub': 1, 'withPrediction': 0,
          }}), 200);
        }
        if (request.url.path.endsWith('/hubs')) {
          return http.Response('{"data":[]}', 200);
        }
        expect(request.url.path, '/api/v1/orders');
        expect(request.url.queryParameters['source'], 'operational');
        return http.Response(jsonEncode({
          'data': [{
            'order_id': 'TESTE-0001', 'status': entry.key,
            'estimated_delivery_at': '2026-10-08T18:00:00',
            'source': 'operational', 'hub': null,
          }],
          'total': 1, 'page': 1, 'total_pages': 1,
        }), 200);
      });
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: OrdersScreen(
        ordersApi: OrdersApi(client: client, baseUrl: 'http://api.test'),
        hubsApi: HubsApi(client: client, baseUrl: 'http://api.test'),
      ))));
      await tester.pumpAndSettle();
      expect(find.text('Status'), findsOneWidget);
      expect(find.text(entry.value), findsOneWidget);
      expect(find.text('Entrega prometida'), findsOneWidget);
      expect(find.text('08/10/2026'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Ver detalhes'));
      await tester.tap(find.byTooltip('Ver detalhes'));
      await tester.pumpAndSettle();
      final dialog = find.byType(AlertDialog);
      expect(find.descendant(of: dialog, matching: find.text(entry.value)), findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text('08/10/2026')), findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text('Entrega prometida')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
