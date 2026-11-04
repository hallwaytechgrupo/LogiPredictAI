import 'package:flutter_test/flutter_test.dart';
import 'package:logipredict_ai/services/dispatch_simulation.dart';

void main() {
  test('normalizes the origin CEP list without losing CEP digits', () {
    expect(
      DispatchSimulation.parseOriginCeps('01037-000, 01046-000'),
      ['01037000', '01046000'],
    );
  });

  test('builds only model contract fields and reflects changed inputs', () {
    final route = {
      'origins': [
        {'cep': '01037000'},
      ],
      'seller_state': 'SP',
      'customer_state': 'BA',
      'distance_km': 1450.5,
    };
    final baseline = DispatchSimulation.buildPayload(
      purchaseAt: DateTime(2025, 1, 2, 8),
      dispatchedAt: DateTime(2025, 1, 3, 10),
      estimatedDeliveryAt: DateTime(2025, 1, 8),
      totalWeightG: 2500,
      itemsCount: 1,
      price: 350,
      freightValue: 35,
      route: route,
    );
    final changed = DispatchSimulation.buildPayload(
      purchaseAt: DateTime(2025, 1, 2, 8),
      dispatchedAt: DateTime(2025, 1, 3, 10),
      estimatedDeliveryAt: DateTime(2025, 1, 9),
      totalWeightG: 3000,
      itemsCount: 1,
      price: 350,
      freightValue: 35,
      route: route,
    );

    expect(baseline['seller_state'], 'SP');
    expect(baseline['customer_state'], 'BA');
    expect(baseline['distance_km'], 1450.5);
    expect(baseline['total_weight_g'], 2500);
    expect(baseline['sellers_count'], 1);
    expect(baseline.containsKey('total_volume_cm3'), isFalse);
    expect(changed['total_weight_g'], 3000);
    expect(changed['estimated_delivery_at'],
        isNot(baseline['estimated_delivery_at']));
    expect(changed.keys.toSet(), baseline.keys.toSet());
    expect(
      baseline.keys.toSet(),
      {
        'purchase_at',
        'dispatched_at',
        'estimated_delivery_at',
        'seller_state',
        'customer_state',
        'distance_km',
        'total_weight_g',
        'items_count',
        'sellers_count',
        'price',
        'freight_value',
      },
    );
  });

  test('does not build a request with unresolved locations or invalid dates',
      () {
    expect(
      () => DispatchSimulation.buildPayload(
        purchaseAt: DateTime(2025, 1, 2),
        dispatchedAt: DateTime(2025, 1, 3),
        estimatedDeliveryAt: DateTime(2025, 1, 8),
        totalWeightG: 100,
        itemsCount: 1,
        price: 1,
        freightValue: 0,
        route: const {},
      ),
      throwsFormatException,
    );
    expect(
      () => DispatchSimulation.normalizeCep('1234-567'),
      throwsFormatException,
    );
  });
}
