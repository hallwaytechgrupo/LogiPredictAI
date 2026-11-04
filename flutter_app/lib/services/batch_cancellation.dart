/// Utilitários para cancelamento e resultado de operações em lote.
///
/// [BatchCancellationToken] permite cancelar uma operação em execução.
/// [BatchItemResult] representa o resultado de um item individual.
/// [BatchRunResult] agrega os resultados de todos os itens de um lote.
class BatchCancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

/// Resultado de um item individual processado em lote.
///
/// [I] é o tipo da entrada original.
/// [O] é o tipo do resultado (sucesso ou erro).
class BatchItemResult<I, O> {
  const BatchItemResult({
    required this.input,
    this.value,
    this.error,
  });

  final I input;
  final O? value;
  final Object? error;
}

/// Resultado agregado de uma execução em lote.
///
/// Contém a lista de [BatchItemResult] e o total de itens processados.
class BatchRunResult<I, O> {
  const BatchRunResult(this.items, this.totalCount);

  final List<BatchItemResult<I, O>> items;
  final int totalCount;

  int get skippedCount => totalCount - items.length;
}

Future<BatchRunResult<I, O>> runBatchSequentially<I, O>({
  required List<I> inputs,
  required BatchCancellationToken cancellation,
  required Future<O> Function(I input, int index) process,
  void Function(int completed, List<BatchItemResult<I, O>> items)? onProgress,
}) async {
  final results = <BatchItemResult<I, O>>[];
  for (var index = 0; index < inputs.length; index++) {
    if (cancellation.isCancelled) break;
    final input = inputs[index];
    try {
      final value = await process(input, index);
      results.add(BatchItemResult(input: input, value: value));
    } catch (error) {
      results.add(BatchItemResult(input: input, error: error));
    }
    onProgress?.call(results.length, results);
  }
  return BatchRunResult(List.unmodifiable(results), inputs.length);
}
