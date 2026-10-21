import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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
      _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
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

  const DashboardPage({super.key, required this.isDarkMode, required this.onThemeToggle});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool get _isDark => widget.isDarkMode;
  Color get _surface => _isDark ? const Color(0xFF172338) : Colors.white;
  Color get _surfaceAlt => _isDark ? const Color(0xFF202F46) : const Color(0xFFF8FAFC);
  Color get _border => _isDark ? const Color(0xFF33445D) : const Color(0xFFE2E8F0);
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
  int _risk = 78;
  String _riskTitle = 'ALTO RISCO DE ATRASO';
  String _riskDescription =
      'Rota SP → BA saturada devido à proximidade com a Black Friday 2026.';

  @override
  void dispose() {
    _originController.dispose();
    _destinationController.dispose();
    _weightController.dispose();
    _declaredValueController.dispose();
    _deadlineController.dispose();
    super.dispose();
  }

  void _analyze() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _risk = 78;
      _riskTitle = 'ALTO RISCO DE ATRASO';
      _riskDescription =
      'Rota ${_originController.text} → ${_destinationController.text}: risco elevado no período selecionado.';
    });
  }

  void _applySuggestion(String type) {
    setState(() {
      if (type == 'date') {
        _shippingDate = DateTime(2026, 11, 23);
        _risk = 42;
        _riskTitle = 'RISCO MODERADO';
        _riskDescription =
        'Data antecipada para 23/11. Gargalo reduzido com sucesso.';
      } else {
        _hub = 'guarulhos';
        _risk = 28;
        _riskTitle = 'BAIXO RISCO DE ATRASO';
        _riskDescription =
        'Rota transferida para malha aérea rápida via Hub Guarulhos.';
      }
    });
  }

  Color get _riskColor {
    if (_risk >= 65) return const Color(0xFFDC2626);
    if (_risk >= 35) return const Color(0xFFF59E0B);
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
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19)),
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
                  Text('Modelo v1.4 Ativo',
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
        child: Icon(widget.isDarkMode ? Icons.light_mode : Icons.dark_mode, size: 17),
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
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
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
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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
            SizedBox(width: constraints.maxWidth * .40, child: _buildFormCard()),
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
                    width: split ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth,
                    child: _textField(
                      controller: _originController,
                      label: 'CEP Origem (Vendedor)',
                      helper: 'Jacareí / SJC - SP',
                      validator: _required,
                    ),
                  ),
                  SizedBox(
                    width: split ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth,
                    child: _textField(
                      controller: _destinationController,
                      label: 'CEP Destino (Cliente)',
                      helper: 'Salvador - BA',
                      validator: _required,
                    ),
                  ),
                  SizedBox(
                    width: split ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth,
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
                    width: split ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth,
                    child: _textField(
                      controller: _weightController,
                      label: 'Peso Estimado (kg)',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        final value = double.tryParse((v ?? '').replaceAll(',', '.'));
                        if (value == null || value <= 0) return 'Informe um peso válido.';
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
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                leading: const Icon(Icons.settings_outlined, size: 19),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                children: [
                  DropdownButtonFormField<String>(
                    value: _hub,
                    decoration: const InputDecoration(labelText: 'Hub Logístico de Origem'),
                    items: const [
                      DropdownMenuItem(value: 'cajamar', child: Text('Hub Regional Cajamar - SP')),
                      DropdownMenuItem(value: 'guarulhos', child: Text('Hub Internacional Guarulhos - SP')),
                      DropdownMenuItem(value: 'agencia', child: Text('Agência de Coleta Local')),
                    ],
                    onChanged: (v) => setState(() => _hub = v ?? _hub),
                  ),
                  const SizedBox(height: 12),
                  _textField(
                    controller: _declaredValueController,
                    label: 'Valor Declarado (R\$)',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
              onPressed: _analyze,
              icon: const Icon(Icons.auto_awesome),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 13),
                child: Text('Analisar Risco com IA'),
              ),
            ),
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
              crossAxisAlignment: compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
              children: [
                Text('RESULTADO DO DIAGNÓSTICO',
                    style: TextStyle(fontSize: 11, letterSpacing: 1, color: _secondaryText, fontWeight: FontWeight.bold)),
                const SizedBox(height: 7),
                Text(_riskTitle,
                    textAlign: compact ? TextAlign.center : TextAlign.start,
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: _riskColor)),
                const SizedBox(height: 8),
                Text(_riskDescription,
                    textAlign: compact ? TextAlign.center : TextAlign.start,
                    style: TextStyle(fontSize: 13, color: _secondaryText, height: 1.45)),
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
                  Text('$_risk%',
                      style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: _riskColor)),
                  Text('PROBABILIDADE',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _secondaryText)),
                ],
              ),
            );
            return compact
                ? Column(children: [description, const SizedBox(height: 18), score])
                : Row(children: [Expanded(child: description), const SizedBox(width: 18), score]);
          }),
        ),
        const SizedBox(height: 18),
        _card(
          color: _isDark ? const Color(0xFF142B49) : const Color(0xFFF0F7FF),
          borderColor: _isDark ? const Color(0xFF24518A) : const Color(0xFFBFDBFE),
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
                description: 'Postar em 23/11 evita o pico de lote da rota Nordeste.',
                reduction: '-36% Risco',
                onApply: () => _applySuggestion('date'),
              ),
              const SizedBox(height: 12),
              _suggestionCard(
                icon: Icons.warehouse_outlined,
                iconColor: const Color(0xFFD97706),
                title: 'Alterar para Hub Guarulhos',
                description: 'Transferência para malha aérea reduz o tempo regional.',
                reduction: '-50% Risco',
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
        border: Border.all(color: _isDark ? const Color(0xFF334A67) : const Color(0xFFDBEAFE)),
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
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 5),
                Text(description, style: TextStyle(fontSize: 12, color: _secondaryText, height: 1.4)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            Text(reduction, style: const TextStyle(color: Color(0xFF059669), fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: onApply,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Mapa de Retenção e Gargalos Logísticos',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              const SizedBox(height: 5),
              Text('Visualização ilustrativa de áreas de risco e rotas críticas.',
                  style: TextStyle(fontSize: 12, color: _secondaryText)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _season,
                decoration: const InputDecoration(labelText: 'Sazonalidade'),
                items: const [
                  DropdownMenuItem(value: 'bf', child: Text('Black Friday 2026')),
                  DropdownMenuItem(value: 'natal', child: Text('Natal')),
                  DropdownMenuItem(value: 'normal', child: Text('Período normal')),
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
                    radius: _season == 'normal' ? 80000 : (_season == 'natal' ? 220000 : 300000),
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
                    child: _MapLabel(text: 'Grande São Paulo', color: Colors.deepOrange),
                  ),
                  Marker(
                    point: LatLng(-25.42, -49.27),
                    width: 100,
                    height: 35,
                    child: _MapLabel(text: 'Sul', color: Colors.green),
                  ),
                ]),
                const RichAttributionWidget(
                  attributions: [TextSourceAttribution('© OpenStreetMap contributors')],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text('Mapa demonstrativo: as áreas e os níveis de risco são dados simulados.',
              style: TextStyle(fontSize: 11, color: _secondaryText)),
        ],
      ),
    );
  }

  Widget _buildBatchPage() {
    final rows = [
      ['#ORD-9821', 'Jacareí/SP → Salvador/BA', '24/11/2026', '78% (Alto)', 'Antecipar envio para 23/11', 'P1 - Urgente'],
      ['#ORD-9822', 'São Paulo/SP → Curitiba/PR', '24/11/2026', '12% (Baixo)', 'Manter fluxo padrão', 'P3 - Normal'],
      ['#ORD-9823', 'Campinas/SP → Recife/PE', '25/11/2026', '64% (Médio)', 'Mudar para Hub Guarulhos', 'P2 - Média'],
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Processamento e Priorização em Lote',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text('Exemplos de pedidos importados via CSV e organizados por prioridade.',
              style: TextStyle(fontSize: 12, color: _secondaryText)),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('A exportação CSV ainda precisa ser implementada.')),
              ),
              icon: const Icon(Icons.download),
              label: const Text('Exportar plano'),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(_surfaceAlt),
              columns: const [
                DataColumn(label: Text('ID Pedido')),
                DataColumn(label: Text('Origem/Destino')),
                DataColumn(label: Text('Data')),
                DataColumn(label: Text('Score')),
                DataColumn(label: Text('Ação recomendada')),
                DataColumn(label: Text('Prioridade')),
              ],
              rows: rows.map((r) {
                final score = r[3];
                final scoreColor = score.startsWith('78')
                    ? Colors.red
                    : score.startsWith('64')
                    ? Colors.orange
                    : Colors.green;
                final priorityColor = r[5].startsWith('P1')
                    ? Colors.red
                    : r[5].startsWith('P2')
                    ? Colors.orange
                    : muted;
                return DataRow(cells: [
                  DataCell(Text(r[0], style: const TextStyle(color: blue, fontWeight: FontWeight.bold))),
                  DataCell(Text(r[1])),
                  DataCell(Text(r[2])),
                  DataCell(Text(r[3], style: TextStyle(color: scoreColor, fontWeight: FontWeight.bold))),
                  DataCell(Text(r[4])),
                  DataCell(Text(r[5], style: TextStyle(color: priorityColor, fontWeight: FontWeight.bold))),
                ]);
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),

        ]),
      ),
    );
  }

  Widget _buildAnalyticsPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 850;
        final chart1 = _card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Taxa Histórica de Atraso por Região (%)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            SizedBox(height: 260, child: BarChart(_barChartData())),
          ]),
        );
        final chart2 = _card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Curva Sazonal de Volume x Riscos',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            SizedBox(height: 260, child: LineChart(_lineChartData())),
          ]),
        );
        return wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: chart1),
          const SizedBox(width: 18),
          Expanded(child: chart2),
        ])
            : Column(children: [chart1, const SizedBox(height: 18), chart2]);
      }),
    );
  }

  BarChartData _barChartData() => BarChartData(
    maxY: 16,
    gridData: const FlGridData(show: true, drawVerticalLine: false),
    borderData: FlBorderData(show: false),
    titlesData: FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 34,
          getTitlesWidget: (v, meta) => Text('${v.toInt()}%',
              style: TextStyle(fontSize: 10, color: _secondaryText)),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          getTitlesWidget: (v, meta) {
            const labels = ['BA', 'PE', 'RJ', 'MG', 'RS', 'SP'];
            final i = v.toInt();
            return i >= 0 && i < labels.length
                ? Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(labels[i], style: const TextStyle(fontSize: 11)),
            )
                : const SizedBox.shrink();
          },
        ),
      ),
    ),
    barGroups: [14.2, 12.8, 8.5, 5.1, 4.2, 3.1]
        .asMap()
        .entries
        .map((e) => BarChartGroupData(x: e.key, barRods: [
      BarChartRodData(
        toY: e.value,
        color: blue,
        width: 22,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
      ),
    ]))
        .toList(),
  );

  LineChartData _lineChartData() => LineChartData(
    minY: 0,
    maxY: 100,
    gridData: const FlGridData(show: true, drawVerticalLine: false),
    borderData: FlBorderData(show: false),
    titlesData: FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 34,
          getTitlesWidget: (v, meta) => Text('${v.toInt()}',
              style: TextStyle(fontSize: 10, color: _secondaryText)),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          getTitlesWidget: (v, meta) {
            const labels = ['Jan', 'Mar', 'Mai', 'Jul', 'Set', 'Nov', 'Dez'];
            final i = v.toInt();
            return i >= 0 && i < labels.length
                ? Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(labels[i], style: const TextStyle(fontSize: 10))
            )
                : const SizedBox.shrink();
          },
        ),
      ),
    ),
    lineBarsData: [
      LineChartBarData(
        spots: const [
          FlSpot(0, 20), FlSpot(1, 22), FlSpot(2, 35),
          FlSpot(3, 25), FlSpot(4, 30), FlSpot(5, 85), FlSpot(6, 70),
        ],
        isCurved: true,
        color: const Color(0xFFDC2626),
        barWidth: 3,
        dotData: const FlDotData(show: true),
        belowBarData: BarAreaData(show: false),
      ),
    ],
  );

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
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
      ),
    );
  }
}
