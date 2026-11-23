import 'package:flutter_test/flutter_test.dart';
import 'package:logipredict_ai/services/simulator_prediction_service.dart';
import 'package:logipredict_ai/services/simulator_scenario.dart';

SimulatorScenario scenario({String destination = '40000-000'}) => SimulatorScenario(
      originCeps: ['01001-000', '01002-000'],
      destinationCep: destination,
      purchaseAt: DateTime(2025, 1, 1),
      dispatchedAt: DateTime(2025, 1, 2),
      estimatedDeliveryAt: DateTime(2025, 1, 8),
      weightKg: 2.5,
      volumeCm3: 120,
      itemsCount: 2,
      price: 100,
      freightValue: 10,
    );

Map<String, dynamic> routeFor(String destination) => {
      'origins': [
        {'cep': '01001000', 'state': 'SP', 'city': 'São Paulo'},
        {'cep': '01002000', 'state': 'SP', 'city': 'São Paulo'},
      ],
      'destination': {'cep': destination, 'state': 'BA', 'city': 'Salvador'},
      'seller_state': 'SP',
      'customer_state': 'BA',
      'distance_km': 1450.5,
      'geolocation_source': 'test',
    };

Map<String, dynamic> response({List<String> warnings = const []}) => {
      'delay_probability': .42,
      'predicted_late': true,
      'threshold': .37,
      'model_version': 'rf-test',
      'source': 'test',
      'synthetic': false,
      'warnings': warnings,
    };

void main() {
  test('monta payload real sem order_id e converte kg para gramas', () async {
    Map<String, dynamic>? sentPayload;
    final service = SimulatorPredictionService(
      routeResolver: ({required originCeps, required destinationCep}) async =>
          routeFor(destinationCep),
      predictionCaller: (payload) async {
        sentPayload = payload;
        return response(warnings: ['Score não calibrado.']);
      },
    );

    final execution = await service.predict(scenario());

    expect(sentPayload, isNotNull);
    expect(sentPayload!.containsKey('order_id'), isFalse);
    expect(sentPayload!['total_weight_g'], 2500);
    expect(sentPayload!['total_volume_cm3'], 120);
    expect(sentPayload!['sellers_count'], 2);
    expect(execution.result.warnings, ['Score não calibrado.']);
  });

  test('resolve múltiplos CEPs e deriva estados/distância da rota atual', () async {
    List<String>? origins;
    String? destination;
    final service = SimulatorPredictionService(
      routeResolver: ({required originCeps, required destinationCep}) async {
        origins = originCeps;
        destination = destinationCep;
        return routeFor(destinationCep);
      },
      predictionCaller: (_) async => response(),
    );

    final execution = await service.predict(scenario(destination: '40000-000'));

    expect(origins, ['01001000', '01002000']);
    expect(destination, '40000000');
    expect(execution.payload['seller_state'], 'SP');
    expect(execution.payload['customer_state'], 'BA');
    expect(execution.payload['distance_km'], 1450.5);
  });

  test('não reutiliza geolocalização: consulta novamente quando CEP muda', () async {
    var calls = 0;
    final service = SimulatorPredictionService(
      routeResolver: ({required originCeps, required destinationCep}) async {
        calls++;
        return {...routeFor(destinationCep), 'distance_km': calls * 10.0};
      },
      predictionCaller: (_) async => response(),
    );

    final base = await service.predict(scenario(destination: '40000-000'));
    final alternative = await service.predict(scenario(destination: '20000-000'));

    expect(calls, 2);
    expect(base.payload['distance_km'], 10);
    expect(alternative.payload['distance_km'], 20);
  });

  test('converte resposta válida e preserva warnings', () async {
    final service = SimulatorPredictionService(
      routeResolver: ({required originCeps, required destinationCep}) async =>
          routeFor(destinationCep),
      predictionCaller: (_) async => response(warnings: ['Aviso A', 'Aviso B']),
    );
    final result = (await service.predict(scenario())).result;
    expect(result.delayProbability, .42);
    expect(result.threshold, .37);
    expect(result.warnings, ['Aviso A', 'Aviso B']);
  });

  test('controla falhas de geolocalização, timeout, 422 e 503', () async {
    Future<void> expectFailure(Object error) async {
      final service = SimulatorPredictionService(
        routeResolver: ({required originCeps, required destinationCep}) async {
          throw error;
        },
        predictionCaller: (_) async => response(),
      );
      await expectLater(service.predict(scenario()), throwsA(isA<SimulatorPredictionException>()));
    }

    await expectFailure(Exception('CEP não encontrado'));
    await expectFailure(Exception('Timeout da geolocalização'));
    await expectFailure(Exception('HTTP 422'));
    await expectFailure(Exception('HTTP 503'));
  });

  test('controla resposta inválida, score inválido e falha do ML', () async {
    Future<Map<String, dynamic>> route({
      required List<String> originCeps,
      required String destinationCep,
    }) async => routeFor(destinationCep);
    final invalid = SimulatorPredictionService(
      routeResolver: route,
      predictionCaller: (_) async => {'invalid': true},
    );
    await expectLater(invalid.predict(scenario()), throwsA(isA<SimulatorPredictionException>()));

    final badScore = SimulatorPredictionService(
      routeResolver: route,
      predictionCaller: (_) async => {...response(), 'delay_probability': 2},
    );
    await expectLater(badScore.predict(scenario()), throwsA(isA<SimulatorPredictionException>()));

    final unavailable = SimulatorPredictionService(
      routeResolver: route,
      predictionCaller: (_) async => throw Exception('Serviço ML indisponível'),
    );
    await expectLater(unavailable.predict(scenario()), throwsA(isA<SimulatorPredictionException>()));
  });
}
