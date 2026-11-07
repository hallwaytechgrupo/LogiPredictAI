/// Parseamento de CSV para importação de pedidos em lote.
///
/// [ShipmentCsvService] lê o conteúdo CSV, valida colunas obrigatórias,
/// remove duplicatas e retorna os pedidos prontos para previsão.
/// [ParsedShipmentCsv] contém os pedidos parseados e estatísticas de qualidade.
library;

class ShipmentCsvService {
  const ShipmentCsvService._();

  static ParsedShipmentCsv parseShipments(String content) {
    final records = parseCsv(content.replaceFirst('\uFEFF', ''));
    if (records.length < 2) {
      throw const FormatException(
          'O CSV precisa ter cabeçalho e pelo menos um pedido.');
    }
    final headers = records.first.map((h) => h.trim().toLowerCase()).toList();
    const required = <String>[
      'order_id',
      'origin_zip_code',
      'destination_zip_code',
      'purchase_at',
      'dispatched_at',
      'estimated_delivery_at',
      'seller_state',
      'customer_state',
      'items_count',
      'sellers_count',
      'price',
      'freight_value',
    ];
    final missing = required.where((h) => !headers.contains(h)).toList();
    if (missing.isNotEmpty) {
      throw FormatException(
          'Colunas obrigatórias ausentes: ${missing.join(', ')}.');
    }

    String field(List<String> row, String name) {
      final index = headers.indexOf(name);
      return index < 0 || index >= row.length ? '' : row[index].trim();
    }

    double number(String value, String column, int line,
        {bool allowEmpty = false}) {
      if (allowEmpty && value.isEmpty) return 0;
      final parsed = double.tryParse(value.replaceAll(',', '.'));
      if (parsed == null || !parsed.isFinite) {
        throw FormatException('Linha $line: valor inválido em $column.');
      }
      return parsed;
    }

    DateTime date(String value, String column, int line) {
      final parsed = DateTime.tryParse(value);
      if (parsed == null) {
        throw FormatException(
            'Linha $line: data inválida em $column. Use AAAA-MM-DD ou ISO 8601.');
      }
      return parsed;
    }

    final shipments = <Map<String, dynamic>>[];
    final orderIds = <String>{};
    var duplicateCount = 0;
    var invalidCount = 0;
    final invalidExamples = <String>[];
    for (var i = 1; i < records.length; i++) {
      final row = records[i];
      if (row.every((value) => value.trim().isEmpty)) continue;
      final line = i + 1;
      final id = field(row, 'order_id');
      final originZip = field(row, 'origin_zip_code');
      final destZip = field(row, 'destination_zip_code');
      final sellerState = field(row, 'seller_state').toUpperCase();
      final customerState = field(row, 'customer_state').toUpperCase();
      final purchaseRaw = field(row, 'purchase_at');
      final dispatchedRaw = field(row, 'dispatched_at');
      final estimatedRaw = field(row, 'estimated_delivery_at');
      if (id.isEmpty) {
        invalidCount++;
        if (invalidExamples.length < 5) {
          invalidExamples.add('Linha $line: order_id vazio.');
        }
        continue;
      }
      if (!RegExp(r'^[A-Z]{2}$').hasMatch(sellerState) ||
          !RegExp(r'^[A-Z]{2}$').hasMatch(customerState)) {
        invalidCount++;
        if (invalidExamples.length < 5) {
          invalidExamples.add('Linha $line ($id): UFs inválidas.');
        }
        continue;
      }
      DateTime purchase, dispatched, estimated;
      try {
        purchase = date(purchaseRaw, 'purchase_at', line);
        dispatched = date(dispatchedRaw, 'dispatched_at', line);
        estimated = date(estimatedRaw, 'estimated_delivery_at', line);
      } on FormatException {
        invalidCount++;
        if (invalidExamples.length < 5) {
          invalidExamples.add('Linha $line ($id): data inválida.');
        }
        continue;
      }
      double price, freight;
      int itemsCount, sellersCount;
      try {
        price = number(field(row, 'price'), 'price', line);
        freight = number(field(row, 'freight_value'), 'freight_value', line);
        itemsCount = number(field(row, 'items_count'), 'items_count', line)
            .round();
        sellersCount =
            number(field(row, 'sellers_count'), 'sellers_count', line).round();
      } on FormatException {
        invalidCount++;
        if (invalidExamples.length < 5) {
          invalidExamples.add('Linha $line ($id): valor numérico inválido.');
        }
        continue;
      }
      if (orderIds.contains(id)) {
        duplicateCount++;
        continue;
      }
      if (price < 0 ||
          freight < 0 ||
          itemsCount < 1 ||
          sellersCount < 1 ||
          dispatched.isBefore(purchase) ||
          estimated.isBefore(purchase)) {
        invalidCount++;
        if (invalidExamples.length < 5) {
          invalidExamples.add(
              'Linha $line ($id): despacho/prazo anterior à compra ou valor negativo.');
        }
        continue;
      }
      orderIds.add(id);
      final weightRaw = field(row, 'total_weight_g');
      final volumeRaw = field(row, 'total_volume_cm3');
      final distRaw = field(row, 'distance_km');
      shipments.add({
        'id': id,
        'order_id': id,
        'origin_zip_code': originZip,
        'destination_zip_code': destZip,
        'origin': sellerState,
        'destination': customerState,
        'seller_state': sellerState,
        'customer_state': customerState,
        'purchase_at': purchase,
        'dispatched_at': dispatched,
        'estimated_delivery_at': estimated,
        'weight_g': weightRaw.isEmpty ? 0 : number(weightRaw, 'total_weight_g', line),
        'price': price,
        'freight_value': freight,
        'items_count': itemsCount,
        'sellers_count': sellersCount,
        'total_volume_cm3': volumeRaw.isEmpty
            ? null
            : number(volumeRaw, 'total_volume_cm3', line),
        'distance_km': distRaw.isEmpty
            ? null
            : number(distRaw, 'distance_km', line),
        'days': estimated.difference(dispatched).inDays,
      });
    }
    if (shipments.isEmpty) {
      throw const FormatException(
          'Nenhum pedido válido foi encontrado no CSV.');
    }
    return ParsedShipmentCsv(
      shipments,
      duplicateCount,
      invalidCount: invalidCount,
      invalidExamples: invalidExamples,
    );
  }

  /// Parses comma-separated records, supporting quoted fields and escaped quotes.
  static List<List<String>> parseCsv(String input) {
    final rows = <List<String>>[];
    var row = <String>[];
    var field = StringBuffer();
    var quoted = false;

    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      if (char == '"') {
        if (quoted && i + 1 < input.length && input[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (char == ',' && !quoted) {
        row.add(field.toString());
        field = StringBuffer();
      } else if ((char == '\n' || char == '\r') && !quoted) {
        if (char == '\r' && i + 1 < input.length && input[i + 1] == '\n') {
          i++;
        }
        row.add(field.toString());
        if (row.any((value) => value.trim().isNotEmpty)) rows.add(row);
        row = <String>[];
        field = StringBuffer();
      } else {
        field.write(char);
      }
    }

    row.add(field.toString());
    if (row.any((value) => value.trim().isNotEmpty)) rows.add(row);
    if (quoted) throw const FormatException('O CSV contém aspas não fechadas.');
    return rows;
  }
}

class ParsedShipmentCsv {
  const ParsedShipmentCsv(
    this.shipments,
    this.duplicateCount, {
    this.invalidCount = 0,
    this.invalidExamples = const [],
  });

  final List<Map<String, dynamic>> shipments;
  final int duplicateCount;
  final int invalidCount;
  final List<String> invalidExamples;
}
