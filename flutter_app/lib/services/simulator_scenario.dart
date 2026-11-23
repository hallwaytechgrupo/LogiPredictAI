import 'dispatch_simulation.dart';

/// Dados editáveis de um cenário de previsão.
///
/// Features derivadas (distância, UFs, lead time e calendário) não fazem parte
/// deste modelo: são resolvidas/construídas no momento da inferência.
class SimulatorScenario {
  SimulatorScenario({
    required List<String> originCeps,
    required String destinationCep,
    required this.purchaseAt,
    required this.dispatchedAt,
    required this.estimatedDeliveryAt,
    required this.weightKg,
    this.volumeCm3,
    required this.itemsCount,
    required this.price,
    required this.freightValue,
  })  : originCeps = List.unmodifiable(originCeps.map(DispatchSimulation.normalizeCep)),
        destinationCep = DispatchSimulation.normalizeCep(destinationCep) {
    validate();
  }

  final List<String> originCeps;
  final String destinationCep;
  final DateTime purchaseAt;
  final DateTime dispatchedAt;
  final DateTime estimatedDeliveryAt;
  final double weightKg;
  final double? volumeCm3;
  final int itemsCount;
  final double price;
  final double freightValue;

  int get sellersCount => originCeps.length;

  void validate() {
    if (originCeps.isEmpty || originCeps.length > 100) {
      throw const FormatException('Informe de 1 a 100 CEPs de origem.');
    }
    if (dispatchedAt.isBefore(purchaseAt)) {
      throw const FormatException('O despacho não pode ocorrer antes da compra.');
    }
    if (estimatedDeliveryAt.isBefore(purchaseAt) ||
        estimatedDeliveryAt.isBefore(dispatchedAt)) {
      throw const FormatException(
          'A previsão de entrega deve ser posterior à compra e ao despacho.');
    }
    if (!weightKg.isFinite || weightKg < 0) {
      throw const FormatException('Informe um peso válido.');
    }
    if (volumeCm3 != null && (!volumeCm3!.isFinite || volumeCm3! < 0)) {
      throw const FormatException('Informe um volume válido.');
    }
    if (itemsCount < 1 || itemsCount > 10000) {
      throw const FormatException('Informe de 1 a 10.000 itens.');
    }
    if (sellersCount > itemsCount) {
      throw const FormatException('Há mais vendedores do que itens no pedido.');
    }
    if (!price.isFinite || price < 0 ||
        !freightValue.isFinite || freightValue < 0) {
      throw const FormatException('Confira preço e frete.');
    }
  }

  SimulatorScenario copyWith({
    List<String>? originCeps,
    String? destinationCep,
    DateTime? purchaseAt,
    DateTime? dispatchedAt,
    DateTime? estimatedDeliveryAt,
    double? weightKg,
    Object? volumeCm3 = _unchanged,
    int? itemsCount,
    double? price,
    double? freightValue,
  }) {
    return SimulatorScenario(
      originCeps: originCeps ?? this.originCeps,
      destinationCep: destinationCep ?? this.destinationCep,
      purchaseAt: purchaseAt ?? this.purchaseAt,
      dispatchedAt: dispatchedAt ?? this.dispatchedAt,
      estimatedDeliveryAt: estimatedDeliveryAt ?? this.estimatedDeliveryAt,
      weightKg: weightKg ?? this.weightKg,
      volumeCm3: identical(volumeCm3, _unchanged) ? this.volumeCm3 : volumeCm3 as double?,
      itemsCount: itemsCount ?? this.itemsCount,
      price: price ?? this.price,
      freightValue: freightValue ?? this.freightValue,
    );
  }

  Set<String> changedFieldsComparedTo(SimulatorScenario other) {
    final changed = <String>{};
    if (!_listEquals(originCeps, other.originCeps)) changed.add('originCeps');
    if (destinationCep != other.destinationCep) changed.add('destinationCep');
    if (purchaseAt != other.purchaseAt) changed.add('purchaseAt');
    if (dispatchedAt != other.dispatchedAt) changed.add('dispatchedAt');
    if (estimatedDeliveryAt != other.estimatedDeliveryAt) changed.add('estimatedDeliveryAt');
    if (weightKg != other.weightKg) changed.add('weightKg');
    if (volumeCm3 != other.volumeCm3) changed.add('volumeCm3');
    if (itemsCount != other.itemsCount) changed.add('itemsCount');
    if (price != other.price) changed.add('price');
    if (freightValue != other.freightValue) changed.add('freightValue');
    return Set.unmodifiable(changed);
  }

  static const _unchanged = Object();

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
