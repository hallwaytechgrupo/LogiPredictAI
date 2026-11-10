import 'package:flutter_test/flutter_test.dart';
import 'package:logipredict_ai/services/shipment_csv_service.dart';

void main() {
  group('ShipmentCsvService.parseCsv', () {
    test('parses quoted fields, commas, escaped quotes, and CRLF', () {
      final rows = ShipmentCsvService.parseCsv(
        'order_id,customer\r\n1,"Salvador, BA"\r\n2,"Loja ""A"""',
      );

      expect(rows, [
        ['order_id', 'customer'],
        ['1', 'Salvador, BA'],
        ['2', 'Loja "A"'],
      ]);
    });

    test('rejects unclosed quoted fields', () {
      expect(
        () => ShipmentCsvService.parseCsv('order_id\n"1'),
        throwsFormatException,
      );
    });

    test('detects semicolons and preserves decimal commas and quoted separators', () {
      expect(
        ShipmentCsvService.parseCsv('order_id;price;customer\r\n1;89,90;"São Paulo; SP"'),
        [['order_id', 'price', 'customer'], ['1', '89,90', 'São Paulo; SP']],
      );
      expect(
        ShipmentCsvService.parseCsv('order_id,customer\n1,"São Paulo; SP"'),
        [['order_id', 'customer'], ['1', 'São Paulo; SP']],
      );
    });
  });

  group('ShipmentCsvService.parseShipments', () {
    const csv =
        'order_id,seller_state,customer_state,purchase_at,dispatched_at,estimated_delivery_at,total_weight_g,price,freight_value,items_count,sellers_count,total_volume_cm3\n';

    test('normalizes prepared Olist rows and ignores duplicate order IDs', () {
      final parsed = ShipmentCsvService.parseShipments(
        '${csv}order-1,SP,BA,2018-01-01,2018-01-02,2018-01-10,250,20,5,1,1,\n'
        'order-1,SP,BA,2018-01-01,2018-01-02,2018-01-10,250,20,5,1,1,\n',
      );
      expect(parsed.shipments, hasLength(1));
      expect(parsed.shipments.single['id'], 'order-1');
      expect(parsed.shipments.single['seller_state'], 'SP');
      expect(parsed.duplicateCount, 1);
    });

    test('operational import requires the CEP columns', () {
      expect(
        () => ShipmentCsvService.parseShipments(
          '${csv}order-1,SP,BA,2018-01-01,2018-01-02,2018-01-10,250,20,5,1,1,\n',
          requireZipCodes: true,
        ),
        throwsFormatException,
      );
    });

    test('allows an Olist promised date earlier than actual dispatch', () {
      final parsed = ShipmentCsvService.parseShipments(
        '${csv}late-order,SP,BA,2017-09-18 14:31:30,2017-10-06 17:50:03,2017-09-28 00:00:00,525,109.9,8.96,1,1,\n',
      );
      expect(parsed.shipments.single['id'], 'late-order');
      expect(
        (parsed.shipments.single['estimated_delivery_at'] as DateTime)
            .isBefore(parsed.shipments.single['dispatched_at'] as DateTime),
        isTrue,
      );
    });

    test('skips and reports rows the ML schema cannot accept', () {
      final parsed = ShipmentCsvService.parseShipments(
        '${csv}valid-order,SP,BA,2017-09-18 14:31:30,2017-10-06 17:50:03,2017-09-28 00:00:00,525,109.9,8.96,1,1,\n'
        'invalid-order,SP,BA,2018-01-03,2018-01-02,2018-01-10,250,20,5,1,1,\n',
      );
      expect(parsed.shipments, hasLength(1));
      expect(parsed.shipments.single['id'], 'valid-order');
      expect(parsed.invalidCount, 1);
      expect(parsed.invalidExamples.single, contains('invalid-order'));
    });

    test('rejects empty, invalid-header, and malformed shipment data', () {
      expect(
          () => ShipmentCsvService.parseShipments(''), throwsFormatException);
      expect(() => ShipmentCsvService.parseShipments('wrong,header\na,b'),
          throwsFormatException);
      expect(
        () => ShipmentCsvService.parseShipments(
          '${csv}order-1,SP,BA,2018-01-01,2018-01-02,2018-01-10,bad,20,5,1,1,\n',
        ),
        throwsFormatException,
      );
      expect(
        () => ShipmentCsvService.parseShipments(
          '${csv}order-1,SP,BA,2018-01-03,2018-01-02,2018-01-01,250,20,5,1,1,\n',
        ),
        throwsFormatException,
      );
    });
  });
}
