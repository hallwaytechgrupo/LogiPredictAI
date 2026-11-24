import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logipredict_ai/main.dart';
import 'package:logipredict_ai/widgets/leaflet_map_native.dart';
import 'package:flutter_map/flutter_map.dart';

http.Response response(Object value) => http.Response(jsonEncode(value), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});

final _transparentPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');

http.Client mobileClient() => MockClient((request) async {
      if (request.url.host == 'tile.openstreetmap.org') {
        return http.Response.bytes(_transparentPng, 200,
            headers: {'content-type': 'image/png'});
      }
      if (request.url.path.endsWith('/analytics/states')) {
        return response({'states': []});
      }
      if (request.url.path.endsWith('/orders/summary')) {
        return response({
          'data': {
            'total': 10,
            'withHub': 5,
            'withoutHub': 5,
            'withPrediction': 2
          }
        });
      }
      return response({'data': [], 'total': 0, 'page': 1, 'total_pages': 1});
    });

void viewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  for (final size in [
    const Size(360, 800),
    const Size(320, 640),
    const Size(740, 360),
    const Size(360, 450)
  ]) {
    testWidgets('telas sem overflow em ${size.width}x${size.height}',
        (tester) async {
      viewport(tester, size);
      final frameworkErrors = <FlutterErrorDetails>[];
      final handler = FlutterError.onError;
      FlutterError.onError = (details) {
        frameworkErrors.add(details);
        handler?.call(details);
      };
      addTearDown(() => FlutterError.onError = handler);
      await http.runWithClient(() async {
        await tester.pumpWidget(const LogiPredictApp());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason:
                frameworkErrors.map((error) => error.toString()).join('\n'));
        if (size.width < 650) {
          expect(find.byType(NavigationBar), findsOneWidget);
          for (final label in [
            'Pedidos',
            'Mapa',
            'Análises',
            'Hubs',
            'Simular'
          ]) {
            await tester.tap(find.descendant(
                of: find.byType(NavigationBar), matching: find.text(label)));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull,
                reason:
                    '$label\n${frameworkErrors.map((error) => error.toString()).join('\n')}');
          }
        } else {
          for (final label in [
            'Pedidos',
            'Analytics & KPIs',
            'Gestão de Hubs'
          ]) {
            await tester.ensureVisible(find.text(label).first);
            await tester.tap(find.text(label).first);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull,
                reason:
                    '$label\n${frameworkErrors.map((error) => error.toString()).join('\n')}');
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }, mobileClient);
    });
  }

  testWidgets('mapa nativo centraliza a rota e usa a cor do risco',
      (tester) async {
    viewport(tester, const Size(360, 800));
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
              body: LeafletSurface(
        blocked: false,
        config: {
          'mode': 'forecast',
          'fitToken': 1,
          'risk': 'Alto',
          'roadRoute': {
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                [-46.63, -23.55],
                [-45.90, -22.5],
                [-43.17, -22.90]
              ],
            },
          },
          'origin': {
            'latitude': -23.55,
            'longitude': -46.63,
            'city': 'São Paulo',
            'state': 'SP',
            'prefix5': '01001'
          },
          'destination': {
            'latitude': -22.90,
            'longitude': -43.17,
            'city': 'Rio de Janeiro',
            'state': 'RJ',
            'prefix5': '20040'
          }
        },
      ))));
      await tester.pumpAndSettle();
      final lines =
          tester.widget<PolylineLayer>(find.byType(PolylineLayer)).polylines;
      expect(lines.single.color, const Color(0xFFDC2626));
      expect(lines.single.points, hasLength(3));
      expect(lines.single.points[1].latitude, -22.5);
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(map.mapController!.camera.zoom, greaterThan(3.3));
      expect(
          map.mapController!.camera.visibleBounds
              .contains(lines.single.points[1]),
          isTrue);
      final previousZoom = map.mapController!.camera.zoom;
      await tester.tap(find.byTooltip('Aumentar zoom'));
      await tester.pumpAndSettle();
      expect(map.mapController!.camera.zoom, greaterThan(previousZoom));
      await tester.tap(find.byTooltip('Centralizar mapa'));
      await tester.pumpAndSettle();
      expect(map.mapController!.camera.zoom, closeTo(previousZoom, .001));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, mobileClient);
  });

  testWidgets('historico nativo mostra contornos, hubs e detalhes da UF',
      (tester) async {
    viewport(tester, const Size(360, 800));
    final geometry = await tester.runAsync(
        () => rootBundle.loadString('assets/geojson/brazil_regions.geojson'));
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: LeafletSurface(
        geometryLoader: () async => geometry!,
        blocked: false,
        config: const {
          'mode': 'history',
          'fitToken': 1,
          'focus': 'Sudeste',
          'regions': [
            {
              'name': 'Sudeste',
              'total': 100,
              'valid': 90,
              'delayed': 9,
              'rate': 10.0,
              'states': [
                {'state': 'SP', 'delayRate': 10.0, 'totalOrders': 100}
              ]
            }
          ],
          'hubs': [
            {
              'name': 'Hub São Paulo',
              'code': 'HUB-SP',
              'city': 'São Paulo',
              'state': 'SP',
              'latitude': -23.55,
              'longitude': -46.63
            }
          ]
        },
      ))));
      await tester.pumpAndSettle();
      expect(find.byType(PolygonLayer<Object>), findsOneWidget,
          reason: tester.allWidgets
              .whereType<Text>()
              .map((widget) => widget.data)
              .join(' / '));
      expect(tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers,
          hasLength(2));
      await tester.tap(find.text('Sudeste · 10.0%'));
      await tester.pumpAndSettle();
      expect(find.textContaining('SP: 10.0%'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, mobileClient);
  });
}
