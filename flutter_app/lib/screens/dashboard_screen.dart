/// Dashboard principal com abas para simulação logística, mapa, análise
/// e importação de pedidos.
///
/// Usa `part` directives para dividir o código em:
/// - dashboard_simulator_screen.dart: simulador logístico unificado (previsão + despacho).
/// - dashboard_map_screen.dart: mapa com hubs e pedidos.
/// - dashboard_analytics_screen.dart: análise por UF e região.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_geojson2/flutter_map_geojson2.dart';
import 'package:latlong2/latlong.dart';
import '../services/dispatch_simulation.dart';
import '../services/dispatch_api.dart';
import '../services/logipredict_api.dart';
import '../services/hubs_api.dart';
import '../services/hub_analytics_api.dart';
import '../services/orders_api.dart';
import '../services/orders_geography_api.dart';
import '../services/orders_region_api.dart';
import '../widgets/hub_risk_layer_unavailable.dart';
import '../widgets/logistics_heat_map.dart';
import 'hubs_management_screen.dart';
import 'orders_screen.dart';

part 'dashboard_simulator_screen.dart';
part 'dashboard_map_screen.dart';
part 'dashboard_analytics_screen.dart';

const navy = Color(0xFF0F172A);
const blue = Color(0xFF2563EB);
const muted = Color(0xFF64748B);

class DashboardScreen extends StatefulWidget {
  final bool isDarkMode;
  final VoidCallback onThemeToggle;

  const DashboardScreen(
      {super.key, required this.isDarkMode, required this.onThemeToggle});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // ValueNotifier to trigger OrdersScreen refresh from Simulator or tab switch
  final _ordersRefreshTrigger = ValueNotifier<int>(0);

  bool _isAnalyzing = false;
  List<String> _warnings = [];
  String? _modelVersion;
  List<Map<String, dynamic>> _stateAnalytics = [];
  bool _loadingAnalytics = false;
  String? _analyticsError;
  bool get _isDark => widget.isDarkMode;
  Color get _surface => _isDark ? const Color(0xFF172338) : Colors.white;
  Color get _surfaceAlt =>
      _isDark ? const Color(0xFF202F46) : const Color(0xFFF8FAFC);
  Color get _border =>
      _isDark ? const Color(0xFF33445D) : const Color(0xFFE2E8F0);
  Color get _primaryText => _isDark ? const Color(0xFFE2E8F0) : navy;
  Color get _secondaryText => _isDark ? const Color(0xFFB5C2D4) : muted;
  int _tab = 0;
  final _formKey = GlobalKey<FormState>();
  final _originController = TextEditingController();
  final _destinationController = TextEditingController();
  final _purchaseAtController = TextEditingController();
  final _dispatchedAtController = TextEditingController();
  final _estimatedDeliveryAtController = TextEditingController();
  final _weightController = TextEditingController();
  final _volumeController = TextEditingController();
  final _itemsCountController = TextEditingController();
  final _declaredValueController = TextEditingController();
  final _freightValueController = TextEditingController();
  final HubsApi _hubsApi = HubsApi();
  final HubAnalyticsApi _hubAnalyticsApi = HubAnalyticsApi();
  final OrdersApi _ordersApi = OrdersApi();
  List<LogisticHub> _mapHubs = [];
  bool _loadingMapHubs = true;
  String? _mapHubsError;
  Map<String, HubRiskAggregate> _mapHubRisk = {};
  int _mapHubRiskTotal = 0;
  bool _loadingHubRisk = false;
  String? _hubRiskError;
  bool _showHubRiskLayer = true;
  double? _riskProbability;
  bool? _predictedLate;
  String _riskTitle = 'Aguardando análise';
  String _riskDescription =
      'Preencha os dados do pedido e execute uma simulação com o modelo.';
  double? _lastThreshold;
  Map<String, dynamic>? _currentScenario;
  Map<String, dynamic>? _previousScenario;
  Map<String, dynamic>? _lastAttempt;

  // Dispatch simulation state (unified in simulator screen)
  Map<String, dynamic>? _dispatchResult;
  bool _dispatchLoading = false;
  String? _dispatchError;
  bool _dispatchMapReady = false;

  // Order selection state (select imported order for auto-fill)
  bool _useImportedOrder = false;
  Map<String, dynamic>? _selectedOrder;
  String _orderSearchQuery = '';
  List<Map<String, dynamic>> _orderSearchResults = [];
  bool _searchingOrders = false;
  bool _loadingSelectedOrder = false;
  int _orderSelectionRequest = 0;
  String? _orderSearchError;

  // Order geography map state (legacy, kept for backward compatibility)
  final OrdersGeographyApi _ordersGeographyApi = OrdersGeographyApi();
  List<OrderGeographyRecord> _orderGeographyData = [];
  bool _loadingOrderGeography = false;
  String? _orderGeographyError;
  String? _selectedGeographyState;

  // Region choropleth map state
  final OrdersRegionApi _ordersRegionApi = OrdersRegionApi();
  List<RegionOrderRecord> _regionOrderData = [];
  bool _loadingRegions = false;
  String? _regionError;
  bool _showHubLayer = true;

  @override
  void dispose() {
    _ordersRefreshTrigger.dispose();
    _originController.dispose();
    _destinationController.dispose();
    _purchaseAtController.dispose();
    _dispatchedAtController.dispose();
    _estimatedDeliveryAtController.dispose();
    _weightController.dispose();
    _volumeController.dispose();
    _itemsCountController.dispose();
    _declaredValueController.dispose();
    _freightValueController.dispose();
    _dispatchMapReady = false;
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
    _loadMapHubs();
    _loadRegions();
  }

  Future<void> _loadMapHubs() async {
    setState(() {
      _loadingMapHubs = true;
      _mapHubsError = null;
      _loadingHubRisk = true;
      _hubRiskError = null;
    });
    List<LogisticHub> hubs = _mapHubs;
    String? hubsError;
    Map<String, HubRiskAggregate> risk = _mapHubRisk;
    var riskTotal = _mapHubRiskTotal;
    String? riskError;
    try {
      hubs = await _hubsApi.list(includeInactive: true);
    } catch (e) {
      hubsError = e.toString();
      hubs = [];
    }
    try {
      final response = await _hubAnalyticsApi.list();
      risk = indexHubRiskAggregates(response.data);
      riskTotal = response.total;
    } catch (e) {
      riskError = e.toString();
      risk = {};
      riskTotal = 0;
    }
    if (!mounted) return;
    setState(() {
      _mapHubs = hubs;
      _mapHubsError = hubsError;
      _loadingMapHubs = false;
      _mapHubRisk = risk;
      _mapHubRiskTotal = riskTotal;
      _hubRiskError = riskError;
      _loadingHubRisk = false;
    });
    // Note: the LogisticsHeatMap widget manages its own MapController,
    // so we no longer call _mapController.move/fitCamera here.
  }

  Future<void> _loadAnalytics() async {
    if (!mounted) return;

    setState(() {
      _loadingAnalytics = true;
      _analyticsError = null;
    });

    try {
      final states = await LogiPredictApi.fetchStateAnalytics();

      if (!mounted) return;

      setState(() {
        _stateAnalytics = states;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _analyticsError = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingAnalytics = false;
        });
      }
    }
  }

  void _setHubRiskLayerEnabled(bool enabled) {
    setState(() => _showHubRiskLayer = enabled);
  }

  Future<void> _loadOrderGeography({String? state}) async {
    setState(() {
      _loadingOrderGeography = true;
      _orderGeographyError = null;
    });
    try {
      final response = await _ordersGeographyApi.list(state: state);
      if (!mounted) return;
      setState(() {
        _orderGeographyData = response.data;
        _loadingOrderGeography = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _orderGeographyError = e.toString();
        _loadingOrderGeography = false;
      });
    }
  }

  Future<void> _loadRegions() async {
    setState(() {
      _loadingRegions = true;
      _regionError = null;
    });
    try {
      final response = await _ordersRegionApi.list();
      if (!mounted) return;
      setState(() {
        _regionOrderData = response;
        _loadingRegions = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _regionError = e.toString();
        _loadingRegions = false;
      });
    }
  }

  Future<void> _showRegionDetails(RegionOrderRecord record) async {
    final band = record.riskBand;
    final delayRateText = record.ordersWithValidDates > 0
        ? '${record.delayRate.toStringAsFixed(1)}%'
        : 'Sem dados';
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(record.region),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total de pedidos: ${record.totalOrders}'),
              const SizedBox(height: 4),
              Text('Pedidos com datas válidas: ${record.ordersWithValidDates}'),
              const SizedBox(height: 4),
              Text('Pedidos atrasados: ${record.delayedOrders}'),
              const SizedBox(height: 4),
              Text('Taxa de atraso: $delayRateText'),
              const SizedBox(height: 4),
              Text(
                'Classificação de risco: ${orderRiskLabel(band)}',
                style: TextStyle(
                  color: orderRiskColor(band),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                  'Pedidos sem data de entrega: ${record.ordersWithoutDeliveryDate}'),
              if (record.states.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text('UFs ordenadas por taxa de atraso:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ...record.states.map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${s.state}'),
                          Text(
                            '${s.delayRate.toStringAsFixed(1)}% (${s.riskBand == OrderRiskBand.baixo ? 'baixo' : s.riskBand == OrderRiskBand.medio ? 'médio' : s.riskBand == OrderRiskBand.alto ? 'alto' : s.riskBand == OrderRiskBand.muitoAlto ? 'muito alto' : 'sem dados'})',
                            style: TextStyle(
                              color: orderRiskColor(s.riskBand),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> _showHubDetails(LogisticHub hub) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.local_shipping, size: 22),
            const SizedBox(width: 8),
            Expanded(child: Text(hub.name)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cidade: ${hub.city}'),
              const SizedBox(height: 4),
              Text('UF: ${hub.state}'),
              const SizedBox(height: 4),
              Text(
                'Status: ${hub.status == "active" ? "Ativo" : "Inativo"}',
                style: TextStyle(
                  color: hub.isActive ? const Color(0xFF15803D) : muted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (hub.classification != null &&
                  hub.classification!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Classificação: ${hub.classification}'),
              ],
              if (hub.provisionalCategory != null &&
                  hub.provisionalCategory!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Categoria provisória: ${hub.provisionalCategory}'),
              ],
              if (hub.operatorName != null &&
                  hub.operatorName!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Operador: ${hub.operatorName}'),
              ],
              const SizedBox(height: 10),
              const Text(
                'Nota: Este hub é simulado e não possui relação com os pedidos Olist.',
                style: TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }


  void _simulationInputsChanged() {
    if (_isAnalyzing) return;
    setState(() {
      if (_currentScenario != null) {
        _previousScenario = _currentScenario;
      }
      _currentScenario = null;
      _lastAttempt = null;
      _riskProbability = null;
      _predictedLate = null;
      _riskTitle = 'Parâmetros alterados';
      _riskDescription =
          'Execute uma nova simulação para consultar o modelo com estes dados.';
      _warnings = [];
      _modelVersion = null;
      _lastThreshold = null;
      // Clear dispatch results when inputs change
      _dispatchResult = null;
      _dispatchError = null;
      _dispatchLoading = false;
      _dispatchMapReady = false;
    });
  }

  DateTime? _parseLocalDateTime(String input) =>
      DateTime.tryParse(input.trim().replaceFirst(' ', 'T'));

  String? _requiredDateTime(String? value) {
    if (value == null || value.trim().isEmpty) return 'Informe data e hora.';
    if (_parseLocalDateTime(value) == null) return 'Data/hora inválida.';
    return null;
  }

  double? _parseNumber(String value) =>
      double.tryParse(value.trim().replaceAll(',', '.'));

  Future<void> _chooseDateTime(TextEditingController controller) async {
    final current = _parseLocalDateTime(controller.text) ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;
    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    controller.text =
        selected.toIso8601String().substring(0, 16).replaceFirst('T', ' ');
    _simulationInputsChanged();
  }

  Widget _dateTimeField({
    required TextEditingController controller,
    required String label,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      onTap: _isAnalyzing ? null : () => _chooseDateTime(controller),
      validator: _requiredDateTime,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.calendar_month),
      ),
    );
  }

  Future<void> _analyze() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    late final List<String> originCeps;
    late final String destinationCep;
    try {
      originCeps = DispatchSimulation.parseOriginCeps(_originController.text);
      destinationCep =
          DispatchSimulation.normalizeCep(_destinationController.text);
    } on FormatException catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
      return;
    }

    final purchaseAt = _parseLocalDateTime(_purchaseAtController.text)!;
    final dispatchedAt = _parseLocalDateTime(_dispatchedAtController.text)!;
    final estimatedDeliveryAt =
        _parseLocalDateTime(_estimatedDeliveryAtController.text)!;
    final weightKg = _parseNumber(_weightController.text)!;
    final volumeText = _volumeController.text.trim();
    final volumeCm3 = volumeText.isEmpty ? null : _parseNumber(volumeText);
    final itemsCount = int.tryParse(_itemsCountController.text.trim())!;
    final price = _parseNumber(_declaredValueController.text)!;
    final freightValue = _parseNumber(_freightValueController.text)!;

    setState(() {
      if (_currentScenario != null) {
        _previousScenario = _currentScenario;
      }
      _currentScenario = null;
      _lastAttempt = null;
      _isAnalyzing = true;
      _riskProbability = null;
      _predictedLate = null;
      _riskTitle = 'Resolvendo CEPs';
      _riskDescription = 'Consultando a base geográfica usada no treinamento.';
      _warnings = [];
      _modelVersion = null;
      _lastThreshold = null;
      // Reset dispatch state
      _dispatchResult = null;
      _dispatchError = null;
      _dispatchLoading = true;
      _dispatchMapReady = false;
    });

    // Run prediction and dispatch simulation independently
    final orderId = _selectedOrder?['order_id']?.toString();
    final predictionFuture = _runPrediction(
      originCeps: originCeps,
      destinationCep: destinationCep,
      purchaseAt: purchaseAt,
      dispatchedAt: dispatchedAt,
      estimatedDeliveryAt: estimatedDeliveryAt,
      weightKg: weightKg,
      volumeCm3: volumeCm3,
      itemsCount: itemsCount,
      price: price,
      freightValue: freightValue,
      orderId: orderId,
    );

    // Use the first origin CEP for dispatch simulation
    final dispatchFuture = _runDispatch(
      originCep: originCeps[0],
      destinationCep: destinationCep,
    );

    // Wait for both independently
    final predictionResult = await predictionFuture;
    final dispatchResult = await dispatchFuture;

    if (!mounted) return;

    // Apply prediction result
    if (predictionResult != null) {
      setState(() {
        _currentScenario = predictionResult['scenario'];
        _lastAttempt = predictionResult['lastAttempt'];
        _riskProbability = predictionResult['probability'];
        _predictedLate = predictionResult['predictedLate'];
        _riskTitle = predictionResult['riskTitle'];
        _riskDescription = predictionResult['riskDescription'];
        _modelVersion = predictionResult['modelVersion'];
        _lastThreshold = predictionResult['threshold'];
        _warnings = predictionResult['warnings'];
      });
    }

    // Apply dispatch result
    if (dispatchResult != null) {
      setState(() {
        _dispatchResult = dispatchResult['result'];
        _dispatchError = dispatchResult['error'];
        _dispatchLoading = false;
      });
    } else if (_dispatchLoading) {
      setState(() => _dispatchLoading = false);
    }

    if (mounted) setState(() => _isAnalyzing = false);
  }

  /// Runs the ML prediction and returns the result, or null on error.
  Future<Map<String, dynamic>?> _runPrediction({
    required List<String> originCeps,
    required String destinationCep,
    required DateTime purchaseAt,
    required DateTime dispatchedAt,
    required DateTime estimatedDeliveryAt,
    required double weightKg,
    required double? volumeCm3,
    required int itemsCount,
    required double price,
    required double freightValue,
    String? orderId,
  }) async {
    try {
      final route = await LogiPredictApi.resolveRoute(
        originCeps: originCeps,
        destinationCep: destinationCep,
      );
      final payload = DispatchSimulation.buildPayload(
        purchaseAt: purchaseAt,
        dispatchedAt: dispatchedAt,
        estimatedDeliveryAt: estimatedDeliveryAt,
        totalWeightG: weightKg * 1000,
        totalVolumeCm3: volumeCm3,
        itemsCount: itemsCount,
        price: price,
        freightValue: freightValue,
        route: route,
      );

      final result = await LogiPredictApi.predict(payload, orderId: orderId);
      final probabilityValue = result['delay_probability'];
      final predictedLateValue = result['predicted_late'];
      final thresholdValue = result['threshold'];
      if (probabilityValue is! num ||
          predictedLateValue is! bool ||
          thresholdValue is! num) {
        throw const FormatException(
          'Resposta incompleta: eram esperados score, decisão e limiar do modelo.',
        );
      }
      final probability = probabilityValue.toDouble();
      final threshold = thresholdValue.toDouble();
      if (!probability.isFinite ||
          probability < 0 ||
          probability > 1 ||
          !threshold.isFinite ||
          threshold < 0 ||
          threshold > 1) {
        throw const FormatException(
          'O modelo retornou score ou limiar fora do intervalo de 0 a 1.',
        );
      }
      final warningsRaw = result['warnings'];
      final warnings = warningsRaw is List
          ? warningsRaw.map((item) => item.toString()).toList()
          : <String>[];
      if (result['synthetic'] == true &&
          !warnings
              .any((warning) => warning.toLowerCase().contains('sintético'))) {
        warnings.add(
            'Esta resposta veio de um modelo treinado com dados sintéticos.');
      }

      return {
        'scenario': {'payload': payload, 'route': route, 'response': result},
        'lastAttempt': null,
        'probability': probability,
        'predictedLate': predictedLateValue,
        'riskTitle': predictedLateValue
            ? 'O modelo classificou risco de atraso'
            : 'O modelo não classificou atraso acima do limiar',
        'riskDescription': 'Estimativa de risco, não garantia de atraso.',
        'modelVersion': result['model_version']?.toString(),
        'threshold': threshold,
        'warnings': warnings,
      };
    } catch (error) {
      // Store error in state directly
      if (mounted) {
        setState(() {
          _riskProbability = null;
          _predictedLate = null;
          _riskTitle = 'Previsão indisponível';
          _riskDescription = error.toString();
        });
      }
      return null;
    }
  }

  /// Runs the dispatch simulation and returns the result, or null on error.
  Future<Map<String, dynamic>?> _runDispatch({
    required String originCep,
    required String destinationCep,
  }) async {
    try {
      final api = DispatchApi();
      final response = await api.simulate(originCep, destinationCep);
      return {
        'result': response['data'],
        'error': null,
      };
    } catch (error) {
      return {
        'result': null,
        'error': error.toString(),
      };
    }
  }

  // ===== Order Selection Methods =====

  /// Searches for orders by query string.
  Future<void> _searchOrders() async {
    if (_orderSearchQuery.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _orderSearchResults = [];
          _orderSearchError = null;
        });
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _searchingOrders = true;
      _orderSearchError = null;
    });

    try {
      final response = await _ordersApi.listOrders(
        query: _orderSearchQuery.trim(),
        source: 'operational',
        perPage: 20,
      );
      final data = response['data'] as List? ?? [];
      if (!mounted) return;
      setState(() {
        _orderSearchResults = data.whereType<Map<String, dynamic>>().toList();
        _searchingOrders = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _orderSearchError = error.toString();
        _searchingOrders = false;
      });
    }
  }

  /// Formats a raw CEP (01001000) to display format (01001-000).
  String _formatCep(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 8) {
      return '${digits.substring(0, 5)}-${digits.substring(5)}';
    }
    return raw;
  }

  /// Formats an ISO datetime to the picker display format (YYYY-MM-DD HH:MM).
  String _formatDateTime(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final parsed = DateTime.tryParse(raw.trim().replaceFirst(' ', 'T'));
    if (parsed == null) return raw.trim();
    return parsed.toIso8601String().substring(0, 16).replaceFirst('T', ' ');
  }

  Future<void> _selectOrder(Map<String, dynamic> order) async {
    final request = ++_orderSelectionRequest;
    setState(() {
      _loadingSelectedOrder = true;
      _orderSearchError = null;
    });
    try {
      final details = await _ordersApi.getOrder(order['order_id'].toString());
      if (!mounted || request != _orderSelectionRequest) return;
      _fillFormFromOrder(details);
    } catch (error) {
      if (!mounted || request != _orderSelectionRequest) return;
      setState(() => _orderSearchError = error.toString());
    } finally {
      if (mounted && request == _orderSelectionRequest) {
        setState(() => _loadingSelectedOrder = false);
      }
    }
  }

  /// Fills every field, including empty values, from the complete order.
  void _fillFormFromOrder(Map<String, dynamic> order) {
    // Fill origin CEP (formatted with dash)
    final originZip = order['origin_zip_code']?.toString().trim();
    _originController.text = _formatCep(originZip ?? '');

    // Fill destination CEP (formatted with dash)
    final destZip = order['destination_zip_code']?.toString().trim();
    _destinationController.text = _formatCep(destZip ?? '');

    // Fill dates (formatted for picker display)
    final purchaseAt = order['purchase_at']?.toString().trim();
    _purchaseAtController.text = _formatDateTime(purchaseAt);

    final dispatchedAt = order['dispatched_at']?.toString().trim();
    _dispatchedAtController.text = _formatDateTime(dispatchedAt);

    final estimatedDeliveryAt = order['estimated_delivery_at']?.toString().trim();
    _estimatedDeliveryAtController.text = _formatDateTime(estimatedDeliveryAt);

    // Fill numeric fields
    final weightG = _parseNumber(order['total_weight_g']?.toString() ?? '');
    _weightController.text = weightG == null ? '' : (weightG / 1000).toString();

    final volumeCm3 = order['total_volume_cm3'];
    _volumeController.text = volumeCm3?.toString() ?? '';

    final itemsCount = order['items_count'];
    _itemsCountController.text = itemsCount?.toString() ?? '';

    final price = order['price'];
    _declaredValueController.text = price?.toString() ?? '';

    final freightValue = order['freight_value'];
    _freightValueController.text = freightValue?.toString() ?? '';

    // Clear previous simulation results
    setState(() {
      _selectedOrder = order;
      _currentScenario = null;
      _lastAttempt = null;
      _riskProbability = null;
      _predictedLate = null;
      _riskTitle = 'Pedido selecionado';
      _riskDescription = 'Dados carregados do pedido ${order['order_id']}. Execute a simulação para obter resultados.';
      _warnings = [];
      _modelVersion = null;
      _lastThreshold = null;
      _dispatchResult = null;
      _dispatchError = null;
      _dispatchLoading = false;
      _dispatchMapReady = false;
      _orderSearchResults = [];
      _orderSearchQuery = '';
    });
  }

  /// Clears the selected order and returns to manual mode.
  void _clearSelectedOrder() {
    _orderSelectionRequest++;
    setState(() {
      _loadingSelectedOrder = false;
      _useImportedOrder = false;
      _selectedOrder = null;
      _orderSearchQuery = '';
      _orderSearchResults = [];
      _searchingOrders = false;
      _orderSearchError = null;
    });
  }

  /// Toggles between manual and imported order mode.
  void _toggleOrderSelectionMode(bool value) {
    if (value) {
      setState(() {
        _useImportedOrder = true;
        _selectedOrder = null;
        _orderSearchResults = [];
      });
    } else {
      _clearSelectedOrder();
    }
  }

  /// Attempts to associate an order without a hub to the nearest hub.
  Future<void> _associateOrderHub(Map<String, dynamic> order) async {
    final destZip = order['destination_zip_code']?.toString()?.trim();
    if (destZip == null || destZip.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pedido sem CEP de destino para associação.')),
        );
      }
      return;
    }

    // Show loading indicator
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: Card(child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Buscando hub mais próximo...'),
              ],
            ),
          )),
        ),
      );
    }

    try {
      final api = DispatchApi();
      final response = await api.nearestHub(cep: destZip);

      // API returns: { data: { cep, location, hub: {id, code, name, ...}, distance_km } }
      final data = response['data'] as Map<String, dynamic>?;
      final hub = data?['hub'] as Map<String, dynamic>?;

      if (hub != null && hub['id'] != null) {
        await _ordersApi.setHub(order['order_id'].toString(), hub['id'].toString());
        if (mounted) {
          Navigator.of(context).pop(); // Close loading dialog
          setState(() {
            // Update the selected order with full hub info
            _selectedOrder = {
              ...order,
              'hub_id': hub['id'],
              'hub': hub,
            };
          });
          final hubName = hub['name']?.toString() ?? hub['code']?.toString() ?? 'Hub';
          final distance = data?['distance_km']?.toString() ?? '';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$hubName associado ao pedido (${distance} km).'),
              backgroundColor: Colors.green,
            ),
          );
          // Refresh OrdersScreen so the updated hub appears immediately
          _ordersRefreshTrigger.value++;
        }
      } else {
        if (mounted) {
          Navigator.of(context).pop(); // Close loading dialog
          // Provide specific error based on response
          String errorMessage = 'Nenhum hub encontrado para o CEP de destino.';
          final errorType = response['error']?.toString();
          if (errorType == 'CEP_NOT_FOUND') {
            errorMessage = 'CEP ${destZip} não encontrado na base geográfica.';
          } else if (errorType == 'NO_HUBS_AVAILABLE') {
            errorMessage = 'Nenhum hub ativo e aprovado disponível no sistema.';
          } else if (errorType == 'NO_ELIGIBLE_HUBS') {
            errorMessage = 'Nenhum hub com coordenadas válidas encontrado para esta região.';
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errorMessage)),
          );
        }
      }
    } catch (error) {
      if (mounted) {
        if (Navigator.canPop(context)) {
          Navigator.of(context).pop(); // Close loading dialog
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao associar hub: ${error.toString()}'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  /// Order selection widget: toggle, search, and results.
  Widget _buildOrderSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.receipt_long, size: 18, color: blue),
            const SizedBox(width: 8),
            const Text(
              'Utilizar pedido importado',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const Spacer(),
            Switch(
              value: _useImportedOrder,
              onChanged: _isAnalyzing || _loadingSelectedOrder ? null : _toggleOrderSelectionMode,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Selecione um pedido já importado para carregar automaticamente os dados do formulário.',
          style: TextStyle(fontSize: 11, color: _secondaryText),
        ),
        if (_useImportedOrder) ...[
          const SizedBox(height: 12),
          const Divider(height: 16),
          if (_selectedOrder != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Pedido: ${_selectedOrder!['order_id']}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _isAnalyzing ? null : _clearSelectedOrder,
                        child: const Text('Limpar', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'CEP origem: ${_formatCep(_selectedOrder!['origin_zip_code']?.toString() ?? 'N/A')} | '
                    'CEP destino: ${_formatCep(_selectedOrder!['destination_zip_code']?.toString() ?? 'N/A')}',
                    style: TextStyle(fontSize: 12, color: _secondaryText),
                  ),
                  if ((_selectedOrder!['hub_id'] ?? '').toString().isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber, color: Colors.orange, size: 16),
                          const SizedBox(width: 6),
                          const Text(
                            'Sem hub associado. ',
                            style: TextStyle(color: Colors.orange, fontSize: 12),
                          ),
                          TextButton(
                            onPressed: () => _associateOrderHub(_selectedOrder!),
                            child: const Text('Associar agora', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  if ((_selectedOrder!['hub_id'] ?? '').toString().isNotEmpty) ...() {
                    final hub = _selectedOrder!['hub'] as Map<String, dynamic>?;
                    final hubCode = hub?['code']?.toString() ?? _selectedOrder!['hub_id'].toString();
                    return [
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Hub: $hubCode',
                          style: TextStyle(fontSize: 12, color: _secondaryText),
                        ),
                      ),
                    ];
                  }(),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          TextFormField(
            initialValue: _orderSearchQuery,
            decoration: InputDecoration(
              labelText: 'Pesquisar por order_id',
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              isDense: true,
            ),
            onChanged: (value) {
              setState(() => _orderSearchQuery = value);
              _searchOrders();
            },
            enabled: !_isAnalyzing && !_loadingSelectedOrder,
          ),
          if (_searchingOrders)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          if (_loadingSelectedOrder)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Carregando dados do pedido...'),
                ],
              ),
            ),
          if (_orderSearchError != null && !_searchingOrders)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _orderSearchError!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
          if (_orderSearchResults.isNotEmpty && !_searchingOrders) ...[
            const SizedBox(height: 8),
            Text(
              '${_orderSearchResults.length} pedido(s) encontrado(s)',
              style: TextStyle(fontSize: 11, color: _secondaryText),
            ),
            const SizedBox(height: 4),
            ..._orderSearchResults.take(10).map((order) {
              final orderId = order['order_id']?.toString() ?? '';
              final originZip = order['origin_zip_code']?.toString() ?? '';
              final destZip = order['destination_zip_code']?.toString() ?? '';
              final hubObj = order['hub'] as Map<String, dynamic>?;
              final hubCode = hubObj?['code']?.toString() ?? '';
              final hubId = order['hub_id']?.toString() ?? '';
              final hasHub = hubId.isNotEmpty;
              final hubLabel = hubCode.isNotEmpty ? hubCode : hubId;
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _isAnalyzing || _loadingSelectedOrder ? null : () => _selectOrder(order),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: _border),
                      borderRadius: BorderRadius.circular(8),
                      color: _surfaceAlt,
                    ),
                    margin: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(Icons.receipt_long, size: 18,
                            color: hasHub ? Colors.green : Colors.orange),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(orderId,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w500, fontSize: 13)),
                              Text(
                                'Origem: ${_formatCep(originZip)} → Destino: ${_formatCep(destZip)}'
                                '${hasHub ? ' | Hub: $hubLabel' : ' | Sem hub'}',
                                style: TextStyle(fontSize: 11, color: _secondaryText),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, size: 18, color: muted),
                      ],
                    ),
                  ),
                ),
              );
            }),
            if (_orderSearchResults.length > 10)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Mostrando 10 de ${_orderSearchResults.length}. Refine a pesquisa.',
                  style: TextStyle(fontSize: 11, color: _secondaryText),
                ),
              ),
          ],
          if (_orderSearchResults.isEmpty &&
              !_searchingOrders &&
              _orderSearchQuery.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Nenhum pedido encontrado para "$_orderSearchQuery".',
                style: TextStyle(fontSize: 12, color: _secondaryText),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ],
    );
  }

  Color get _riskColor {
    if (_predictedLate == null) return _secondaryText;
    return _predictedLate! ? const Color(0xFFDC2626) : const Color(0xFF059669);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildSimulator(),
      _buildMapPage(),
      OrdersScreen(refreshTrigger: _ordersRefreshTrigger),
      _buildAnalyticsPage(),
      const HubsManagementScreen(),
    ];
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: blue,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.local_shipping, size: 22),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('LogiPredict AI',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 19)),
                  Text('Módulo B2B Prescritivo',
                      style: TextStyle(fontSize: 11, color: Color(0xFFBFDBFE))),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (MediaQuery.sizeOf(context).width > 650)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Row(
                children: [
                  Icon(Icons.business, size: 17, color: Color(0xFFCBD5E1)),
                  SizedBox(width: 6),
                  Text('E-commerce BR', style: TextStyle(fontSize: 12)),
                  SizedBox(width: 14),
                  Icon(Icons.circle, size: 9, color: Color(0xFF34D399)),
                  SizedBox(width: 5),
                  Text(
                    'Modelo v1.4 Ativo',
                    style: TextStyle(fontSize: 12, color: Color(0xFF6EE7B7)),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          _buildNavigation(),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1400),
                child: IndexedStack(index: _tab, children: pages),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        key: const ValueKey('theme-toggle'),
        mini: true,
        onPressed: widget.onThemeToggle,
        tooltip: widget.isDarkMode ? 'Ativar modo claro' : 'Ativar modo escuro',
        child: Icon(widget.isDarkMode ? Icons.light_mode : Icons.dark_mode,
            size: 17),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildNavigation() {
    const labels = [
      'Simulador Logístico',
      'Mapa de Calor Logístico',
      'Pedidos',
      'Analytics & KPIs',
      'Gestão de Hubs',
    ];
    const icons = [
      Icons.calculate_outlined,
      Icons.map_outlined,
      Icons.receipt_long_outlined,
      Icons.show_chart,
      Icons.warehouse_outlined,
    ];
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(labels.length, (i) {
            final selected = _tab == i;
            return InkWell(
              onTap: () {
                final wasOnMap = _tab == 1;
                final wasOnOrders = _tab == 2;
                setState(() => _tab = i);
                if (i == 1 &&
                    !wasOnMap &&
                    !_loadingMapHubs &&
                    !_loadingHubRisk) {
                  _loadMapHubs();
                }
                // Refresh OrdersScreen when navigating to it
                if (i == 2 && !wasOnOrders) {
                  _ordersRefreshTrigger.value++;
                }
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: selected ? blue : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(icons[i], size: 18, color: selected ? blue : muted),
                    const SizedBox(width: 8),
                    Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? blue : _secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    String? helper,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    ValueChanged<String>? onChanged,
    bool enabled = true,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label, helperText: helper),
      keyboardType: keyboardType,
      validator: validator,
      onChanged: onChanged,
      enabled: enabled,
    );
  }

  Widget _card({
    required Widget child,
    Color? color,
    Color? borderColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color ?? _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor ?? _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isDark ? .18 : .04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const _SectionTitle({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: blue, size: 21),
        const SizedBox(width: 9),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? const Color(0xFFE2E8F0) : navy,
              ),
            ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? const Color(0xFFB5C2D4) : muted,
                  ),
                ),
              ),
          ]),
        ),
      ],
    );
  }
}
