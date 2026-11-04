/// Dashboard principal com abas para simulação, mapa, análise e importação.
///
/// Usa `part` directives para dividir o código em:
/// - dashboard_simulator_screen.dart: simulação de despacho individual.
/// - dashboard_map_screen.dart: mapa com hubs e pedidos.
/// - dashboard_analytics_screen.dart: análise por UF e região.
/// - dashboard_batch_screen.dart: importação e previsão em lote.
library;

import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_geojson2/flutter_map_geojson2.dart';
import 'package:latlong2/latlong.dart';
import '../services/dispatch_simulation.dart';
import '../services/logipredict_api.dart';
import '../services/hubs_api.dart';
import '../services/hub_analytics_api.dart';
import '../services/orders_api.dart';
import '../services/olist_dataset_api.dart';
import '../services/batch_cancellation.dart';
import '../services/batch_prediction_api.dart';
import '../services/shipment_csv_service.dart';
import '../widgets/order_hub_selector.dart';
import '../services/orders_geography_api.dart';
import '../services/orders_region_api.dart';
import '../widgets/hub_risk_layer_unavailable.dart';
import 'hubs_management_screen.dart';
import 'orders_management_screen.dart';

part 'dashboard_simulator_screen.dart';
part 'dashboard_map_screen.dart';
part 'dashboard_batch_screen.dart';
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
  final MapController _mapController = MapController();
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
  bool _isBatchAnalyzing = false;
  BatchCancellationToken _batchCancellation = BatchCancellationToken();
  bool _batchIsOlist = false;
  String? _batchDemoHubId;
  int _batchSkipped = 0;
  int _batchExistingCount = 0;
  int _batchDemoAssignedCount = 0;
  int _batchPreservedHubCount = 0;
  String _batchPhase = '';
  List<String> _batchAlerts = [];
  int _batchCompleted = 0;
  int _batchTotal = 0;
  String? _batchError;
  String? _batchFileName;
  List<Map<String, dynamic>> _batchShipments = [];
  List<Map<String, dynamic>> _batchResults = [];
  final Set<String> _savingOrderHubIds = {};
  String? _batchAssociationError;
  Stopwatch _batchStopwatch = Stopwatch();
  Timer? _batchTimer;

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
  final LayerHitNotifier<String> _regionHitNotifier = LayerHitNotifier<String>(null);
  bool _showHubLayer = true;

  @override
  void dispose() {
    _batchTimer?.cancel();
    _regionHitNotifier.dispose();
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
    if (hubsError == null) {
      final points = hubs
          .where((hub) => hub.hasValidCoordinates)
          .map((hub) => LatLng(hub.latitude!, hub.longitude!))
          .toList();
      if (points.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final distinctPoints = points
              .map((point) => '${point.latitude},${point.longitude}')
              .toSet();
          if (distinctPoints.length == 1) {
            _mapController.move(points.first, 11);
          } else {
            _mapController.fitCamera(
              CameraFit.coordinates(
                coordinates: points,
                padding: const EdgeInsets.all(44),
                maxZoom: 12,
              ),
            );
          }
        });
      }
    }
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

  void _updateBatchState(VoidCallback update) {
    setState(update);
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
    });

    var stage = 'Resolvendo CEPs';
    try {
      final route = await LogiPredictApi.resolveRoute(
        originCeps: originCeps,
        destinationCep: destinationCep,
      );
      stage = 'Validando os parâmetros';
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
      setState(() {
        _lastAttempt = {'payload': payload, 'route': route};
      });

      stage = 'Consultando o modelo';
      final result = await LogiPredictApi.predict(payload);
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
      if (!mounted) return;
      setState(() {
        _currentScenario = {
          'payload': payload,
          'route': route,
          'response': result,
        };
        _lastAttempt = null;
        _riskProbability = probability;
        _predictedLate = predictedLateValue;
        _riskTitle = predictedLateValue
            ? 'O modelo classificou risco de atraso'
            : 'O modelo não classificou atraso acima do limiar';
        _riskDescription = 'Estimativa de risco, não garantia de atraso.';
        _modelVersion = result['model_version']?.toString();
        _lastThreshold = threshold;
        _warnings = warnings;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _riskProbability = null;
        _predictedLate = null;
        _riskTitle = switch (stage) {
          'Resolvendo CEPs' => 'Não foi possível resolver a localização',
          'Validando os parâmetros' => 'Parâmetros inválidos',
          _ => 'Previsão indisponível',
        };
        _riskDescription = error.toString();
      });
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
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
      _buildBatchPage(),
      _buildAnalyticsPage(),
      const HubsManagementScreen(),
      const OrdersManagementScreen(),
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
      'Simulador Prescritivo',
      'Mapa de Calor Logístico',
      'Simulação em Lote',
      'Analytics & KPIs',
      'Gestão de Hubs',
      'Pedidos',
    ];
    const icons = [
      Icons.calculate_outlined,
      Icons.map_outlined,
      Icons.table_view_outlined,
      Icons.show_chart,
      Icons.warehouse_outlined,
      Icons.receipt_long_outlined,
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
                setState(() => _tab = i);
                if (i == 1 &&
                    !wasOnMap &&
                    !_loadingMapHubs &&
                    !_loadingHubRisk) {
                  _loadMapHubs();
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
