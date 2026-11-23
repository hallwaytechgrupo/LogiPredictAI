import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logipredict_ai/services/simulator_prediction_service.dart';
import 'package:logipredict_ai/services/simulator_scenario.dart';
import 'package:logipredict_ai/services/simulator_sensitivity.dart';

SimulatorScenario sensitivityScenario() => SimulatorScenario(
      originCeps: ['01001-000'],
      destinationCep: '40000-000',
      purchaseAt: DateTime(2025, 1, 1, 9),
      dispatchedAt: DateTime(2025, 1, 2, 14, 30),
      estimatedDeliveryAt: DateTime(2025, 1, 8, 14, 30),
      weightKg: 2,
      volumeCm3: 120,
      itemsCount: 1,
      price: 100,
      freightValue: 10,
    );

Map<String, dynamic> sensitivityRoute() => {
      'origins': [
        {'cep': '01001000'}
      ],
      'destination': {'cep': '40000000'},
      'seller_state': 'SP',
      'customer_state': 'BA',
      'distance_km': 1450.0,
    };

Map<String, dynamic> sensitivityResponse(double score) => {
      'delay_probability': score,
      'predicted_late': score >= .37,
      'threshold': .37,
      'model_version': 'rf-test',
      'source': 'test',
      'synthetic': false,
      'warnings': <String>[],
    };

SimulatorPredictionService sensitivityService(
    Future<Map<String, dynamic>> Function(Map<String, dynamic>) caller) {
  return SimulatorPredictionService(
    routeResolver: ({required originCeps, required destinationCep}) async =>
        sensitivityRoute(),
    predictionCaller: caller,
  );
}

void main() {
  test('gera datas pelo prazo de calendário e preserva os demais atributos',
      () {
    final base = sensitivityScenario();
    final generated = SimulatorSensitivityController.scenarioForDays(base, 5);

    expect(generated.purchaseAt, base.purchaseAt);
    expect(generated.dispatchedAt, base.dispatchedAt);
    expect(generated.estimatedDeliveryAt, DateTime(2025, 1, 7, 14, 30));
    expect(
        generated.estimatedDeliveryAt.difference(DateTime(2025, 1, 2)).inDays,
        5);
    expect(generated.weightKg, base.weightKg);
    expect(generated.volumeCm3, base.volumeCm3);
    expect(generated.itemsCount, base.itemsCount);
    expect(generated.price, base.price);
    expect(generated.freightValue, base.freightValue);
    expect(generated.originCeps, base.originCeps);
    expect(generated.destinationCep, base.destinationCep);
  });

  test('limita o intervalo a 16 pontos e ordena os prazos', () {
    expect(SimulatorSensitivityController.buildDays(3, 5), [3, 4, 5]);
    expect(() => SimulatorSensitivityController.buildDays(0, 16),
        throwsFormatException);
  });

  test('usa scores reais, não inclui order_id e mantém os cenários externos',
      () async {
    final base = sensitivityScenario();
    final scores = <double>[.2, .5, .3];
    final payloads = <Map<String, dynamic>>[];
    final controller = SimulatorSensitivityController(
      sensitivityService((payload) async {
        payloads.add(payload);
        return sensitivityResponse(scores[payloads.length - 1]);
      }),
    );

    final points = await controller.analyze(
      baseScenario: base,
      startDay: 1,
      endDay: 3,
    );

    expect(points!.map((point) => point.remainingDays), [1, 2, 3]);
    expect(points.map((point) => point.result.delayProbability), scores);
    expect(
        payloads.every((payload) => !payload.containsKey('order_id')), isTrue);
    expect(base.estimatedDeliveryAt, DateTime(2025, 1, 8, 14, 30));
    expect(controller.status, SimulatorSensitivityStatus.success);
  });

  test('falha uma análise sem alterar o cenário e reporta erro', () async {
    var calls = 0;
    final controller = SimulatorSensitivityController(
      sensitivityService((_) async {
        calls++;
        if (calls == 2) throw const SimulatorPredictionException('falha');
        return sensitivityResponse(.2);
      }),
    );
    final base = sensitivityScenario();

    final points = await controller.analyze(
      baseScenario: base,
      startDay: 1,
      endDay: 3,
    );

    expect(points, isNull);
    expect(controller.status, SimulatorSensitivityStatus.error);
    expect(controller.error!.message, 'falha');
    expect(base.estimatedDeliveryAt, DateTime(2025, 1, 8, 14, 30));
  });

  test('descarta respostas antigas e marca análise como desatualizada',
      () async {
    final first = Completer<Map<String, dynamic>>();
    final second = Completer<Map<String, dynamic>>();
    var calls = 0;
    final controller = SimulatorSensitivityController(
      sensitivityService((_) => ++calls == 1 ? first.future : second.future),
    );
    final base = sensitivityScenario();

    final oldRun =
        controller.analyze(baseScenario: base, startDay: 1, endDay: 1);
    controller.invalidate();
    expect(controller.status, SimulatorSensitivityStatus.stale);
    final newRun =
        controller.analyze(baseScenario: base, startDay: 2, endDay: 2);
    second.complete(sensitivityResponse(.8));
    await newRun;
    first.complete(sensitivityResponse(.1));
    expect(await oldRun, isNull);
    expect(controller.points.single.remainingDays, 2);
    expect(controller.points.single.result.delayProbability, .8);
  });
}
