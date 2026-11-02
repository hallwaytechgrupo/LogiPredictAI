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
      'seller_state',
      'customer_state',
      'dispatched_at',
      'estimated_delivery_at',
      'total_weight_g',
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
      final sellerState = field(row, 'seller_state').toUpperCase();
      final customerState = field(row, 'customer_state').toUpperCase();
      final dispatched =
          date(field(row, 'dispatched_at'), 'dispatched_at', line);
      final estimated = date(
          field(row, 'estimated_delivery_at'), 'estimated_delivery_at', line);
      final purchaseRaw = field(row, 'purchase_at');
      final purchase = purchaseRaw.isEmpty
          ? dispatched
          : date(purchaseRaw, 'purchase_at', line);
      final weight =
          number(field(row, 'total_weight_g'), 'total_weight_g', line);
      final price = number(field(row, 'price'), 'price', line);
      final freight =
          number(field(row, 'freight_value'), 'freight_value', line);
      if (id.isEmpty ||
          !RegExp(r'^[A-Z]{2}$').hasMatch(sellerState) ||
          !RegExp(r'^[A-Z]{2}$').hasMatch(customerState)) {
        throw FormatException(
            'Linha $line: order_id e UFs válidas (ex.: SP, BA) são obrigatórios.');
      }
      if (orderIds.contains(id)) {
        duplicateCount++;
        continue;
      }
      if (weight < 0 ||
          price < 0 ||
          freight < 0 ||
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
      shipments.add({
        'id': id,
        'origin': sellerState,
        'destination': customerState,
        'seller_state': sellerState,
        'customer_state': customerState,
        'purchase_at': purchase,
        'dispatched_at': dispatched,
        'estimated_delivery_at': estimated,
        'weight_g': weight,
        'price': price,
        'freight_value': freight,
        'items_count': field(row, 'items_count').isEmpty
            ? 1
            : number(field(row, 'items_count'), 'items_count', line).round(),
        'sellers_count': field(row, 'sellers_count').isEmpty
            ? 1
            : number(field(row, 'sellers_count'), 'sellers_count', line)
                .round(),
        'total_volume_cm3': field(row, 'total_volume_cm3').isEmpty
            ? null
            : number(field(row, 'total_volume_cm3'), 'total_volume_cm3', line),
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
