import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:logipredict_ai/main.dart' as app;

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  final elapsed = Stopwatch()..start();
  while (finder.evaluate().isEmpty) {
    if (elapsed.elapsed > const Duration(seconds: 60)) {
      fail('A tela não apresentou o elemento esperado: $finder');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android consulta o servidor e executa a previsao real no mapa',
      (tester) async {
    await app.main();
    await tester.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(find.byTooltip('Configurar conexão'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conexão USB'));
    await tester.tap(find.text('Testar conexão'));
    await tester.pumpAndSettle();
    await waitFor(tester,
        find.text('Conexão disponível. O serviço de previsão está pronto.'));
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('android-simulador');

    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('Mapa')));
    await tester.pumpAndSettle();
    final example = find.byKey(const ValueKey('future-example'));
    await tester.ensureVisible(example);
    await tester.tap(example);
    await tester.pumpAndSettle();
    final calculate = find.byKey(const ValueKey('map-simulate'));
    await tester.ensureVisible(calculate);
    await tester.tap(calculate);
    await tester.pumpAndSettle();
    await waitFor(tester, find.text('Risco alto'));
    await tester.ensureVisible(find.text('Risco alto'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('android-previsao');
    await tester.ensureVisible(find.text('Detalhes da análise'));
    await tester.tap(find.text('Detalhes da análise'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Modelo: modelo_564_filter'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.byKey(const ValueKey('forecast-leaflet')));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('android-rota');
    await tester.tap(find.text('Histórico'));
    await tester.pumpAndSettle();
    await waitFor(tester, find.byType(PolygonLayer<Object>));
    await binding.takeScreenshot('android-historico');
    final region = find.textContaining('Sudeste ·');
    await tester.tap(region);
    await tester.pumpAndSettle();
    expect(find.text('Sudeste — histórico Olist'), findsOneWidget);
    await binding.takeScreenshot('android-detalhes-regiao');
    Navigator.of(tester.element(find.byType(BottomSheet))).pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    for (final label in ['Pedidos', 'Análises', 'Hubs']) {
      await tester.tap(find.descendant(
          of: find.byType(NavigationBar), matching: find.text(label)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: label);
    }
    await binding.takeScreenshot('android-hubs');
  });
}
