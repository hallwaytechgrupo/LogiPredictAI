import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logipredict_ai/screens/orders_import_screen.dart';
import 'package:logipredict_ai/screens/orders_screen.dart';

const pickerChannel = MethodChannel('miguelruivo.flutter.plugins.filepicker');

http.Response response(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

http.Response emptyData(http.Request request) {
  if (request.url.path == '/api/v1/orders/summary') {
    return response({
      'data': {'total': 0, 'withHub': 0, 'withoutHub': 0, 'withPrediction': 0}
    });
  }
  return response({'data': [], 'total': 0, 'page': 1, 'total_pages': 1});
}

void main() {
  for (final screen in <Widget>[
    const OrdersScreen(),
    const OrdersImportScreen()
  ]) {
    testWidgets(
        '${screen.runtimeType} reads picker bytes and submits five UTF-8 records',
        (tester) async {
      final csv = File('../back/data/exemplos_fe04_be02.csv')
          .readAsStringSync()
          .replaceFirst('DEMO-FE04-001', 'DEMO-SÃO-PAULO');
      final bytes = Uint8List.fromList(utf8.encode('\uFEFF$csv'));
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(pickerChannel, (call) async {
        expect(call.method, 'custom');
        expect(call.arguments['withData'], isTrue);
        return [
          {
            'name': 'exemplos_fe04_be02.csv',
            'size': bytes.length,
            'bytes': bytes
          }
        ];
      });
      addTearDown(
          () => messenger.setMockMethodCallHandler(pickerChannel, null));
      await tester.binding.setSurfaceSize(const Size(1400, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      String? submitted;
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: screen)));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Selecionar CSV'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Não foi possível ler'), findsNothing);
        final importButton = find.ancestor(
            of: find.text('Importar'),
            matching:
                find.byWidgetPredicate((widget) => widget is ElevatedButton));
        expect(
            tester.widget<ElevatedButton>(importButton).onPressed, isNotNull);
        await tester.tap(find.text('Importar'));
        await tester.pumpAndSettle();
        expect(submitted, csv);
        expect(submitted, contains('DEMO-SÃO-PAULO'));
        expect(find.text('Importação concluída!'), findsOneWidget);
      },
          () => MockClient((request) async {
                if (request.url.path == '/api/v1/orders/import-csv') {
                  submitted = (jsonDecode(request.body)
                      as Map<String, dynamic>)['csv'] as String;
                  return response(
                      {'imported': 5, 'ignored': 0, 'failed': 0, 'data': {}});
                }
                return emptyData(request);
              }));
    });
  }

  for (final selection in ['empty', 'cancel']) {
    testWidgets(
        '$selection selection disables importing previously selected content',
        (tester) async {
      var calls = 0;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(pickerChannel, (call) async {
        calls++;
        if (calls == 1) {
          final bytes =
              Uint8List.fromList(utf8.encode('order_id\nfirst-order\n'));
          return [
            {'name': 'first.csv', 'size': bytes.length, 'bytes': bytes}
          ];
        }
        if (selection == 'cancel') return null;
        return [
          {'name': 'empty.csv', 'size': 0, 'bytes': Uint8List(0)}
        ];
      });
      addTearDown(
          () => messenger.setMockMethodCallHandler(pickerChannel, null));
      await tester.binding.setSurfaceSize(const Size(1400, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await http.runWithClient(() async {
        await tester.pumpWidget(
            const MaterialApp(home: Scaffold(body: OrdersScreen())));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Selecionar CSV'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('first.csv'));
        await tester.pumpAndSettle();
        final importButton = find.ancestor(
            of: find.text('Importar'),
            matching:
                find.byWidgetPredicate((widget) => widget is ElevatedButton));
        expect(tester.widget<ElevatedButton>(importButton).onPressed, isNull);
        expect(find.text('first.csv'), findsNothing);
      }, () => MockClient((request) async => emptyData(request)));
    });
  }
}
