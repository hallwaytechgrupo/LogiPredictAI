import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web/web.dart' as web;
import 'package:logipredict_ai/main.dart' as app;

Future<void> waitFor(WidgetTester tester, bool Function() condition) async {
  final elapsed = Stopwatch()..start();
  while (!condition()) {
    if (elapsed.elapsed > const Duration(seconds: 60)) {
      fail('A interface não apresentou o resultado esperado.');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

web.Element? mapStatus() {
  final element =
      web.document.querySelector('iframe[title="Mapa Leaflet LogiPredict"]');
  return element == null
      ? null
      : (element as web.HTMLIFrameElement)
          .contentDocument
          ?.getElementById('status');
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('mapa Web desenha estrada real e preserva previsão e histórico',
      (tester) async {
    await app.main();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mapa de Calor Logístico').first);
    await tester.pumpAndSettle();
    final example = find.byKey(const ValueKey('future-example'));
    await tester.ensureVisible(example);
    await tester.tap(example);
    await waitFor(tester,
        () => find.textContaining('km por estrada').evaluate().isNotEmpty);
    await waitFor(
        tester,
        () =>
            (int.tryParse(
                    mapStatus()?.getAttribute('data-route-points') ?? '') ??
                0) >
            2);
    expect(mapStatus()?.getAttribute('data-mode'), 'forecast');
    await tester.pump(const Duration(seconds: 2));
    await binding.takeScreenshot('web-rota-estrada');

    final calculate = find.byKey(const ValueKey('map-simulate'));
    await tester.ensureVisible(calculate);
    await tester.tap(calculate);
    await waitFor(tester, () => find.text('Risco alto').evaluate().isNotEmpty);
    await tester.ensureVisible(example);
    await tester.pumpAndSettle();
    expect(int.parse(mapStatus()!.getAttribute('data-route-points')!),
        greaterThan(2));
    await binding.takeScreenshot('web-rota-risco');

    await tester.tap(find.text('Histórico por região').first);
    await tester.pumpAndSettle();
    await waitFor(
        tester, () => mapStatus()?.getAttribute('data-mode') == 'history');
    expect(mapStatus()?.getAttribute('data-route-points'), '0');
    await tester.pump(const Duration(seconds: 2));
    await binding.takeScreenshot('web-historico-preservado');

    await tester.tap(find.text('Simular nova entrega').first);
    await tester.pumpAndSettle();
    await waitFor(
        tester,
        () =>
            (int.tryParse(
                    mapStatus()?.getAttribute('data-route-points') ?? '') ??
                0) >
            2);
    expect(find.text('Risco alto'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
