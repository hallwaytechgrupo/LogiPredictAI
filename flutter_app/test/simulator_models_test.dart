import 'package:flutter_test/flutter_test.dart';
import 'package:logipredict_ai/services/simulator_comparison.dart';
import 'package:logipredict_ai/services/simulator_result.dart';
import 'package:logipredict_ai/services/simulator_scenario.dart';

SimulatorScenario scenario() => SimulatorScenario(
      originCeps: ['01001-000'],
      destinationCep: '40000-000',
      purchaseAt: DateTime(2025, 1, 1),
      dispatchedAt: DateTime(2025, 1, 2),
      estimatedDeliveryAt: DateTime(2025, 1, 8),
      weightKg: 2,
      itemsCount: 1,
      price: 100,
      freightValue: 10,
    );

SimulatorResult result(double score, {String version = 'rf-test'}) =>
    SimulatorResult.fromJson({
      'delay_probability': score,
      'predicted_late': score >= .37,
      'threshold': .37,
      'model_version': version,
      'source': 'test',
      'synthetic': false,
      'warnings': ['Score não calibrado.'],
    });

void main() {
  test('constrói cenário válido e mantém lista independente', () {
    final origins = ['01001-000'];
    final base = SimulatorScenario(
      originCeps: origins,
      destinationCep: '40000-000',
      purchaseAt: DateTime(2025, 1, 1),
      dispatchedAt: DateTime(2025, 1, 2),
      estimatedDeliveryAt: DateTime(2025, 1, 8),
      weightKg: 2,
      itemsCount: 1,
      price: 100,
      freightValue: 10,
    );
    origins.add('01002-000');
    expect(base.originCeps, ['01001000']);
  });

  test('copia, altera sem mutar o original e restaura', () {
    final base = scenario();
    final alternative = base.copyWith(weightKg: 4);
    expect(base.weightKg, 2);
    expect(alternative.weightKg, 4);
    expect(alternative.copyWith(weightKg: base.weightKg).weightKg, 2);
    expect(alternative.changedFieldsComparedTo(base), {'weightKg'});
  });

  test('rejeita datas inválidas, peso negativo e vendedores incompatíveis', () {
    expect(() => scenario().copyWith(dispatchedAt: DateTime(2024, 1, 1)),
        throwsFormatException);
    expect(() => scenario().copyWith(weightKg: -1), throwsFormatException);
    expect(() => scenario().copyWith(originCeps: ['01001-000', '01002-000']),
        throwsFormatException);
  });

  test('aceita volume ausente e identifica múltiplos campos alterados', () {
    final changed =
        scenario().copyWith(volumeCm3: null, price: 120, freightValue: 12);
    expect(changed.volumeCm3, isNull);
    expect(
        changed.changedFieldsComparedTo(scenario()), {'price', 'freightValue'});
  });

  test('valida scores, preserva warnings e rejeita scores inválidos', () {
    expect(result(.2).warnings, ['Score não calibrado.']);
    expect(() => result(-.1), throwsFormatException);
    expect(
        () => SimulatorResult.fromJson({
              ...{
                'delay_probability': .2,
                'predicted_late': false,
                'threshold': 1.1,
                'model_version': 'v',
                'source': 'test',
                'synthetic': false,
                'warnings': []
              }
            }),
        throwsFormatException);
  });

  test('calcula diferenças positiva, negativa, zero e mudança de classificação',
      () {
    final base = scenario();
    final alt = base.copyWith(weightKg: 3);
    expect(
        SimulatorComparison.fromResults(
                base: result(.2),
                alternative: result(.5),
                baseScenario: base,
                alternativeScenario: alt)
            .differencePercentagePoints,
        closeTo(30, 0.001));
    expect(
        SimulatorComparison.fromResults(
                base: result(.5),
                alternative: result(.2),
                baseScenario: base,
                alternativeScenario: alt)
            .differencePercentagePoints,
        closeTo(-30, 0.001));
    expect(
        SimulatorComparison.fromResults(
                base: result(.2),
                alternative: result(.2),
                baseScenario: base,
                alternativeScenario: alt)
            .differencePercentagePoints,
        0);
    expect(result(.2).predictedLate, isFalse);
    expect(result(.5).predictedLate, isTrue);
  });

  test(
      'calcula prazo disponível e identifica aumento de score com prazo ampliado',
      () {
    final base = scenario();
    final alternative = base.copyWith(
      estimatedDeliveryAt: DateTime(2025, 1, 15),
    );
    final comparison = SimulatorComparison.fromResults(
      base: result(.497),
      alternative: result(.516),
      baseScenario: base,
      alternativeScenario: alternative,
    );

    expect(comparison.baseRemainingDays, 6);
    expect(comparison.alternativeRemainingDays, 13);
    expect(comparison.remainingDaysDifference, 7);
    expect(comparison.changedFields, {'estimatedDeliveryAt'});
    expect(comparison.isOnlyEstimatedDeliveryChanged, isTrue);
    expect(comparison.differencePercentagePoints, closeTo(1.9, .001));
    expect(comparison.shouldExplainHigherScore, isTrue);
  });

  test('não exibe explicação contextual para outros campos ou score menor', () {
    final base = scenario();
    final changedWeight = SimulatorComparison.fromResults(
      base: result(.497),
      alternative: result(.516),
      baseScenario: base,
      alternativeScenario: base.copyWith(weightKg: 3),
    );
    final lowerScore = SimulatorComparison.fromResults(
      base: result(.516),
      alternative: result(.497),
      baseScenario: base,
      alternativeScenario: base.copyWith(
        estimatedDeliveryAt: DateTime(2025, 1, 15),
      ),
    );

    expect(changedWeight.shouldExplainHigherScore, isFalse);
    expect(lowerScore.shouldExplainHigherScore, isFalse);
  });

  test('não compara versões diferentes e não inclui order_id no modelo', () {
    final base = scenario();
    expect(
        () => SimulatorComparison.fromResults(
              base: result(.2),
              alternative: result(.3, version: 'other'),
              baseScenario: base,
              alternativeScenario: base,
            ),
        throwsFormatException);
    expect(base.toString().contains('order_id'), isFalse);
  });
}
