/// Utilitários para simulação de despacho e construção de payload ML.
///
/// Fornece métodos estáticos para:
/// - Normalização e validação de CEPs.
/// - Construção do payload enviado ao modelo de ML.
/// - Validação de consistência temporal e numérica.
///
/// A classe não é instanciável (construtor privado).
class DispatchSimulation {
  const DispatchSimulation._();

  /// Parseia uma string com CEPs separados por vírgula, ponto e vírgula ou espaço.
  /// Retorna lista de CEPs normalizados (sem hífen).
  static List<String> parseOriginCeps(String input) {
    final values = input
        .split(RegExp(r'[,;\s]+'))
        .where((value) => value.trim().isNotEmpty)
        .map(normalizeCep)
        .toList();
    if (values.isEmpty || values.length > 100) {
      throw const FormatException(
        'Informe de 1 a 100 CEPs de origem, um por vendedor.',
      );
    }
    return values;
  }

  /// Normaliza um CEP removendo o hífen e validando o formato (11 dígitos).
  static String normalizeCep(String input) {
    final value = input.trim();
    if (!RegExp(r'^\d{5}-?\d{3}$').hasMatch(value)) {
      throw FormatException('CEP inválido: $input. Use o formato 00000-000.');
    }
    return value.replaceAll('-', '');
  }

  /// Constrói o payload JSON enviado ao modelo ML para previsão de atraso.
  ///
  /// Valida consistência temporal (compra <= despacho <= entrega estimada)
  /// e verifica que os dados numéricos e de rota estão presentes e válidos.
  static Map<String, dynamic> buildPayload({
    required DateTime purchaseAt,
    required DateTime dispatchedAt,
    required DateTime estimatedDeliveryAt,
    required double totalWeightG,
    double? totalVolumeCm3,
    required int itemsCount,
    required double price,
    required double freightValue,
    required Map<String, dynamic> route,
  }) {
    if (dispatchedAt.isBefore(purchaseAt)) {
      throw const FormatException(
        'O despacho não pode ocorrer antes da compra.',
      );
    }
    if (estimatedDeliveryAt.isBefore(purchaseAt) ||
        estimatedDeliveryAt.isBefore(dispatchedAt)) {
      throw const FormatException(
        'A previsão de entrega deve ser posterior à compra e ao despacho.',
      );
    }
    final origins = route['origins'];
    final sellerState = route['seller_state'];
    final customerState = route['customer_state'];
    final distanceKm = route['distance_km'];
    if (origins is! List ||
        origins.isEmpty ||
        sellerState is! String ||
        customerState is! String ||
        distanceKm is! num ||
        !distanceKm.toDouble().isFinite ||
        distanceKm < 0 ||
        distanceKm > 20050) {
      throw const FormatException(
        'A localização não contém os dados necessários para a previsão.',
      );
    }
    if (!totalWeightG.isFinite ||
        totalWeightG < 0 ||
        (totalVolumeCm3 != null &&
            (!totalVolumeCm3.isFinite || totalVolumeCm3 < 0)) ||
        itemsCount < 1 ||
        itemsCount > 10000 ||
        origins.length > itemsCount ||
        !price.isFinite ||
        price < 0 ||
        !freightValue.isFinite ||
        freightValue < 0) {
      throw const FormatException(
        'Confira peso, volume, quantidade de itens, preço e frete.',
      );
    }
    final payload = <String, dynamic>{
      'purchase_at': _localIso(purchaseAt),
      'dispatched_at': _localIso(dispatchedAt),
      'estimated_delivery_at': _localIso(estimatedDeliveryAt),
      'seller_state': sellerState,
      'customer_state': customerState,
      'distance_km': distanceKm.toDouble(),
      'total_weight_g': totalWeightG,
      'items_count': itemsCount,
      'sellers_count': origins.length,
      'price': price,
      'freight_value': freightValue,
    };
    if (totalVolumeCm3 != null) {
      payload['total_volume_cm3'] = totalVolumeCm3;
    }
    return payload;
  }

  static String _localIso(DateTime value) {
    final local = DateTime(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
      value.second,
    );
    return local.toIso8601String();
  }
}
