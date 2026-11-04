import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logipredict_ai/services/hubs_api.dart';
import 'package:logipredict_ai/widgets/hub_risk_layer_unavailable.dart';

void main() {
  test('map accepts valid coordinates and rejects invalid coordinates', () {
    const valid = LogisticHub(
      id: 'hub-valid',
      code: 'HUB-1',
      name: 'Hub cadastrado',
      city: 'São Paulo',
      state: 'SP',
      status: 'active',
      latitude: -23.55,
      longitude: -46.63,
    );
    const missing = LogisticHub(
      id: 'hub-missing',
      code: 'HUB-2',
      name: 'Hub sem coordenadas',
      city: 'São Paulo',
      state: 'SP',
      status: 'active',
    );
    const invalidLatitude = LogisticHub(
      id: 'hub-invalid-lat',
      code: 'HUB-3',
      name: 'Hub com latitude inválida',
      city: 'São Paulo',
      state: 'SP',
      status: 'active',
      latitude: 91,
      longitude: -46.63,
    );
    expect(valid.hasValidCoordinates, isTrue);
    expect(missing.hasValidCoordinates, isFalse);
    expect(invalidLatitude.hasValidCoordinates, isFalse);
  });

  test('risk bands describe 0%, partial and 100% aggregates', () {
    expect(hubRiskBand(0), HubRiskBand.noRisk);
    expect(hubRiskBand(12.5), HubRiskBand.low);
    expect(hubRiskBand(50), HubRiskBand.elevated);
    expect(hubRiskBand(99.9), HubRiskBand.elevated);
    expect(hubRiskBand(100), HubRiskBand.allRisk);
    expect(hubRiskBand(null), HubRiskBand.unavailable);
    expect(hubRiskBand(101), HubRiskBand.unavailable);
  });

  testWidgets('risk layer toggle is enabled and labels bands accessibly',
      (tester) async {
    var changed = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HubRiskLayerUnavailable(
          enabled: true,
          loading: false,
          total: 1,
          onChanged: (value) => changed = value,
        ),
      ),
    ));

    final toggle = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('risk-layer-toggle')),
    );
    expect(toggle.value, isTrue);
    expect(toggle.onChanged, isNotNull);
    await tester.tap(find.byKey(const ValueKey('risk-layer-toggle')));
    expect(changed, isFalse);
    expect(find.textContaining('não são novos thresholds'), findsOneWidget);
    expect(find.text(hubRiskLabel(HubRiskBand.allRisk)), findsOneWidget);
    expect(find.textContaining('Sem previsões associadas'), findsOneWidget);
  });

  testWidgets('hub details show no associated predictions when absent',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: HubRiskDetails(aggregate: null)),
    ));
    expect(find.text('Sem previsões associadas a este hub.'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });
}
