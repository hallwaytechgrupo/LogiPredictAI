import 'simulator_prediction_service.dart';
import 'simulator_result.dart';
import 'simulator_scenario.dart';

class SimulatorSensitivityPoint {
  const SimulatorSensitivityPoint({
    required this.remainingDays,
    required this.scenario,
    required this.result,
  });

  final int remainingDays;
  final SimulatorScenario scenario;
  final SimulatorResult result;
}

enum SimulatorSensitivityStatus { initial, loading, success, error, stale }

class SimulatorSensitivityController {
  SimulatorSensitivityController(this.predictionService);

  static const defaultBeforeDays = 5;
  static const defaultAfterDays = 10;
  static const maxPoints = 16;

  final SimulatorPredictionService predictionService;
  SimulatorSensitivityStatus status = SimulatorSensitivityStatus.initial;
  List<SimulatorSensitivityPoint> points = const [];
  SimulatorPredictionException? error;
  String? modelVersion;
  int? selectedStartDay;
  int? selectedEndDay;
  int _token = 0;

  bool get isLoading => status == SimulatorSensitivityStatus.loading;

  void invalidate() {
    _token++;
    if (status == SimulatorSensitivityStatus.success ||
        status == SimulatorSensitivityStatus.loading) {
      status = SimulatorSensitivityStatus.stale;
    }
  }

  Future<List<SimulatorSensitivityPoint>?> analyze({
    required SimulatorScenario baseScenario,
    required int startDay,
    required int endDay,
  }) async {
    final days = _buildDays(startDay, endDay);
    final token = ++_token;
    status = SimulatorSensitivityStatus.loading;
    error = null;
    points = const [];
    modelVersion = null;
    selectedStartDay = startDay;
    selectedEndDay = endDay;

    try {
      final next = <SimulatorSensitivityPoint>[];
      // Sequential execution deliberately keeps pressure on the API low and
      // guarantees no more than one request is active for this analysis.
      for (final remainingDays in days) {
        final scenario = _scenarioForDays(baseScenario, remainingDays);
        final execution = await predictionService.predict(scenario);
        if (token != _token) return null;
        next.add(SimulatorSensitivityPoint(
          remainingDays: remainingDays,
          scenario: scenario,
          result: execution.result,
        ));
        modelVersion = execution.result.modelVersion;
      }
      if (token != _token) return null;
      points = List.unmodifiable(next);
      status = SimulatorSensitivityStatus.success;
      return points;
    } catch (caught) {
      if (token != _token) return null;
      error = caught is SimulatorPredictionException
          ? caught
          : SimulatorPredictionException(caught.toString());
      status = SimulatorSensitivityStatus.error;
      return null;
    }
  }

  static List<int> buildDays(int startDay, int endDay) =>
      _buildDays(startDay, endDay);

  static List<int> _buildDays(int startDay, int endDay) {
    if (startDay < 0 || endDay < startDay) {
      throw const FormatException('Informe um intervalo de prazos válido.');
    }
    final days = [for (var day = startDay; day <= endDay; day++) day];
    if (days.length > maxPoints) {
      throw const FormatException(
          'O intervalo deve conter no máximo 16 prazos.');
    }
    return days;
  }

  static SimulatorScenario scenarioForDays(
          SimulatorScenario baseScenario, int remainingDays) =>
      _scenarioForDays(baseScenario, remainingDays);

  static SimulatorScenario _scenarioForDays(
      SimulatorScenario baseScenario, int remainingDays) {
    if (remainingDays < 0) {
      throw const FormatException('O prazo não pode ser negativo.');
    }
    final dispatched = baseScenario.dispatchedAt;
    final dispatchDate = DateTime(
      dispatched.year,
      dispatched.month,
      dispatched.day,
      dispatched.hour,
      dispatched.minute,
      dispatched.second,
      dispatched.millisecond,
      dispatched.microsecond,
    );
    return baseScenario.copyWith(
      estimatedDeliveryAt: dispatchDate.add(Duration(days: remainingDays)),
    );
  }
}
