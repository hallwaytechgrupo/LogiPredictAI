import 'simulator_comparison.dart';
import 'simulator_prediction_service.dart';
import 'simulator_result.dart';
import 'simulator_scenario.dart';

/// Estado e coordenação dos cenários do simulador.
///
/// O controlador não renderiza widgets e não persiste dados. Cada mutação
/// incrementa [_generation], invalidando respostas de chamadas anteriores.
class SimulatorController {
  SimulatorController(this.predictionService);

  final SimulatorPredictionService predictionService;

  SimulatorScenario? _baseScenario;
  SimulatorScenario? _alternativeScenario;
  SimulatorResult? _baseResult;
  SimulatorResult? _alternativeResult;
  SimulatorPredictionExecution? _baseExecution;
  SimulatorPredictionExecution? _alternativeExecution;
  SimulatorComparison? _comparison;
  SimulatorPredictionException? _baseError;
  SimulatorPredictionException? _alternativeError;
  bool _baseLoading = false;
  bool _alternativeLoading = false;
  int _baseToken = 0;
  int _alternativeToken = 0;
  int _executionId = 0;

  SimulatorScenario? get baseScenario => _baseScenario;
  SimulatorScenario? get alternativeScenario => _alternativeScenario;
  SimulatorResult? get baseResult => _baseResult;
  SimulatorResult? get alternativeResult => _alternativeResult;
  SimulatorPredictionExecution? get baseExecution => _baseExecution;
  SimulatorPredictionExecution? get alternativeExecution => _alternativeExecution;
  SimulatorComparison? get comparison => _comparison;
  SimulatorPredictionException? get baseError => _baseError;
  SimulatorPredictionException? get alternativeError => _alternativeError;
  bool get baseLoading => _baseLoading;
  bool get alternativeLoading => _alternativeLoading;
  bool get isLoading => _baseLoading || _alternativeLoading;
  int get executionId => _executionId;

  void defineBase(SimulatorScenario scenario) {
    _invalidateAll();
    _baseScenario = scenario;
    _alternativeScenario = scenario.copyWith();
  }

  SimulatorScenario createAlternative() {
    final base = _baseScenario;
    if (base == null) {
      throw StateError('Defina o cenário base antes do cenário alternativo.');
    }
    _alternativeToken++;
    _alternativeLoading = false;
    _alternativeScenario = base.copyWith();
    _alternativeResult = null;
    _alternativeExecution = null;
    _alternativeError = null;
    _comparison = null;
    return _alternativeScenario!;
  }

  void updateAlternative(SimulatorScenario scenario) {
    if (_baseScenario == null) {
      throw StateError('Defina o cenário base antes do cenário alternativo.');
    }
    _alternativeToken++;
    _alternativeLoading = false;
    _alternativeScenario = scenario;
    _alternativeResult = null;
    _alternativeError = null;
    _comparison = null;
  }

  Future<SimulatorResult?> executeBasePrediction() async {
    final scenario = _baseScenario;
    if (scenario == null) throw StateError('Cenário base não definido.');
    final token = _beginBaseExecution();
    try {
      final execution = await predictionService.predict(scenario);
      if (token != _baseToken || !identical(_baseScenario, scenario)) return null;
      _baseResult = execution.result;
      _baseExecution = execution;
      _baseError = null;
      return _baseResult;
    } catch (error) {
      if (token != _baseToken || !identical(_baseScenario, scenario)) return null;
      _baseResult = null;
      _baseExecution = null;
      _baseError = _asPredictionException(error);
      return null;
    } finally {
      if (token == _baseToken) _baseLoading = false;
    }
  }

  Future<SimulatorResult?> executeAlternativePrediction() async {
    final scenario = _alternativeScenario;
    if (scenario == null) throw StateError('Cenário alternativo não definido.');
    final token = _beginAlternativeExecution();
    try {
      final execution = await predictionService.predict(scenario);
      if (token != _alternativeToken || !identical(_alternativeScenario, scenario)) {
        return null;
      }
      _alternativeResult = execution.result;
      _alternativeExecution = execution;
      _alternativeError = null;
      return _alternativeResult;
    } catch (error) {
      if (token != _alternativeToken || !identical(_alternativeScenario, scenario)) {
        return null;
      }
      _alternativeResult = null;
      _alternativeExecution = null;
      _alternativeError = _asPredictionException(error);
      return null;
    } finally {
      if (token == _alternativeToken) _alternativeLoading = false;
    }
  }

  SimulatorComparison? compareScenarios() {
    final baseScenario = _baseScenario;
    final alternativeScenario = _alternativeScenario;
    final baseResult = _baseResult;
    final alternativeResult = _alternativeResult;
    if (baseScenario == null || alternativeScenario == null ||
        baseResult == null || alternativeResult == null) {
      _comparison = null;
      return null;
    }
    try {
      _comparison = SimulatorComparison.fromResults(
        base: baseResult,
        alternative: alternativeResult,
        baseScenario: baseScenario,
        alternativeScenario: alternativeScenario,
      );
      return _comparison;
    } on FormatException {
      _comparison = null;
      rethrow;
    }
  }

  void restoreAlternative() {
    final base = _baseScenario;
    if (base == null) return;
    _alternativeToken++;
    _alternativeLoading = false;
    _alternativeScenario = base.copyWith();
    _alternativeResult = null;
    _alternativeExecution = null;
    _alternativeError = null;
    _comparison = null;
  }

  void clearSimulation() {
    _invalidateAll();
    _baseScenario = null;
    _alternativeScenario = null;
  }

  int _beginBaseExecution() {
    final token = ++_baseToken;
    _baseLoading = true;
    _baseError = null;
    _baseResult = null;
    _comparison = null;
    _executionId++;
    return token;
  }

  int _beginAlternativeExecution() {
    final token = ++_alternativeToken;
    _alternativeLoading = true;
    _alternativeError = null;
    _alternativeResult = null;
    _comparison = null;
    _executionId++;
    return token;
  }

  void _invalidatePendingOnly() {
    _baseToken++;
    _alternativeToken++;
    _executionId++;
  }

  void _invalidateAll() {
    _invalidatePendingOnly();
    _baseResult = null;
    _alternativeResult = null;
    _baseExecution = null;
    _alternativeExecution = null;
    _comparison = null;
    _baseError = null;
    _alternativeError = null;
    _baseLoading = false;
    _alternativeLoading = false;
  }

  static SimulatorPredictionException _asPredictionException(Object error) {
    if (error is SimulatorPredictionException) return error;
    return SimulatorPredictionException(error.toString(), cause: error);
  }
}
