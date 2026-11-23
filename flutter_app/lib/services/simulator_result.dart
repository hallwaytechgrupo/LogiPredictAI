class SimulatorResult {
  SimulatorResult({
    required this.delayProbability,
    required this.predictedLate,
    required this.threshold,
    required this.modelVersion,
    required this.source,
    required this.synthetic,
    required List<String> warnings,
  }) : warnings = List.unmodifiable(warnings);

  final double delayProbability;
  final bool predictedLate;
  final double threshold;
  final String modelVersion;
  final String source;
  final bool synthetic;
  final List<String> warnings;

  factory SimulatorResult.fromJson(Map<String, dynamic> json) {
    final probability = _score(json['delay_probability'], 'delay_probability');
    final threshold = _score(json['threshold'], 'threshold');
    final predictedLate = json['predicted_late'];
    if (predictedLate is! bool) {
      throw const FormatException('predicted_late inválido.');
    }
    final modelVersion = json['model_version'];
    final source = json['source'];
    final synthetic = json['synthetic'];
    if (modelVersion is! String || modelVersion.isEmpty ||
        source is! String || source.isEmpty || synthetic is! bool) {
      throw const FormatException('Metadados do modelo inválidos.');
    }
    final rawWarnings = json['warnings'];
    if (rawWarnings is! List) {
      throw const FormatException('warnings inválido.');
    }
    return SimulatorResult(
      delayProbability: probability,
      predictedLate: predictedLate,
      threshold: threshold,
      modelVersion: modelVersion,
      source: source,
      synthetic: synthetic,
      warnings: rawWarnings.map((item) => item.toString()).toList(),
    );
  }

  static double _score(Object? value, String name) {
    if (value is! num) throw FormatException('$name inválido.');
    final score = value.toDouble();
    if (!score.isFinite || score < 0 || score > 1) {
      throw FormatException('$name deve estar entre 0 e 1.');
    }
    return score;
  }
}
