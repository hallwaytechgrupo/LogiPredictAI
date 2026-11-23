import 'dispatch_simulation.dart';
import 'simulator_result.dart';
import 'simulator_scenario.dart';

typedef RouteResolver = Future<Map<String, dynamic>> Function({
  required List<String> originCeps,
  required String destinationCep,
});

typedef PredictionCaller = Future<Map<String, dynamic>> Function(
  Map<String, dynamic> payload,
);

class SimulatorPredictionException implements Exception {
  const SimulatorPredictionException(this.message, {this.stage, this.cause});

  final String message;
  final String? stage;
  final Object? cause;

  @override
  String toString() => stage == null ? message : '$message (etapa: $stage)';
}

class SimulatorPredictionExecution {
  const SimulatorPredictionExecution({
    required this.payload,
    required this.route,
    required this.result,
  });

  final Map<String, dynamic> payload;
  final Map<String, dynamic> route;
  final SimulatorResult result;
}

/// Orquestra uma inferência real para um cenário, sem persistência.
///
/// As dependências são injetadas para que a camada possa ser testada sem
/// backend, banco ou rede. A [predictionCaller] recebe somente o payload ML;
/// não existe parâmetro de order_id neste contrato.
class SimulatorPredictionService {
  const SimulatorPredictionService({
    required this.routeResolver,
    required this.predictionCaller,
  });

  final RouteResolver routeResolver;
  final PredictionCaller predictionCaller;

  Future<SimulatorPredictionExecution> predict(SimulatorScenario scenario) async {
    try {
      scenario.validate();
      if (scenario.purchaseAt.isUtc ||
          scenario.dispatchedAt.isUtc ||
          scenario.estimatedDeliveryAt.isUtc) {
        throw const FormatException(
            'Use datas locais sem fuso, como na base Olist.');
      }

      final route = await routeResolver(
        originCeps: List.unmodifiable(scenario.originCeps),
        destinationCep: scenario.destinationCep,
      );
      final payload = DispatchSimulation.buildPayload(
        purchaseAt: scenario.purchaseAt,
        dispatchedAt: scenario.dispatchedAt,
        estimatedDeliveryAt: scenario.estimatedDeliveryAt,
        totalWeightG: scenario.weightKg * 1000,
        totalVolumeCm3: scenario.volumeCm3,
        itemsCount: scenario.itemsCount,
        price: scenario.price,
        freightValue: scenario.freightValue,
        route: route,
      );

      // Deliberadamente não há order_id: cenários hipotéticos não persistem.
      final response = await predictionCaller(payload);
      final result = SimulatorResult.fromJson(response);
      return SimulatorPredictionExecution(
        payload: Map.unmodifiable(payload),
        route: Map.unmodifiable(route),
        result: result,
      );
    } on SimulatorPredictionException {
      rethrow;
    } on FormatException catch (error) {
      throw SimulatorPredictionException(
        error.message,
        stage: 'validação ou resposta do modelo',
        cause: error,
      );
    } catch (error) {
      throw SimulatorPredictionException(
        _messageFor(error),
        stage: 'geolocalização ou previsão',
        cause: error,
      );
    }
  }

  static String _messageFor(Object error) {
    final text = error.toString();
    if (text.toLowerCase().contains('timeout')) {
      return 'Tempo limite excedido ao consultar a previsão.';
    }
    return text;
  }
}
