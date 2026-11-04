import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:logipredict_ai/services/hubs_api.dart';
import 'package:logipredict_ai/services/orders_api.dart';
import 'package:logipredict_ai/widgets/order_hub_selector.dart';

void main() {
  test('imports order IDs without assigning hubs and returns existing links',
      () async {
    http.Request? captured;
    final api = OrdersApi(
      baseUrl: 'https://api.example.test',
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'data': [
              {'order_id': 'order-1', 'hub_id': null},
            ],
            'total': 1,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final imported = await api.importOrders(['order-1']);

    expect(captured!.url.path, '/api/v1/orders/import');
    expect(jsonDecode(captured!.body), {
      'orders': [
        {'order_id': 'order-1'},
      ],
    });
    expect(imported.single['hub_id'], isNull);
  });

  test('supports explicit demo hub assignment within the 2000 ID API limit',
      () async {
    http.Request? captured;
    final api = OrdersApi(
      baseUrl: 'https://api.example.test',
      client: MockClient((request) async {
        captured = request;
        return http.Response(
            jsonEncode({
              'data': [
                {'order_id': 'order-1', 'hub_id': 'demo-hub'},
              ],
              'total': 1,
            }),
            200);
      }),
    );
    await api.importOrders(['order-1'], defaultHubId: 'demo-hub');
    expect(OrdersApi.importBatchLimit, 2000);
    expect(jsonDecode(captured!.body), {
      'orders': [
        {'order_id': 'order-1'},
      ],
      'default_hub_id': 'demo-hub',
    });
  });

  test('updates association by stable hub ID and supports clearing it',
      () async {
    final requests = <http.Request>[];
    final api = OrdersApi(
      baseUrl: 'https://api.example.test/',
      client: MockClient((request) async {
        requests.add(request);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'data': {'order_id': 'order/1', 'hub_id': body['hub_id']},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await api.setHub('order/1', 'stable-hub-id');
    await api.setHub('order/1', null);

    expect(requests[0].url.path, '/api/v1/orders/order%2F1/hub');
    expect(jsonDecode(requests[0].body), {'hub_id': 'stable-hub-id'});
    expect(jsonDecode(requests[1].body), {'hub_id': null});
  });

  testWidgets('hub selector emits the selected registered hub ID',
      (tester) async {
    String? selected;
    const hub = LogisticHub(
      id: 'hub-stable-id',
      code: 'HUB-01',
      name: 'Hub São Paulo',
      city: 'São Paulo',
      state: 'SP',
      status: 'active',
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OrderHubSelector(
          selectedHubId: null,
          hubs: const [hub],
          onChanged: (hubId) => selected = hubId,
        ),
      ),
    ));

    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hub São Paulo · HUB-01').last);
    await tester.pumpAndSettle();

    expect(selected, hub.id);
  });
}
