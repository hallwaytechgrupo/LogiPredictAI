import 'package:flutter_test/flutter_test.dart';
import 'package:logipredict_ai/services/logipredict_api.dart';

void main() {
  test('adds order ID as Node API metadata, not as part of ML payload', () {
    final uri = LogiPredictApi.predictionUri(orderId: 'order-123');

    expect(uri.path, '/api/v1/predictions');
    expect(uri.queryParameters, {'order_id': 'order-123'});
  });

  test('keeps the existing individual simulation URL when no order is given',
      () {
    final uri = LogiPredictApi.predictionUri();

    expect(uri.path, '/api/v1/predictions');
    expect(uri.hasQuery, isFalse);
  });
}
