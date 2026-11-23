import 'simulator_result.dart';
import 'simulator_scenario.dart';

class SimulatorComparison {
  const SimulatorComparison({
    required this.base,
    required this.alternative,
    required this.differencePercentagePoints,
    required this.changedFields,
    required this.baseScenario,
    required this.alternativeScenario,
  });

  final SimulatorResult base;
  final SimulatorResult alternative;
  final double differencePercentagePoints;
  final Set<String> changedFields;

  int get baseRemainingDays => _remainingDays(baseScenario);
  int get alternativeRemainingDays => _remainingDays(alternativeScenario);
  int get remainingDaysDifference =>
      alternativeRemainingDays - baseRemainingDays;

  final SimulatorScenario baseScenario;
  final SimulatorScenario alternativeScenario;

  factory SimulatorComparison.fromResults({
    required SimulatorResult base,
    required SimulatorResult alternative,
    required SimulatorScenario baseScenario,
    required SimulatorScenario alternativeScenario,
  }) {
    if (base.modelVersion != alternative.modelVersion) {
      throw const FormatException(
          'Não é possível comparar versões diferentes do modelo.');
    }
    final comparison = SimulatorComparison(
      base: base,
      alternative: alternative,
      differencePercentagePoints:
          (alternative.delayProbability - base.delayProbability) * 100,
      changedFields: baseScenario.changedFieldsComparedTo(alternativeScenario),
      baseScenario: baseScenario,
      alternativeScenario: alternativeScenario,
    );
    return comparison;
  }

  bool get isOnlyEstimatedDeliveryChanged =>
      changedFields.length == 1 &&
      changedFields.contains('estimatedDeliveryAt');

  bool get shouldExplainHigherScore =>
      isOnlyEstimatedDeliveryChanged &&
      alternative.delayProbability > base.delayProbability &&
      alternativeScenario.estimatedDeliveryAt.isAfter(
        baseScenario.estimatedDeliveryAt,
      );

  static int _remainingDays(SimulatorScenario scenario) => DateTime(
          scenario.estimatedDeliveryAt.year,
          scenario.estimatedDeliveryAt.month,
          scenario.estimatedDeliveryAt.day)
      .difference(DateTime(scenario.dispatchedAt.year,
          scenario.dispatchedAt.month, scenario.dispatchedAt.day))
      .inDays;
}
