import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logipredict_ai/services/simulator_controller.dart';
import 'package:logipredict_ai/services/simulator_prediction_service.dart';
import 'package:logipredict_ai/services/simulator_scenario.dart';

SimulatorScenario scenario({double weight = 2}) => SimulatorScenario(
      originCeps: ['01001-000'],
      destinationCep: '40000-000',
      purchaseAt: DateTime(2025, 1, 1),
      dispatchedAt: DateTime(2025, 1, 2),
      estimatedDeliveryAt: DateTime(2025, 1, 8),
      weightKg: weight,
      itemsCount: 1,
      price: 100,
      freightValue: 10,
    );

Map<String, dynamic> route() => {
      'origins': [{'cep': '01001000'}],
      'destination': {'cep': '40000000'},
      'seller_state': 'SP',
      'customer_state': 'BA',
      'distance_km': 1450.0,
    };

Map<String, dynamic> response(double score, {String version = 'rf-test'}) => {
      'delay_probability': score,
      'predicted_late': score >= .37,
      'threshold': .37,
      'model_version': version,
      'source': 'test',
      'synthetic': false,
      'warnings': <String>[],
    };

SimulatorController controller({
  Future<Map<String, dynamic>> Function(Map<String, dynamic>)? caller,
}) {
  return SimulatorController(SimulatorPredictionService(
    routeResolver: ({required originCeps, required destinationCep}) async => route(),
    predictionCaller: caller ?? (_) async => response(.2),
  ));
}

void main() {
  test('define base and create alternative without sharing state', () {
    final c = controller();
    final base = scenario();
    c.defineBase(base);
    final alternative = c.createAlternative();
    expect(c.baseScenario, same(base));
    expect(alternative, isNot(same(base)));
    expect(alternative.originCeps, base.originCeps);
  });

  test('update alternative preserves base and invalidates its result', () async {
    final c = controller();
    c.defineBase(scenario());
    await c.executeBasePrediction();
    c.updateAlternative(scenario(weight: 4));
    expect(c.baseScenario!.weightKg, 2);
    expect(c.baseResult, isNotNull);
    expect(c.alternativeScenario!.weightKg, 4);
    expect(c.alternativeResult, isNull);
    expect(c.comparison, isNull);
  });

  test('executes both predictions and compares scores', () async {
    var calls = 0;
    final c = controller(caller: (_) async => response(++calls == 1 ? .2 : .5));
    c.defineBase(scenario());
    c.updateAlternative(scenario(weight: 4));
    await c.executeBasePrediction();
    await c.executeAlternativePrediction();
    final comparison = c.compareScenarios();
    expect(comparison!.differencePercentagePoints, closeTo(30, .001));
    expect(comparison.changedFields, {'weightKg'});
  });

  test('altera a data prevista e atualiza payload, resultado e comparação', () async {
    final payloads = <Map<String, dynamic>>[];
    var calls = 0;
    final c = controller(caller: (payload) async {
      payloads.add(payload);
      return ++calls == 1
          ? response(0.4209054089)
          : response(0.3301332534);
    });
    final base = scenario().copyWith(
      purchaseAt: DateTime(2018, 1, 1, 8),
      dispatchedAt: DateTime(2018, 1, 2, 8),
      estimatedDeliveryAt: DateTime(2018, 1, 8, 8),
    );
    final alternative = base.copyWith(
      estimatedDeliveryAt: DateTime(2018, 1, 15, 8),
    );

    c.defineBase(base);
    await c.executeBasePrediction();
    c.updateAlternative(alternative);
    await c.executeAlternativePrediction();
    final comparison = c.compareScenarios();

    expect(payloads, hasLength(2));
    expect(payloads[0]['estimated_delivery_at'], '2018-01-08T08:00:00.000');
    expect(payloads[1]['estimated_delivery_at'], '2018-01-15T08:00:00.000');
    expect(payloads.every((payload) => !payload.containsKey('order_id')), isTrue);
    expect(base.changedFieldsComparedTo(alternative), {'estimatedDeliveryAt'});
    expect(c.baseResult!.delayProbability, 0.4209054089);
    expect(c.alternativeResult!.delayProbability, 0.3301332534);
    expect(comparison, isNotNull);
    expect(comparison!.base.delayProbability, 0.4209054089);
    expect(comparison.alternative.delayProbability, 0.3301332534);
    expect(comparison.differencePercentagePoints, closeTo(-9.07721556, 0.000001));
  });

  test('restores alternative and clears simulation', () async {
    final c = controller();
    c.defineBase(scenario());
    c.updateAlternative(scenario(weight: 4));
    await c.executeBasePrediction();
    c.restoreAlternative();
    expect(c.alternativeScenario!.weightKg, 2);
    expect(c.alternativeResult, isNull);
    c.clearSimulation();
    expect(c.baseScenario, isNull);
    expect(c.alternativeScenario, isNull);
    expect(c.baseResult, isNull);
  });

  test('keeps failures independent', () async {
    var calls = 0;
    final c = controller(caller: (_) async {
      calls++;
      if (calls == 2) throw const SimulatorPredictionException('alternativa falhou');
      return response(.2);
    });
    c.defineBase(scenario());
    c.updateAlternative(scenario(weight: 4));
    await c.executeBasePrediction();
    await c.executeAlternativePrediction();
    expect(c.baseResult, isNotNull);
    expect(c.alternativeResult, isNull);
    expect(c.alternativeError, isNotNull);
    expect(c.compareScenarios(), isNull);
  });

  test('descarta resposta antiga após nova execução', () async {
    final first = Completer<Map<String, dynamic>>();
    final second = Completer<Map<String, dynamic>>();
    var calls = 0;
    final c = controller(caller: (_) => ++calls == 1 ? first.future : second.future);
    c.defineBase(scenario());
    final oldRun = c.executeBasePrediction();
    c.defineBase(scenario(weight: 4));
    final newRun = c.executeBasePrediction();
    second.complete(response(.8));
    await newRun;
    first.complete(response(.1));
    await oldRun;
    expect(c.baseResult!.delayProbability, .8);
    expect(c.baseScenario!.weightKg, 4);
  });

  test('restauração e limpeza invalidam previsões pendentes', () async {
    final pending = Completer<Map<String, dynamic>>();
    final c = controller(caller: (_) => pending.future);
    c.defineBase(scenario());
    final run = c.executeAlternativePrediction();
    c.restoreAlternative();
    pending.complete(response(.9));
    await run;
    expect(c.alternativeResult, isNull);

    final pendingBase = Completer<Map<String, dynamic>>();
    final c2 = controller(caller: (_) => pendingBase.future);
    c2.defineBase(scenario());
    final baseRun = c2.executeBasePrediction();
    c2.clearSimulation();
    pendingBase.complete(response(.9));
    await baseRun;
    expect(c2.baseResult, isNull);
  });

  test('falha antiga não sobrescreve resultado novo', () async {
    final old = Completer<Map<String, dynamic>>();
    final newResponse = Completer<Map<String, dynamic>>();
    var calls = 0;
    final c = controller(caller: (_) {
      if (++calls == 1) return old.future;
      return newResponse.future;
    });
    c.defineBase(scenario());
    final oldRun = c.executeBasePrediction();
    c.defineBase(scenario(weight: 3));
    final newRun = c.executeBasePrediction();
    newResponse.complete(response(.7));
    await newRun;
    old.completeError(const SimulatorPredictionException('erro antigo'));
    await oldRun;
    expect(c.baseResult!.delayProbability, .7);
    expect(c.baseError, isNull);
  });

  test('versões incompatíveis impedem comparação e não há order_id', () async {
    var calls = 0;
    final c = controller(caller: (_) async => response(
          .2,
          version: ++calls == 1 ? 'v1' : 'v2',
        ));
    c.defineBase(scenario());
    c.updateAlternative(scenario(weight: 3));
    await c.executeBasePrediction();
    await c.executeAlternativePrediction();
    expect(() => c.compareScenarios(), throwsFormatException);
    expect(c.baseResult, isNotNull);
  });
}
