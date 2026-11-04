import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:logipredict_ai/services/olist_dataset_api.dart';

void main() {
  test('loads the prepared Olist CSV from the configured API', () async {
    Uri? requested;
    final api = OlistDatasetApi(
      baseUrl: 'https://api.example.test/',
      client: MockClient((request) async {
        requested = request.url;
        return http.Response('order_id,seller_state\norder-1,SP\n', 200,
            headers: {'content-type': 'text/csv'});
      }),
    );
    final csv = await api.loadPreparedCsv();
    expect(
        requested.toString(), 'https://api.example.test/api/v1/datasets/olist');
    expect(csv, contains('order-1,SP'));
  });

  test('reports a missing configured dataset and rejects empty CSV', () async {
    final missing = OlistDatasetApi(
      baseUrl: 'https://api.example.test',
      client: MockClient((_) async => http.Response('{}', 404)),
    );
    await expectLater(missing.loadPreparedCsv(), throwsA(isA<Exception>()));

    final empty = OlistDatasetApi(
      baseUrl: 'https://api.example.test',
      client: MockClient((_) async => http.Response('', 200)),
    );
    await expectLater(empty.loadPreparedCsv(), throwsFormatException);
  });
}
