import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'services/logipredict_api.dart';

void main() => runApp(const LogiPredictApp());

const navy = Color(0xFF0F172A);
const blue = Color(0xFF2563EB);
const pageBg = Color(0xFFF8FAFC);
const muted = Color(0xFF64748B);

class LogiPredictApp extends StatefulWidget {
  const LogiPredictApp({super.key});

  @override
  State<LogiPredictApp> createState() => _LogiPredictAppState();
}

class _LogiPredictAppState extends State<LogiPredictApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void _toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LogiPredict AI',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: blue),
        scaffoldBackgroundColor: pageBg,
        appBarTheme: const AppBarTheme(
          backgroundColor: navy,
          foregroundColor: Colors.white,
          elevation: 1,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: blue,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0B1120),
        canvasColor: const Color(0xFF0B1120),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF111827),
          foregroundColor: Colors.white,
          elevation: 1,
        ),
        cardColor: const Color(0xFF1E293B),
        dividerColor: const Color(0xFF334155),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1E293B),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF475569)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF475569)),
          ),
        ),
      ),
      home: DashboardPage(
        isDarkMode: _themeMode == ThemeMode.dark,
        onThemeToggle: _toggleTheme,
      ),
    );
  }
}

class DashboardPage extends StatefulWidget {
  final bool isDarkMode;
  final VoidCallback onThemeToggle;

  const DashboardPage(
      {super.key, required this.isDarkMode, required this.onThemeToggle});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
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
  final _originController = TextEditingController(text: '12220-000');
  final _destinationController = TextEditingController(text: '40010-000');
  final _weightController = TextEditingController(text: '2.5');
  final _declaredValueController = TextEditingController(text: '350.00');
  final _deadlineController = TextEditingController(text: '5');
  DateTime _shippingDate = DateTime(2026, 11, 24);
  String _hub = 'cajamar';
  String _season = 'bf';
  bool _advanced = false;
  int? _risk;
  String _riskTitle = 'Aguardando análise';
  String _riskDescription =
      'Informe os dados do despacho e execute a análise para consultar o modelo.';
  double? _lastThreshold;
  bool _isBatchAnalyzing = false;
  int _batchCompleted = 0;
  int _batchTotal = 0;
  String? _batchError;
  String? _batchFileName;
  List<Map<String, dynamic>> _batchShipments = [];
  List<Map<String, dynamic>> _batchResults = [];

  @override
  void dispose() {
    _originController.dispose();
    _destinationController.dispose();
    _weightController.dispose();
    _declaredValueController.dispose();
    _deadlineController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
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

  Future<void> _analyze() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final sellerState = _stateFromCep(_originController.text);
    final customerState = _stateFromCep(_destinationController.text);
    if (sellerState == null || customerState == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível identificar a UF pelo CEP.'),
        ),
      );
      return;
    }

    final weightKg = double.tryParse(
      _weightController.text.replaceAll(',', '.'),
    );
    final price = double.tryParse(
          _declaredValueController.text.replaceAll(',', '.'),
        ) ??
        0.0;
    final deadlineDays = int.tryParse(_deadlineController.text) ?? 5;

    if (weightKg == null || weightKg <= 0 || price < 0 || deadlineDays <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Confira peso, valor declarado e prazo prometido.'),
        ),
      );
      return;
    }

    final estimatedDelivery = _shippingDate.add(Duration(days: deadlineDays));
    final shipment = <String, dynamic>{
      'purchase_at': _shippingDate.toIso8601String(),
      'dispatched_at': _shippingDate.toIso8601String(),
      'estimated_delivery_at': estimatedDelivery.toIso8601String(),
      'seller_state': sellerState,
      'customer_state': customerState,
      'distance_km': null,
      'total_weight_g': weightKg * 1000,
      'total_volume_cm3': null,
      'items_count': 1,
      'sellers_count': 1,
      'price': price,
      'freight_value': 0.0,
    };

    setState(() {
      _isAnalyzing = true;
      _risk = null;
      _riskTitle = 'Análise em andamento';
      _riskDescription = 'Consultando o serviço de Machine Learning...';
      _warnings = [];
      _modelVersion = null;
      _lastThreshold = null;
    });

    try {
      final result = await LogiPredictApi.predict(shipment);
      if (!mounted) return;

      final probabilityValue = result['delay_probability'];
      final predictedLateValue = result['predicted_late'];
      final thresholdValue = result['threshold'];

      if (probabilityValue is! num ||
          predictedLateValue is! bool ||
          thresholdValue is! num) {
        throw const FormatException(
          'Resposta incompleta do modelo: eram esperados '
          'delay_probability, predicted_late e threshold.',
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
          'O modelo retornou uma probabilidade ou limiar fora do intervalo de 0 a 1.',
        );
      }

      final modelVersion = result['model_version']?.toString();
      final warningsRaw = result['warnings'];
      final warnings = warningsRaw is List
          ? warningsRaw.map((item) => item.toString()).toList()
          : <String>[];

      setState(() {
        _risk = (probability * 100).round();
        _riskTitle = predictedLateValue
            ? 'RISCO ELEVADO SEGUNDO O MODELO'
            : 'ATRASO NÃO INDICADO PELO MODELO';
        _riskDescription = 'Probabilidade estimada pelo modelo'
            '${modelVersion == null ? '' : ' $modelVersion'}. '
            'Limiar de decisão: ${(threshold * 100).toStringAsFixed(1)}%.';
        _modelVersion = modelVersion;
        _lastThreshold = threshold;
        _warnings = warnings;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _risk = null;
        _riskTitle = 'Não foi possível calcular o risco';
        _riskDescription =
            'Nenhuma previsão foi apresentada. Verifique a API e tente novamente.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha na análise: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isAnalyzing = false);
      }
    }
  }

  String? _stateFromCep(String cep) {
    final digits = cep.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 8) return null;
    final prefix3 = int.tryParse(digits.substring(0, 3));
    final prefix = int.tryParse(digits.substring(0, 2));
    if (prefix == null || prefix3 == null) return null;
    if (prefix <= 19) return 'SP';
    if (prefix <= 28) return 'RJ';
    if (prefix == 29) return 'ES';
    if (prefix <= 39) return 'MG';
    if (prefix <= 48) return 'BA';
    if (prefix == 49) return 'SE';
    if (prefix <= 56) return 'PE';
    if (prefix == 57) return 'AL';
    if (prefix == 58) return 'PB';
    if (prefix == 59) return 'RN';
    if (prefix <= 63) return 'CE';
    if (prefix == 64) return 'PI';
    if (prefix == 65) return 'MA';
    if (prefix == 68 && prefix3 == 689) return 'AP';
    if (prefix <= 68) return 'PA';
    if (prefix == 69 && prefix3 == 693) return 'RR';
    if (prefix == 69 && prefix3 == 699) return 'AC';
    if (prefix == 69) return 'AM';
    if (prefix == 70 || prefix == 71 || (prefix == 72 && prefix3 <= 727)) {
      return 'DF';
    }
    if (prefix == 76 && prefix3 >= 768) return 'RO';
    if (prefix <= 76) return 'GO';
    if (prefix == 77) return 'TO';
    if (prefix == 78) return 'MT';
    if (prefix == 79) return 'MS';
    if (prefix <= 87) return 'PR';
    if (prefix <= 89) return 'SC';
    return 'RS';
  }

  Future<void> _applySuggestion(String type) async {
    if (_isAnalyzing) return;

    if (type == 'hub') {
      // O payload atual não envia hub para o serviço de ML. Não alterar a UI
      // como se isso fosse um cenário avaliado pelo modelo.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A alteração de hub ainda não está integrada ao modelo. '
            'É necessário atualizar o contrato da API e o serviço Python.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _shippingDate = _shippingDate.subtract(const Duration(days: 1));

      // Alterar parâmetros não equivale a recalcular uma previsão.
      // A previsão anterior é invalidada até o usuário executar nova análise.
      _risk = null;
      _riskTitle = 'Recalculando cenário';
      _riskDescription =
          'A data foi antecipada em um dia. Consultando o modelo para estimar o risco atualizado...';
      _warnings = [];
      _modelVersion = null;
      _lastThreshold = null;
    });

    // Aplicar a sugestão também executa a análise do cenário atualizado.
    await _analyze();
  }

  Color get _riskColor {
    final risk = _risk;
    if (risk == null) return _secondaryText;
    if (risk >= 65) return const Color(0xFFDC2626);
    if (risk >= 35) return const Color(0xFFF59E0B);
    return const Color(0xFF059669);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildSimulator(),
      _buildMapPage(),
      _buildBatchPage(),
      _buildAnalyticsPage(),
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
    ];
    const icons = [
      Icons.calculate_outlined,
      Icons.map_outlined,
      Icons.table_view_outlined,
      Icons.show_chart,
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
              onTap: () => setState(() => _tab = i),
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

  Widget _buildSimulator() {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 950;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                      width: constraints.maxWidth * .40,
                      child: _buildFormCard()),
                  const SizedBox(width: 22),
                  Expanded(child: _buildResults()),
                ],
              )
            : Column(
                children: [
                  _buildFormCard(),
                  const SizedBox(height: 18),
                  _buildResults(),
                ],
              ),
      );
    });
  }

  Widget _buildFormCard() {
    return _card(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionTitle(
              icon: Icons.tune,
              title: 'Parâmetros do Despacho',
            ),
            const SizedBox(height: 18),
            LayoutBuilder(builder: (context, constraints) {
              final split = constraints.maxWidth > 460;
              return Wrap(
                spacing: 12,
                runSpacing: 14,
                children: [
                  SizedBox(
                    width: split
                        ? (constraints.maxWidth - 12) / 2
                        : constraints.maxWidth,
                    child: _textField(
                      controller: _originController,
                      label: 'CEP Origem (Vendedor)',
                      helper: 'Jacareí / SJC - SP',
                      validator: _required,
                    ),
                  ),
                  SizedBox(
                    width: split
                        ? (constraints.maxWidth - 12) / 2
                        : constraints.maxWidth,
                    child: _textField(
                      controller: _destinationController,
                      label: 'CEP Destino (Cliente)',
                      helper: 'Salvador - BA',
                      validator: _required,
                    ),
                  ),
                  SizedBox(
                    width: split
                        ? (constraints.maxWidth - 12) / 2
                        : constraints.maxWidth,
                    child: InkWell(
                      onTap: _pickDate,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Data Prevista Envio',
                          suffixIcon: Icon(Icons.calendar_month),
                        ),
                        child: Text(_dateString(_shippingDate)),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: split
                        ? (constraints.maxWidth - 12) / 2
                        : constraints.maxWidth,
                    child: _textField(
                      controller: _weightController,
                      label: 'Peso Estimado (kg)',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        final value =
                            double.tryParse((v ?? '').replaceAll(',', '.'));
                        if (value == null || value <= 0)
                          return 'Informe um peso válido.';
                        return null;
                      },
                    ),
                  ),
                ],
              );
            }),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: _surfaceAlt,
                border: Border.all(color: _border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ExpansionTile(
                initiallyExpanded: _advanced,
                onExpansionChanged: (v) => setState(() => _advanced = v),
                title: const Text('Opções Avançadas (Hub, Valor, Dimensões)',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                leading: const Icon(Icons.settings_outlined, size: 19),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                children: [
                  DropdownButtonFormField<String>(
                    value: _hub,
                    decoration: const InputDecoration(
                        labelText: 'Hub Logístico de Origem'),
                    items: const [
                      DropdownMenuItem(
                          value: 'cajamar',
                          child: Text('Hub Regional Cajamar - SP')),
                      DropdownMenuItem(
                          value: 'guarulhos',
                          child: Text('Hub Internacional Guarulhos - SP')),
                      DropdownMenuItem(
                          value: 'agencia',
                          child: Text('Agência de Coleta Local')),
                    ],
                    onChanged: (v) => setState(() => _hub = v ?? _hub),
                  ),
                  const SizedBox(height: 12),
                  _textField(
                    controller: _declaredValueController,
                    label: 'Valor Declarado (R\$)',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 12),
                  _textField(
                    controller: _deadlineController,
                    label: 'Prazo Prometido (dias)',
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _isAnalyzing ? null : _analyze,
              icon: _isAnalyzing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: Text(
                  _isAnalyzing ? 'Analisando...' : 'Analisar Risco com IA',
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    return Column(
      children: [
        _card(
          child: LayoutBuilder(builder: (context, constraints) {
            final compact = constraints.maxWidth < 420;
            final description = Column(
              crossAxisAlignment: compact
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                Text('RESULTADO DO DIAGNÓSTICO',
                    style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1,
                        color: _secondaryText,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 7),
                Text(_riskTitle,
                    textAlign: compact ? TextAlign.center : TextAlign.start,
                    style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: _riskColor)),
                const SizedBox(height: 8),
                Text(_riskDescription,
                    textAlign: compact ? TextAlign.center : TextAlign.start,
                    style: TextStyle(
                        fontSize: 13, color: _secondaryText, height: 1.45)),
              ],
            );
            final score = Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                color: _surfaceAlt,
                border: Border.all(color: _border),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_risk == null ? '—' : '$_risk%',
                      style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          color: _riskColor)),
                  Text(_risk == null ? 'SEM PREVISÃO' : 'PROBABILIDADE',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: _secondaryText)),
                ],
              ),
            );
            return compact
                ? Column(
                    children: [description, const SizedBox(height: 18), score])
                : Row(children: [
                    Expanded(child: description),
                    const SizedBox(width: 18),
                    score
                  ]);
          }),
        ),
        const SizedBox(height: 18),
        _card(
          color: _isDark ? const Color(0xFF142B49) : const Color(0xFFF0F7FF),
          borderColor:
              _isDark ? const Color(0xFF24518A) : const Color(0xFFBFDBFE),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle(
                icon: Icons.lightbulb_outline,
                title: 'Sugestões Prescritivas da IA',
                subtitle: 'Para reduzir o risco',
              ),
              const SizedBox(height: 14),
              _suggestionCard(
                icon: Icons.calendar_month,
                iconColor: blue,
                title: 'Antecipar Data de Despacho',
                description:
                    'Antecipar a data em um dia. Reanalise para avaliar o efeito estimado pelo modelo.',
                reduction: 'Requer nova análise',
                onApply: () => _applySuggestion('date'),
              ),
              const SizedBox(height: 12),
              _suggestionCard(
                icon: Icons.warehouse_outlined,
                iconColor: const Color(0xFFD97706),
                title: 'Alteração de hub (integração pendente)',
                description:
                    'Ainda não é enviado ao modelo Python. A integração da API precisa ser concluída antes de estimar o efeito.',
                reduction: 'Não integrado',
                onApply: () => _applySuggestion('hub'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _suggestionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    required String reduction,
    required VoidCallback onApply,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(
            color: _isDark ? const Color(0xFF334A67) : const Color(0xFFDBEAFE)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 5),
                    Text(description,
                        style: TextStyle(
                            fontSize: 12, color: _secondaryText, height: 1.4)),
                  ]),
            ),
          ]),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            Text(reduction,
                style: TextStyle(
                    color: _secondaryText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: onApply,
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Aplicar'),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildMapPage() {
    final center = const LatLng(-14.235, -51.925);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          _card(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Mapa de Retenção e Gargalos Logísticos',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              const SizedBox(height: 5),
              Text(
                  'Visualização ilustrativa de áreas de risco e rotas críticas.',
                  style: TextStyle(fontSize: 12, color: _secondaryText)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _season,
                decoration: const InputDecoration(labelText: 'Sazonalidade'),
                items: const [
                  DropdownMenuItem(
                      value: 'bf', child: Text('Black Friday 2026')),
                  DropdownMenuItem(value: 'natal', child: Text('Natal')),
                  DropdownMenuItem(
                      value: 'normal', child: Text('Período normal')),
                ],
                onChanged: (v) => setState(() => _season = v ?? _season),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          Container(
            height: 470,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border),
            ),
            child: FlutterMap(
              options: MapOptions(initialCenter: center, initialZoom: 4),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.logipredict_ai',
                ),
                CircleLayer(circles: [
                  CircleMarker(
                    point: const LatLng(-12.97, -38.50),
                    radius: _season == 'normal'
                        ? 80000
                        : (_season == 'natal' ? 220000 : 300000),
                    useRadiusInMeter: true,
                    color: Colors.red.withValues(alpha: .25),
                    borderColor: Colors.red,
                    borderStrokeWidth: 2,
                  ),
                  CircleMarker(
                    point: const LatLng(-23.55, -46.63),
                    radius: _season == 'normal' ? 70000 : 200000,
                    useRadiusInMeter: true,
                    color: Colors.orange.withValues(alpha: .22),
                    borderColor: Colors.orange,
                    borderStrokeWidth: 2,
                  ),
                  CircleMarker(
                    point: const LatLng(-25.42, -49.27),
                    radius: 150000,
                    useRadiusInMeter: true,
                    color: Colors.green.withValues(alpha: .18),
                    borderColor: Colors.green,
                    borderStrokeWidth: 2,
                  ),
                ]),
                MarkerLayer(markers: const [
                  Marker(
                    point: LatLng(-12.97, -38.50),
                    width: 110,
                    height: 35,
                    child: _MapLabel(text: 'Salvador/BA', color: Colors.red),
                  ),
                  Marker(
                    point: LatLng(-23.55, -46.63),
                    width: 130,
                    height: 35,
                    child: _MapLabel(
                        text: 'Grande São Paulo', color: Colors.deepOrange),
                  ),
                  Marker(
                    point: LatLng(-25.42, -49.27),
                    width: 100,
                    height: 35,
                    child: _MapLabel(text: 'Sul', color: Colors.green),
                  ),
                ]),
                const RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('© OpenStreetMap contributors')
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
              'Mapa demonstrativo: as áreas e os níveis de risco são dados simulados.',
              style: TextStyle(fontSize: 11, color: _secondaryText)),
        ],
      ),
    );
  }

  Future<void> _pickBatchCsv() async {
    if (_isBatchAnalyzing) return;
    try {
      final selection = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        withData: true,
      );
      if (selection == null || selection.files.isEmpty) return;
      final file = selection.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw const FormatException(
            'O arquivo CSV está vazio ou não pôde ser lido.');
      }
      final content =
          utf8.decode(bytes, allowMalformed: true).replaceFirst('\uFEFF', '');
      final records = _parseCsv(content);
      if (records.length < 2) {
        throw const FormatException(
            'O CSV precisa ter cabeçalho e pelo menos um pedido.');
      }
      final headers = records.first.map((h) => h.trim().toLowerCase()).toList();
      final required = <String>[
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
            'Colunas obrigatórias ausentes: ${missing.join(', ')}. Baixe/consulte o modelo CSV esperado.');
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
        if (parsed == null)
          throw FormatException(
              'Linha $line: data inválida em $column. Use AAAA-MM-DD ou ISO 8601.');
        return parsed;
      }

      final shipments = <Map<String, dynamic>>[];
      for (var i = 1; i < records.length; i++) {
        final row = records[i];
        if (row.every((v) => v.trim().isEmpty)) continue;
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
        if (weight < 0 ||
            price < 0 ||
            freight < 0 ||
            estimated.isBefore(dispatched)) {
          throw FormatException(
              'Linha $line: peso/valores não podem ser negativos e a previsão de entrega deve ser posterior ao despacho.');
        }
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
              : number(
                  field(row, 'total_volume_cm3'), 'total_volume_cm3', line),
          'days': estimated.difference(dispatched).inDays,
        });
      }
      if (shipments.isEmpty)
        throw const FormatException(
            'Nenhum pedido válido foi encontrado no CSV.');
      setState(() {
        _batchShipments = shipments;
        _batchResults = [];
        _batchError = null;
        _batchCompleted = 0;
        _batchTotal = shipments.length;
        _batchFileName = file.name;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '${shipments.length} pedidos carregados de ${file.name}.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _batchError = 'Não foi possível importar o CSV: $e');
    }
  }

  List<List<String>> _parseCsv(String input) {
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
        if (char == '\r' && i + 1 < input.length && input[i + 1] == '\n') i++;
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

  Future<void> _runBatchAnalysis() async {
    if (_isBatchAnalyzing) return;
    if (_batchShipments.isEmpty) {
      setState(() => _batchError =
          'Importe um CSV de pedidos antes de executar a análise.');
      return;
    }
    final shipments = List<Map<String, dynamic>>.from(_batchShipments);
    setState(() {
      _isBatchAnalyzing = true;
      _batchCompleted = 0;
      _batchTotal = shipments.length;
      _batchError = null;
      _batchResults = [];
    });

    final results = <Map<String, dynamic>>[];
    for (final order in shipments) {
      final payload = <String, dynamic>{
        'purchase_at': (order['purchase_at'] as DateTime).toIso8601String(),
        'dispatched_at': (order['dispatched_at'] as DateTime).toIso8601String(),
        'estimated_delivery_at':
            (order['estimated_delivery_at'] as DateTime).toIso8601String(),
        'seller_state': order['seller_state'],
        'customer_state': order['customer_state'],
        'distance_km': null,
        'total_weight_g': order['weight_g'],
        'total_volume_cm3': order['total_volume_cm3'],
        'items_count': order['items_count'],
        'sellers_count': order['sellers_count'],
        'price': order['price'],
        'freight_value': order['freight_value'],
      };
      try {
        final response = await LogiPredictApi.predict(payload);
        final probabilityValue = response['delay_probability'];
        final predictedLateValue = response['predicted_late'];
        final thresholdValue = response['threshold'];
        if (probabilityValue is! num ||
            predictedLateValue is! bool ||
            thresholdValue is! num) {
          throw const FormatException('Resposta incompleta do modelo.');
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
              'Probabilidade/limiar fora do intervalo 0–1.');
        }
        results.add({
          ...order,
          'probability': probability,
          'predicted_late': predictedLateValue,
          'threshold': threshold,
          'model_version': response['model_version']?.toString(),
          'error': null
        });
      } catch (e) {
        results.add({...order, 'error': e.toString()});
      }
      if (!mounted) return;
      setState(() {
        _batchCompleted = results.length;
        _batchResults = List<Map<String, dynamic>>.from(results)
          ..sort((a, b) => ((b['probability'] as num?)?.toDouble() ?? -1)
              .compareTo((a['probability'] as num?)?.toDouble() ?? -1));
      });
    }
    if (!mounted) return;
    final failed = results.where((row) => row['error'] != null).length;
    setState(() {
      _isBatchAnalyzing = false;
      _batchError = failed == 0
          ? null
          : '$failed de ${shipments.length} pedidos não puderam ser analisados.';
    });
  }

  Widget _buildBatchPage() {
    final successful =
        _batchResults.where((r) => r['probability'] is num).length;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Processamento e Priorização em Lote',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text(
            'Importe um CSV de pedidos com dados de despacho, destino, peso e valores. Cada linha válida será enviada à API de Machine Learning.',
            style: TextStyle(fontSize: 12, color: _secondaryText),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _surfaceAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border),
            ),
            child: const Text(
              'Os resultados só serão de pedidos reais se o CSV vier de uma base real. O CSV precisa estar no formato padronizado descrito no modelo de exemplo; os arquivos brutos da Olist precisam ser unidos e preparados antes.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 16),
          if (_batchFileName != null) ...[
            Text(
                'Arquivo: $_batchFileName · ${_batchShipments.length} pedidos carregados',
                style: TextStyle(fontSize: 12, color: _secondaryText)),
            const SizedBox(height: 10),
          ],
          Wrap(spacing: 10, runSpacing: 10, children: [
            OutlinedButton.icon(
              onPressed: _isBatchAnalyzing ? null : _pickBatchCsv,
              icon: const Icon(Icons.upload_file),
              label: const Text('Importar CSV'),
            ),
            FilledButton.icon(
              onPressed: _isBatchAnalyzing || _batchShipments.isEmpty
                  ? null
                  : _runBatchAnalysis,
              icon: _isBatchAnalyzing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(_isBatchAnalyzing
                  ? 'Analisando $_batchCompleted/$_batchTotal...'
                  : 'Executar análise em lote'),
            ),
            OutlinedButton.icon(
              onPressed: _batchResults.isEmpty || _isBatchAnalyzing
                  ? null
                  : () => setState(() {
                        _batchResults = [];
                        _batchError = null;
                        _batchCompleted = 0;
                      }),
              icon: const Icon(Icons.clear),
              label: const Text('Limpar resultados'),
            ),
          ]),
          if (_isBatchAnalyzing) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
                value: _batchTotal == 0 ? 0 : _batchCompleted / _batchTotal),
          ],
          if (_batchError != null) ...[
            const SizedBox(height: 12),
            Text(_batchError!, style: const TextStyle(color: Colors.red)),
          ],
          if (_batchResults.isNotEmpty) ...[
            const SizedBox(height: 18),
            Wrap(spacing: 12, runSpacing: 8, children: [
              _miniMetric('Analisados', '$successful/${_batchResults.length}'),
              _miniMetric(
                'Alerta de atraso',
                '${_batchResults.where((r) => r['predicted_late'] == true).length}',
              ),
              _miniMetric(
                'Falhas',
                '${_batchResults.where((r) => r['error'] != null).length}',
              ),
            ]),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(_surfaceAlt),
                columns: const [
                  DataColumn(label: Text('ID Pedido')),
                  DataColumn(label: Text('Origem → Destino')),
                  DataColumn(label: Text('Prazo estimado')),
                  DataColumn(label: Text('Probabilidade')),
                  DataColumn(label: Text('Resultado do modelo')),
                  DataColumn(label: Text('Modelo')),
                ],
                rows: _batchResults.map((row) {
                  final probability = row['probability'];
                  final failed = row['error'] != null;
                  final risk =
                      probability is num ? probability.toDouble() : null;
                  final riskColor = failed
                      ? Colors.red
                      : risk != null &&
                              risk >= (row['threshold'] as num).toDouble()
                          ? Colors.deepOrange
                          : Colors.green;
                  return DataRow(cells: [
                    DataCell(Text(row['id'].toString(),
                        style: const TextStyle(fontWeight: FontWeight.bold))),
                    DataCell(Text('${row['origin']} → ${row['destination']}')),
                    DataCell(Text('${row['days']} dias')),
                    DataCell(Text(
                      failed ? 'Erro' : '${(risk! * 100).toStringAsFixed(1)}%',
                      style: TextStyle(
                          color: riskColor, fontWeight: FontWeight.bold),
                    )),
                    DataCell(Text(failed
                        ? 'Falha na API'
                        : row['predicted_late'] == true
                            ? 'Alerta de atraso'
                            : 'Sem alerta pelo limiar')),
                    DataCell(Text(row['model_version']?.toString() ?? '—')),
                  ]);
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ordenação: maior probabilidade primeiro. “Sem alerta” não significa garantia de entrega no prazo.',
              style: TextStyle(fontSize: 11, color: _secondaryText),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _miniMetric(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11, color: _secondaryText)),
          const SizedBox(height: 3),
          Text(value,
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        ]),
      );

  double _numberValue(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _intValue(dynamic value) => _numberValue(value).round();

  double _stateRate(Map<String, dynamic> state) {
    final orders = _intValue(state['orders']);
    final lateOrders = _intValue(state['late_orders']);
    // A taxa é sempre recalculada a partir das contagens, evitando
    // divergências caso late_rate venha arredondado ou em outra escala.
    if (orders <= 0) return 0;
    return (lateOrders / orders).clamp(0.0, 1.0);
  }

  Widget _buildAnalyticsPage() {
    final states = List<Map<String, dynamic>>.from(_stateAnalytics)
      ..sort((a, b) => _stateRate(b).compareTo(_stateRate(a)));

    final totalOrders =
        states.fold<int>(0, (sum, state) => sum + _intValue(state['orders']));
    final totalLateOrders = states.fold<int>(
        0, (sum, state) => sum + _intValue(state['late_orders']));
    final overallRate = totalOrders > 0 ? totalLateOrders / totalOrders : 0.0;
    final statesWithData =
        states.where((s) => _intValue(s['orders']) > 0).length;
    final highestState = states.where((s) => _intValue(s['orders']) > 0).isEmpty
        ? null
        : states.firstWhere((s) => _intValue(s['orders']) > 0);
    final lowestState = states.where((s) => _intValue(s['orders']) > 0).isEmpty
        ? null
        : states.lastWhere((s) => _intValue(s['orders']) > 0);

    return RefreshIndicator(
      onRefresh: _loadAnalytics,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Analytics & KPIs',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: _primaryText,
                          )),
                      const SizedBox(height: 5),
                      Text(
                        'Visão histórica da operação logística por estado.',
                        style: TextStyle(color: _secondaryText, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Atualizar indicadores',
                  onPressed: _loadingAnalytics ? null : _loadAnalytics,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loadingAnalytics && states.isEmpty)
              _card(
                child: const Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (_analyticsError != null && states.isEmpty)
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Não foi possível carregar os indicadores.',
                        style: TextStyle(
                          color: Color(0xFFDC2626),
                          fontWeight: FontWeight.bold,
                        )),
                    const SizedBox(height: 8),
                    SelectableText(_analyticsError!,
                        style: TextStyle(color: _secondaryText, fontSize: 12)),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _loadAnalytics,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              )
            else if (states.isEmpty)
              _card(child: const Text('A API não retornou dados por estado.'))
            else ...[
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 900
                      ? 4
                      : constraints.maxWidth >= 560
                          ? 2
                          : 1;
                  const spacing = 12.0;
                  final cardWidth =
                      (constraints.maxWidth - spacing * (columns - 1)) /
                          columns;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      SizedBox(
                        width: cardWidth,
                        child: _kpiCard(
                          icon: Icons.inventory_2_outlined,
                          label: 'Pedidos analisados',
                          value: totalOrders.toString(),
                          caption: 'Somatório dos estados retornados',
                          color: blue,
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _kpiCard(
                          icon: Icons.local_shipping_outlined,
                          label: 'Pedidos atrasados',
                          value: totalLateOrders.toString(),
                          caption: totalOrders > 0
                              ? '${(overallRate * 100).toStringAsFixed(1)}% do total'
                              : 'Sem pedidos suficientes',
                          color: const Color(0xFFDC2626),
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _kpiCard(
                          icon: Icons.percent,
                          label: 'Taxa histórica geral',
                          value: '${(overallRate * 100).toStringAsFixed(1)}%',
                          caption: 'Atrasados ÷ pedidos',
                          color: overallRate >= .15
                              ? const Color(0xFFDC2626)
                              : overallRate >= .08
                                  ? const Color(0xFFD97706)
                                  : const Color(0xFF059669),
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _kpiCard(
                          icon: Icons.map_outlined,
                          label: 'Estados com dados',
                          value: statesWithData.toString(),
                          caption: highestState == null
                              ? 'Sem dados disponíveis'
                              : 'Maior taxa: ${highestState['customer_state'] ?? '--'}',
                          color: const Color(0xFF7C3AED),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: blue.withValues(alpha: .10),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.bar_chart, color: blue),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Taxa histórica de atraso por estado',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: _primaryText,
                                  )),
                              const SizedBox(height: 4),
                              Text(
                                'Ordenado da maior para a menor taxa. Selecione uma barra para ver os detalhes.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _secondaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 340,
                      child: BarChart(_barChartData(states)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Indicador descritivo dos dados históricos; não representa a probabilidade de atraso de um novo pedido.',
                      style: TextStyle(
                        color: _secondaryText,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.format_list_numbered, color: blue),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text('Detalhamento por estado',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: _primaryText,
                              )),
                        ),
                        Text('${states.length} estados',
                            style: TextStyle(
                              fontSize: 12,
                              color: _secondaryText,
                            )),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'A taxa é calculada como pedidos atrasados ÷ pedidos analisados.',
                      style: TextStyle(fontSize: 12, color: _secondaryText),
                    ),
                    const SizedBox(height: 12),
                    ...states.asMap().entries.map((entry) {
                      final state = entry.value;
                      final uf = state['customer_state']?.toString() ?? '--';
                      final orders = _intValue(state['orders']);
                      final lateOrders = _intValue(state['late_orders']);
                      final rate = _stateRate(state);
                      final rateColor = rate >= .15
                          ? const Color(0xFFDC2626)
                          : rate >= .08
                              ? const Color(0xFFD97706)
                              : const Color(0xFF059669);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 11),
                        decoration: BoxDecoration(
                          color: entry.key.isEven ? _surfaceAlt : _surface,
                          border: Border.all(color: _border),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: rateColor.withValues(alpha: .10),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Text(
                                uf,
                                style: TextStyle(
                                  color: rateColor,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('$orders pedidos',
                                      style: TextStyle(
                                        color: _primaryText,
                                        fontWeight: FontWeight.w700,
                                      )),
                                  const SizedBox(height: 3),
                                  Text('$lateOrders atrasados',
                                      style: TextStyle(
                                        color: _secondaryText,
                                        fontSize: 12,
                                      )),
                                  const SizedBox(height: 7),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: LinearProgressIndicator(
                                      value: rate,
                                      minHeight: 5,
                                      backgroundColor: _border,
                                      valueColor:
                                          AlwaysStoppedAnimation(rateColor),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),
                            SizedBox(
                              width: 62,
                              child: Text(
                                '${(rate * 100).toStringAsFixed(1)}%',
                                textAlign: TextAlign.end,
                                style: TextStyle(
                                  color: rateColor,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    if (lowestState != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Menor taxa observada: ${lowestState['customer_state'] ?? '--'} '
                        '(${(_stateRate(lowestState) * 100).toStringAsFixed(1)}%).',
                        style: TextStyle(
                          fontSize: 12,
                          color: _secondaryText,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kpiCard({
    required IconData icon,
    required String label,
    required String value,
    required String caption,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isDark ? .12 : .025),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: color, size: 19),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                      fontSize: 12,
                      color: _secondaryText,
                      fontWeight: FontWeight.w600,
                    )),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Text(value,
              style: TextStyle(
                color: _primaryText,
                fontSize: 27,
                fontWeight: FontWeight.w900,
                letterSpacing: -.5,
              )),
          const SizedBox(height: 5),
          Text(caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _secondaryText,
                fontSize: 11,
              )),
        ],
      ),
    );
  }

  BarChartData _barChartData(List<Map<String, dynamic>> states) {
    final chartStates =
        states.where((state) => _intValue(state['orders']) > 0).toList();
    final maxRate = chartStates.fold<double>(
      0,
      (current, state) {
        final rate = _stateRate(state) * 100;
        return rate > current ? rate : current;
      },
    );

    return BarChartData(
      maxY: maxRate > 0 ? (maxRate * 1.18).clamp(5.0, 100.0) : 5,
      alignment: BarChartAlignment.spaceAround,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (value) => FlLine(
          color: _border,
          strokeWidth: 1,
          dashArray: [5, 4],
        ),
      ),
      borderData: FlBorderData(show: false),
      barTouchData: BarTouchData(
        enabled: true,
        touchTooltipData: BarTouchTooltipData(
          getTooltipItem: (group, groupIndex, rod, rodIndex) {
            final state = chartStates[group.x];
            final uf = state['customer_state']?.toString() ?? '--';
            final orders = _intValue(state['orders']);
            final lateOrders = _intValue(state['late_orders']);
            return BarTooltipItem(
              '$uf\n${rod.toY.toStringAsFixed(1)}% de atraso\n'
              '$lateOrders de $orders pedidos',
              const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            );
          },
        ),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 44,
            getTitlesWidget: (value, meta) => Text(
              '${value.toStringAsFixed(0)}%',
              style: TextStyle(fontSize: 10, color: _secondaryText),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 32,
            getTitlesWidget: (value, meta) {
              final index = value.toInt();
              if (index < 0 || index >= chartStates.length) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  chartStates[index]['customer_state']?.toString() ?? '--',
                  style: TextStyle(
                    fontSize: 10,
                    color: _secondaryText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            },
          ),
        ),
      ),
      barGroups: chartStates.asMap().entries.map((entry) {
        final state = entry.value;
        final rate = _stateRate(state) * 100;
        final color = rate >= 15
            ? const Color(0xFFDC2626)
            : rate >= 8
                ? const Color(0xFFD97706)
                : const Color(0xFF059669);
        return BarChartGroupData(
          x: entry.key,
          barRods: [
            BarChartRodData(
              toY: rate,
              color: color,
              width: chartStates.length > 22 ? 10 : 16,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(5),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _shippingDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );
    if (selected != null) setState(() => _shippingDate = selected);
  }

  String? _required(String? value) =>
      (value == null || value.trim().isEmpty) ? 'Campo obrigatório.' : null;

  Widget _textField({
    required TextEditingController controller,
    required String label,
    String? helper,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label, helperText: helper),
      keyboardType: keyboardType,
      validator: validator,
    );
  }

  String _dateString(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

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

class _MapLabel extends StatelessWidget {
  final String text;
  final Color color;
  const _MapLabel({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .94),
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.bold, color: color)),
      ),
    );
  }
}
