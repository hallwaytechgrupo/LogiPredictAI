import 'package:flutter_test/flutter_test.dart';
import 'package:logipredict_ai/services/dispatch_simulation.dart';
import 'package:logipredict_ai/services/simulator_date_format.dart';

void main() {
  test('formata datas no padrão brasileiro e preserva horário quando informado',
      () {
    expect(SimulatorDateFormat.format(DateTime(2018, 1, 8)), '08/01/18');
    expect(SimulatorDateFormat.format(DateTime(2018, 1, 15)), '15/01/18');
    expect(SimulatorDateFormat.format(DateTime(2018, 2, 3, 14, 30)),
        '03/02/18 14:30');
  });

  test('trata virada de mês e ano e aceita entrada brasileira e ISO', () {
    expect(SimulatorDateFormat.format(DateTime(2020, 1, 1, 8, 5)),
        '01/01/20 08:05');
    expect(SimulatorDateFormat.parse('03/02/18 14:30'),
        DateTime(2018, 2, 3, 14, 30));
    expect(SimulatorDateFormat.parse('2018-02-03T14:30:00'),
        DateTime(2018, 2, 3, 14, 30));
    expect(SimulatorDateFormat.parse('31/02/18'), isNull);
  });

  test('formatação visual não altera a serialização ISO do payload', () {
    final purchase = SimulatorDateFormat.parse('01/01/18 08:00')!;
    final dispatch = SimulatorDateFormat.parse('02/01/18 08:00')!;
    final estimate = SimulatorDateFormat.parse('08/01/18 08:00')!;
    final payload = DispatchSimulation.buildPayload(
      purchaseAt: purchase,
      dispatchedAt: dispatch,
      estimatedDeliveryAt: estimate,
      totalWeightG: 1000,
      itemsCount: 1,
      price: 10,
      freightValue: 2,
      route: {
        'origins': [
          {'cep': '01001000'}
        ],
        'seller_state': 'SP',
        'customer_state': 'BA',
        'distance_km': 100.0,
      },
    );
    expect(payload['purchase_at'], '2018-01-01T08:00:00.000');
    expect(payload['dispatched_at'], '2018-01-02T08:00:00.000');
    expect(payload['estimated_delivery_at'], '2018-01-08T08:00:00.000');
    expect(SimulatorDateFormat.format(estimate), '08/01/18 08:00');
  });
}
