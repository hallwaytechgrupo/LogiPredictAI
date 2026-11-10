import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logipredict_ai/screens/orders_management_screen.dart';
import 'package:logipredict_ai/services/orders_api.dart';

void main() {
  testWidgets('shows status and promised date in the table and fetched details',
      (tester) async {
    tester.view.physicalSize = const Size(1800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final paths = <String>[];
    final api = OrdersApi(
      baseUrl: 'http://api.test',
      client: MockClient((request) async {
        paths.add(request.url.path);
        const order = {
          'order_id': 'example-1',
          'status': 'shipped',
          'estimated_delivery_at': '2026-10-09T00:00:00',
          'source': 'operational',
          'hub': null,
        };
        return http.Response(
            jsonEncode({
              'data': request.url.path.endsWith('/example-1') ? order : [order],
              'total': 1,
              'page': 1,
              'total_pages': 1,
            }),
            200);
      }),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: OrdersManagementScreen(api: api)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Despachado'), findsOneWidget);
    expect(find.text('Entrega prometida'), findsOneWidget);
    expect(find.text('09/10/2026'), findsOneWidget);
    await tester.tap(find.byTooltip('Ver detalhes'));
    await tester.pumpAndSettle();
    expect(paths, ['/api/v1/orders', '/api/v1/orders/example-1']);
    expect(find.text('Status: Despachado'), findsOneWidget);
    expect(find.text('Entrega prometida: 09/10/2026'), findsOneWidget);
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
