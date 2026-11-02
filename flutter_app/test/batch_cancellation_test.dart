import 'package:flutter_test/flutter_test.dart';
import 'package:logipredict_ai/services/batch_cancellation.dart';

void main() {
  test('cancellation token is safe before start and remains requested', () {
    final token = BatchCancellationToken();
    expect(token.isCancelled, isFalse);
    token.cancel();
    expect(token.isCancelled, isTrue);
    token.cancel();
    expect(token.isCancelled, isTrue);
  });

  test('sequential batch continues after an item error and reports it',
      () async {
    final results = await runBatchSequentially<int, int>(
      inputs: [1, 2, 3],
      cancellation: BatchCancellationToken(),
      process: (value, _) async {
        if (value == 2) throw StateError('transient API error');
        return value * 10;
      },
    );
    expect(results.items.map((item) => item.value), [10, null, 30]);
    expect(results.items[1].error, isA<StateError>());
    expect(results.skippedCount, 0);
  });

  test('cancel stops new sequential items and counts unprocessed orders',
      () async {
    final token = BatchCancellationToken();
    final calls = <int>[];
    final results = await runBatchSequentially<int, int>(
      inputs: [1, 2, 3, 4],
      cancellation: token,
      process: (value, _) async {
        calls.add(value);
        if (value == 2) token.cancel();
        return value;
      },
    );
    expect(calls, [1, 2]);
    expect(results.items, hasLength(2));
    expect(results.skippedCount, 2);
  });
}
