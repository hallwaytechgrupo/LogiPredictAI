import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logipredict_ai/screens/hubs_management_screen.dart';
import 'package:logipredict_ai/services/hubs_api.dart';

class _HubsApiFake extends HubsApi {
  _HubsApiFake() : super();

  @override
  Future<List<LogisticHub>> list({
    bool includeInactive = false,
    String? query,
    String? validationStatus,
  }) async => const [
        LogisticHub(
          id: 'osm-1',
          code: 'OSM-relation-4602996',
          name: 'Mercado Municipal de São Paulo',
          city: 'São Paulo',
          state: 'SP',
          status: 'inactive',
          validationStatus: 'PENDENTE_VALIDACAO',
          osmId: 'relation/4602996',
          latitude: -23.5417397,
          longitude: -46.6294216,
        ),
      ];
}

void main() {
  testWidgets('shows imported hub candidates and their review state',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: HubsManagementScreen(api: _HubsApiFake()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Mercado Municipal de São Paulo'), findsOneWidget);
    expect(find.textContaining('PENDENTE_VALIDACAO'), findsOneWidget);
    expect(find.text('Validação'), findsOneWidget);
  });
}
