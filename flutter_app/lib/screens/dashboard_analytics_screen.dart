part of 'dashboard_screen.dart';

extension _DashboardAnalyticsScreen on _DashboardScreenState {
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

}
