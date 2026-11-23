part of 'dashboard_screen.dart';

extension _DashboardSimulatorScreen on _DashboardScreenState {
  Widget _buildSimulator() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          _buildFormCard(),
          if (_simulatorController.baseResult != null) ...[
            const SizedBox(height: 18),
            _buildAlternativeScenarioSection(),
            const SizedBox(height: 18),
            _buildSensitivitySection(),
          ],
          const SizedBox(height: 18),
          _buildResults(),
        ],
      ),
    );
  }

  Widget _buildSensitivitySection() {
    final base = _simulatorController.baseScenario!;
    final originalDays = DateTime(
      base.estimatedDeliveryAt.year,
      base.estimatedDeliveryAt.month,
      base.estimatedDeliveryAt.day,
    )
        .difference(DateTime(
          base.dispatchedAt.year,
          base.dispatchedAt.month,
          base.dispatchedAt.day,
        ))
        .inDays;
    if (_sensitivityStartController.text.isEmpty &&
        _sensitivityEndController.text.isEmpty) {
      final start =
          (originalDays - SimulatorSensitivityController.defaultBeforeDays)
              .clamp(0, 100000);
      _sensitivityStartController.text = start.toString();
      _sensitivityEndController.text =
          (originalDays + SimulatorSensitivityController.defaultAfterDays)
              .toString();
    }
    final state = _sensitivityController.status;
    final points = _sensitivityController.points;
    final scores =
        points.map((point) => point.result.delayProbability).toList();
    final minScore =
        scores.isEmpty ? 0.0 : scores.reduce((a, b) => a < b ? a : b);
    final maxScore =
        scores.isEmpty ? 1.0 : scores.reduce((a, b) => a > b ? a : b);
    final yPadding =
        scores.isEmpty ? .1 : ((maxScore - minScore) * .15).clamp(.02, .15);
    final originalPoint = points
        .where((point) => point.remainingDays == originalDays)
        .firstOrNull;
    final alternativeDays = _simulatorController.alternativeScenario == null
        ? null
        : DateTime(
            _simulatorController.alternativeScenario!.estimatedDeliveryAt.year,
            _simulatorController.alternativeScenario!.estimatedDeliveryAt.month,
            _simulatorController.alternativeScenario!.estimatedDeliveryAt.day,
          )
            .difference(DateTime(
              _simulatorController.alternativeScenario!.dispatchedAt.year,
              _simulatorController.alternativeScenario!.dispatchedAt.month,
              _simulatorController.alternativeScenario!.dispatchedAt.day,
            ))
            .inDays;
    String scorePercent(double score, {int decimals = 1}) {
      final text = (score * 100).toStringAsFixed(decimals).replaceAll('.', ',');
      return '$text%';
    }

    String tooltipLabelFor(int days) {
      if (days == originalDays) return 'Cenário original';
      if (days == alternativeDays) return 'Cenário alternativo';
      return '';
    }

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Análise de sensibilidade',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text(
            'Executa inferências reais mantendo os demais atributos do cenário original constantes. O score pode oscilar porque o Random Forest não impõe monotonicidade.',
            style: TextStyle(fontSize: 12, color: _secondaryText),
          ),
          const SizedBox(height: 12),
          Text('Prazo original: $originalDays dias'),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (context, constraints) {
            final width = constraints.maxWidth > 460
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: width,
                  child: _textField(
                    controller: _sensitivityStartController,
                    label: 'Prazo inicial (dias)',
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _markSensitivityInputsChanged(),
                    enabled: !stateIsLoading,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _textField(
                    controller: _sensitivityEndController,
                    label: 'Prazo final (dias)',
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _markSensitivityInputsChanged(),
                    enabled: !stateIsLoading,
                  ),
                ),
              ],
            );
          }),
          const SizedBox(height: 8),
          Text(
              'Intervalo: ${_sensitivityStartController.text} a ${_sensitivityEndController.text} dias${_sensitivityDirty ? ' (não analisado)' : ''}',
              style: TextStyle(fontSize: 12, color: _secondaryText)),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: stateIsLoading ? null : _analyzeSensitivity,
            icon: stateIsLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.show_chart),
            label: Text(
                stateIsLoading ? 'Analisando prazos...' : 'Analisar prazos'),
          ),
          if (state == SimulatorSensitivityStatus.error &&
              _sensitivityController.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                      child: Text(
                          'Análise indisponível: ${_sensitivityController.error}',
                          style: const TextStyle(
                              color: Colors.red, fontSize: 12))),
                  TextButton(
                      onPressed: _analyzeSensitivity,
                      child: const Text('Tentar novamente')),
                ],
              ),
            ),
          if (state == SimulatorSensitivityStatus.stale)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                  'O cenário original mudou. Execute a análise novamente.',
                  style: TextStyle(color: _secondaryText, fontSize: 12)),
            ),
          if (state == SimulatorSensitivityStatus.success &&
              points.isNotEmpty &&
              !_sensitivityDirty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 260,
              child: LineChart(
                LineChartData(
                  minX: points.first.remainingDays.toDouble(),
                  maxX: points.last.remainingDays.toDouble(),
                  minY: (minScore - yPadding).clamp(0.0, 1.0),
                  maxY: (maxScore + yPadding).clamp(0.0, 1.0),
                  lineTouchData: LineTouchData(
                    enabled: true,
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => spots.map((spot) {
                        final days = spot.x.round();
                        final scenarioLabel = tooltipLabelFor(days);
                        return LineTooltipItem(
                          'Prazo: $days dias\n'
                          'Score previsto: ${scorePercent(spot.y)}'
                          '${scenarioLabel.isEmpty ? '' : '\n$scenarioLabel'}',
                          const TextStyle(color: Colors.white),
                        );
                      }).toList(),
                    ),
                  ),
                  gridData: const FlGridData(show: true),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      axisNameWidget: const Text('Score de atraso'),
                      axisNameSize: 28,
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 48,
                        getTitlesWidget: (value, meta) => Text(
                          scorePercent(value, decimals: 0),
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      axisNameWidget:
                          const Text('Prazo disponível para entrega (dias)'),
                      axisNameSize: 32,
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        interval: 1,
                        getTitlesWidget: (value, meta) => SideTitleWidget(
                          axisSide: meta.axisSide,
                          space: 6,
                          child: Text(
                            value.round().toString(),
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                    ),
                    topTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (final point in points)
                          FlSpot(point.remainingDays.toDouble(),
                              point.result.delayProbability)
                      ],
                      isCurved: false,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, bar, index) {
                          final isOriginal =
                              originalPoint != null && spot.x == originalDays;
                          final isAlternative = alternativeDays != null &&
                              spot.x == alternativeDays;
                          return FlDotCirclePainter(
                              radius: isOriginal || isAlternative ? 5 : 3,
                              color: isOriginal
                                  ? Colors.orange
                                  : (isAlternative ? Colors.purple : blue),
                              strokeWidth: 1,
                              strokeColor: Colors.white);
                        },
                      ),
                      color: blue,
                      barWidth: 2,
                    ),
                  ],
                ),
              ),
            ),
            Text('Modelo: ${_sensitivityController.modelVersion ?? '—'}'),
            Text(
                'Marcadores: prazo original${alternativeDays == null ? '' : ' e prazo alternativo'}.'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _sensitivityLegendItem(blue, 'Score previsto de atraso'),
                _sensitivityLegendItem(
                    Colors.orange, 'Prazo original ($originalDays dias)'),
                if (alternativeDays != null)
                  _sensitivityLegendItem(Colors.purple,
                      'Prazo alternativo ($alternativeDays dias)'),
              ],
            ),
            const SizedBox(height: 4),
            const Text('Como interpretar este gráfico?',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 3),
            const Text(
                'O eixo horizontal representa o número de dias disponíveis entre o despacho e a entrega prevista. O eixo vertical mostra o score de atraso estimado pelo modelo. Em cada ponto, apenas o prazo de entrega foi alterado; os demais atributos permaneceram constantes.'),
            const SizedBox(height: 3),
            Text(
                'Scores menores indicam menor risco estimado pelo modelo. Como o Random Forest não garante monotonicidade, o score pode apresentar oscilações locais conforme o prazo aumenta. Cada ponto é uma inferência real e o score não é uma probabilidade calibrada.',
                style: TextStyle(fontSize: 11, color: _secondaryText)),
          ],
        ],
      ),
    );
  }

  bool get stateIsLoading => _sensitivityController.isLoading;

  Widget _sensitivityLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  Widget _buildAlternativeScenarioSection() {
    if (!_alternativeVisible) {
      return _card(
        child: FilledButton.icon(
          onPressed: _createAlternativeScenario,
          icon: const Icon(Icons.add_circle_outline),
          label: const Text('Criar cenário alternativo'),
        ),
      );
    }
    String? numberValidator(String? raw, String label, {bool required = true}) {
      final text = (raw ?? '').trim();
      if (text.isEmpty) return required ? 'Informe $label.' : null;
      final value = _parseNumber(text);
      if (value == null || !value.isFinite || value < 0) {
        return 'Informe $label válido.';
      }
      return null;
    }

    String? cepValidator(String? raw) {
      try {
        DispatchSimulation.parseOriginCeps(raw ?? '');
        return null;
      } on FormatException catch (error) {
        return error.message;
      }
    }

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.alt_route, color: blue),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Cenário alternativo',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              TextButton.icon(
                onPressed:
                    _alternativeAnalyzing ? null : _restoreAlternativeScenario,
                icon: const Icon(Icons.restore),
                label: const Text('Restaurar valores originais'),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            'Edite uma cópia independente do cenário original. A comparação mostra diferenças do modelo e não comprova causalidade.',
            style: TextStyle(fontSize: 12, color: _secondaryText),
          ),
          const SizedBox(height: 12),
          Form(
            key: _alternativeFormKey,
            child: LayoutBuilder(builder: (context, constraints) {
              final half = constraints.maxWidth > 460
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: constraints.maxWidth,
                    child: _textField(
                      controller: _alternativeOriginController,
                      label: 'CEPs de origem alternativos',
                      validator: cepValidator,
                      onChanged: (_) => _alternativeInputsChanged(),
                      enabled: !_alternativeAnalyzing,
                    ),
                  ),
                  SizedBox(
                    width: half,
                    child: _textField(
                      controller: _alternativeDestinationController,
                      label: 'CEP de destino alternativo',
                      validator: cepValidator,
                      onChanged: (_) => _alternativeInputsChanged(),
                      enabled: !_alternativeAnalyzing,
                    ),
                  ),
                  for (final item in [
                    (_alternativePurchaseAtController, 'Data da compra'),
                    (_alternativeDispatchedAtController, 'Data do despacho'),
                    (
                      _alternativeEstimatedDeliveryAtController,
                      'Data prometida'
                    ),
                  ])
                    SizedBox(
                      width: half,
                      child: _alternativeDateField(item.$1, item.$2),
                    ),
                  SizedBox(
                    width: half,
                    child: _textField(
                      controller: _alternativeWeightController,
                      label: 'Peso alternativo (kg)',
                      validator: (value) => numberValidator(value, 'o peso'),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => _alternativeInputsChanged(),
                      enabled: !_alternativeAnalyzing,
                    ),
                  ),
                  SizedBox(
                    width: half,
                    child: _textField(
                      controller: _alternativeVolumeController,
                      label: 'Volume alternativo (cm³, opcional)',
                      validator: (value) =>
                          numberValidator(value, 'o volume', required: false),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => _alternativeInputsChanged(),
                      enabled: !_alternativeAnalyzing,
                    ),
                  ),
                  SizedBox(
                    width: half,
                    child: _textField(
                      controller: _alternativeItemsCountController,
                      label: 'Itens alternativos',
                      validator: (value) {
                        final count = int.tryParse((value ?? '').trim());
                        return count == null || count < 1 || count > 10000
                            ? 'Informe de 1 a 10.000 itens.'
                            : null;
                      },
                      keyboardType: TextInputType.number,
                      onChanged: (_) => _alternativeInputsChanged(),
                      enabled: !_alternativeAnalyzing,
                    ),
                  ),
                  SizedBox(
                    width: half,
                    child: _textField(
                      controller: _alternativeDeclaredValueController,
                      label: 'Preço alternativo (R\$)',
                      validator: (value) => numberValidator(value, 'o preço'),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => _alternativeInputsChanged(),
                      enabled: !_alternativeAnalyzing,
                    ),
                  ),
                  SizedBox(
                    width: half,
                    child: _textField(
                      controller: _alternativeFreightValueController,
                      label: 'Frete alternativo (R\$)',
                      validator: (value) => numberValidator(value, 'o frete'),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => _alternativeInputsChanged(),
                      enabled: !_alternativeAnalyzing,
                    ),
                  ),
                ],
              );
            }),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _alternativeAnalyzing ? null : _analyzeAlternative,
            icon: _alternativeAnalyzing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.compare_arrows),
            label: Text(_alternativeAnalyzing
                ? 'Consultando modelo...'
                : 'Prever atraso neste cenário'),
          ),
          if (!_alternativeAnalyzing &&
              _simulatorController.alternativeError != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Previsão alternativa indisponível: ${_simulatorController.alternativeError}',
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
          if (_alternativeVisible &&
              !_alternativeDirty &&
              _simulatorController.comparison != null)
            _buildScenarioComparison(),
          if (_alternativeDirty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                  'Parâmetros alterados. Execute uma nova previsão para atualizar a comparação.',
                  style: TextStyle(color: _secondaryText, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _alternativeDateField(TextEditingController controller, String label) {
    return _dateTimeField(
      controller: controller,
      label: label,
      onChanged: _alternativeInputsChanged,
    );
  }

  Widget _buildScenarioComparison() {
    final comparison = _simulatorController.comparison!;
    final baseScenario = comparison.baseScenario;
    final alternativeScenario = comparison.alternativeScenario;
    String formatDate(DateTime value) => SimulatorDateFormat.format(value);
    String formatValue(String field, SimulatorScenario scenario) {
      switch (field) {
        case 'originCeps':
          return scenario.originCeps.join(', ');
        case 'destinationCep':
          return scenario.destinationCep;
        case 'purchaseAt':
          return formatDate(scenario.purchaseAt);
        case 'dispatchedAt':
          return formatDate(scenario.dispatchedAt);
        case 'estimatedDeliveryAt':
          return formatDate(scenario.estimatedDeliveryAt);
        case 'weightKg':
          return '${scenario.weightKg.toStringAsFixed(3)} kg';
        case 'volumeCm3':
          return scenario.volumeCm3 == null
              ? 'não informado'
              : '${scenario.volumeCm3!.toStringAsFixed(2)} cm³';
        case 'itemsCount':
          return scenario.itemsCount.toString();
        case 'price':
          return 'R\$ ${scenario.price.toStringAsFixed(2)}';
        case 'freightValue':
          return 'R\$ ${scenario.freightValue.toStringAsFixed(2)}';
        default:
          return '—';
      }
    }

    const fieldLabels = <String, String>{
      'originCeps': 'CEPs de origem',
      'destinationCep': 'CEP de destino',
      'purchaseAt': 'Data da compra',
      'dispatchedAt': 'Data do despacho',
      'estimatedDeliveryAt': 'Data prometida',
      'weightKg': 'Peso total',
      'volumeCm3': 'Volume total',
      'itemsCount': 'Quantidade de itens',
      'price': 'Valor do pedido',
      'freightValue': 'Valor do frete',
    };
    Widget resultCard(String title, dynamic result) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                    'Score previsto de atraso: ${(result.delayProbability * 100).toStringAsFixed(1)}%'),
                Text(result.predictedLate
                    ? 'Classificação: acima do threshold'
                    : 'Classificação: abaixo do threshold'),
                Text(
                    'Entrega prevista: ${formatDate(result == comparison.base ? baseScenario.estimatedDeliveryAt : alternativeScenario.estimatedDeliveryAt)}'),
                Text(
                    'Prazo disponível: ${result == comparison.base ? comparison.baseRemainingDays : comparison.alternativeRemainingDays} dias'),
                Text(
                    'Threshold: ${(result.threshold * 100).toStringAsFixed(1)}%'),
                Text('Modelo: ${result.modelVersion}'),
                ...result.warnings.map<Widget>((warning) => Text(
                    'Aviso: $warning',
                    style: TextStyle(fontSize: 11, color: _secondaryText))),
              ],
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Comparação de cenários',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (context, constraints) {
            final row = Row(children: [
              resultCard('Cenário original', comparison.base),
              const SizedBox(width: 10),
              resultCard('Cenário alternativo', comparison.alternative),
            ]);
            return constraints.maxWidth < 600
                ? Column(children: [
                    resultCard('Cenário original', comparison.base),
                    const SizedBox(height: 10),
                    resultCard('Cenário alternativo', comparison.alternative)
                  ])
                : row;
          }),
          const SizedBox(height: 10),
          Text(
              'Diferença: ${comparison.differencePercentagePoints >= 0 ? '+' : ''}${comparison.differencePercentagePoints.toStringAsFixed(2)} pontos percentuais'),
          Text(
              'Diferença de prazo: ${comparison.remainingDaysDifference >= 0 ? '+' : ''}${comparison.remainingDaysDifference} dias'),
          const SizedBox(height: 10),
          const Text('O que mudou?',
              style: TextStyle(fontWeight: FontWeight.bold)),
          Text(
              'Campos alterados: ${comparison.changedFields.isEmpty ? 'nenhum' : comparison.changedFields.join(', ')}'),
          if (comparison.changedFields.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: _border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    child: Row(
                      children: [
                        Expanded(flex: 2, child: Text('Variável')),
                        Expanded(child: Text('Original')),
                        Expanded(child: Text('Alternativo')),
                      ],
                    ),
                  ),
                  for (final field in comparison.changedFields)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 7),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(fieldLabels[field] ?? field,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                          ),
                          Expanded(
                              child: Text(formatValue(field, baseScenario))),
                          Expanded(
                              child: Text(
                                  formatValue(field, alternativeScenario))),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (comparison.shouldExplainHigherScore) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade700),
              ),
              child: const Text(
                'Você ampliou o prazo de entrega, mas o modelo retornou um score maior. O Random Forest utiliza padrões históricos e pode apresentar oscilações. Isso não significa que ampliar o prazo causou um aumento do risco real.',
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
              'A comparação mostra diferenças nas previsões do modelo e não comprova uma relação causal entre as alterações e o atraso real.',
              style: TextStyle(fontSize: 11, color: _secondaryText)),
        ],
      ),
    );
  }

  Widget _buildFormCard() {
    String? numberValidator(String? raw, String label,
        {bool required = true, bool positive = false}) {
      final text = (raw ?? '').trim();
      if (text.isEmpty) return required ? 'Informe $label.' : null;
      final value = _parseNumber(text);
      if (value == null ||
          !value.isFinite ||
          value < 0 ||
          (positive && value == 0)) {
        return 'Informe $label válido.';
      }
      return null;
    }

    String? originValidator(String? raw) {
      try {
        final origins = DispatchSimulation.parseOriginCeps(raw ?? '');
        final items = int.tryParse(_itemsCountController.text.trim());
        if (items != null && origins.length > items) {
          return 'Há mais vendedores do que itens no pedido.';
        }
      } on FormatException catch (error) {
        return error.message;
      }
      return null;
    }

    String? destinationValidator(String? raw) {
      try {
        DispatchSimulation.normalizeCep(raw ?? '');
      } on FormatException catch (error) {
        return error.message;
      }
      return null;
    }

    return _card(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildOrderSelection(),
            const SizedBox(height: 12),
            const _SectionTitle(
              icon: Icons.tune,
              title: 'Dados do Pedido',
              subtitle:
                  'Preencha os dados para previsão de atraso e simulação de despacho.',
            ),
            const SizedBox(height: 8),
            Text(
              'Os CEPs alimentam a previsão de atraso e a identificação automática dos hubs de origem e destino. Para pedidos com vários vendedores, informe um CEP por vendedor; o primeiro CEP de origem será usado para o despacho.',
              style: TextStyle(fontSize: 12, color: _secondaryText),
            ),
            const SizedBox(height: 18),
            LayoutBuilder(builder: (context, constraints) {
              final split = constraints.maxWidth > 460;
              final half = split
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 14,
                children: [
                  SizedBox(
                    width: constraints.maxWidth,
                    child: _textField(
                      controller: _originController,
                      label: 'CEP(s) de origem dos vendedores',
                      helper: 'Um CEP por vendedor, separados por vírgula.',
                      validator: originValidator,
                      keyboardType: TextInputType.text,
                      onChanged: (_) => _simulationInputsChanged(),
                      enabled: !_isAnalyzing,
                    ),
                  ),
                  SizedBox(
                    width: half,
                    child: _textField(
                      controller: _destinationController,
                      label: 'CEP de destino do cliente',
                      validator: destinationValidator,
                      keyboardType: TextInputType.text,
                      onChanged: (_) => _simulationInputsChanged(),
                      enabled: !_isAnalyzing,
                    ),
                  ),
                  SizedBox(
                      width: half,
                      child: _dateTimeField(
                          controller: _purchaseAtController,
                          label: 'Data/hora da compra')),
                  SizedBox(
                      width: half,
                      child: _dateTimeField(
                          controller: _dispatchedAtController,
                          label: 'Data/hora do despacho')),
                  SizedBox(
                      width: half,
                      child: _dateTimeField(
                          controller: _estimatedDeliveryAtController,
                          label: 'Data/hora prometida de entrega')),
                  SizedBox(
                    width: half,
                    child: _textField(
                      controller: _weightController,
                      label: 'Peso total do pedido (kg)',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: (value) =>
                          numberValidator(value, 'o peso', positive: true),
                      onChanged: (_) => _simulationInputsChanged(),
                      enabled: !_isAnalyzing,
                    ),
                  ),
                  SizedBox(
                    width: half,
                    child: _textField(
                      controller: _volumeController,
                      label: 'Volume total do pedido (cm³, opcional)',
                      helper:
                          'Se omitido, o pipeline aplica a imputação treinada e retorna um aviso.',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: (value) =>
                          numberValidator(value, 'o volume', required: false),
                      onChanged: (_) => _simulationInputsChanged(),
                      enabled: !_isAnalyzing,
                    ),
                  ),
                  SizedBox(
                    width: half,
                    child: _textField(
                      controller: _itemsCountController,
                      label: 'Quantidade de itens do pedido',
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        final count = int.tryParse((value ?? '').trim());
                        if (count == null || count < 1 || count > 10000) {
                          return 'Informe de 1 a 10.000 itens.';
                        }
                        return null;
                      },
                      onChanged: (_) => _simulationInputsChanged(),
                      enabled: !_isAnalyzing,
                    ),
                  ),
                  SizedBox(
                    width: half,
                    child: _textField(
                      controller: _declaredValueController,
                      label: 'Preço total do pedido (R\$)',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: (value) => numberValidator(value, 'o preço'),
                      onChanged: (_) => _simulationInputsChanged(),
                      enabled: !_isAnalyzing,
                    ),
                  ),
                  SizedBox(
                    width: half,
                    child: _textField(
                      controller: _freightValueController,
                      label: 'Frete total do pedido (R\$)',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: (value) => numberValidator(value, 'o frete'),
                      onChanged: (_) => _simulationInputsChanged(),
                      enabled: !_isAnalyzing,
                    ),
                  ),
                ],
              );
            }),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed:
                  _isAnalyzing || _loadingSelectedOrder ? null : _analyze,
              icon: _isAnalyzing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: Text(_isAnalyzing
                    ? 'Executando simulação logística...'
                    : 'Simular operação logística'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    final current = _currentScenario;
    final response = current?['response'] as Map<String, dynamic>?;
    final currentSource = response?['source']?.toString();
    final scenario = current ?? _lastAttempt;

    return Column(
      children: [
        // ===== PREDICTION PANEL =====
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Previsão de Atraso',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(builder: (context, constraints) {
                final compact = constraints.maxWidth < 420;
                final description = Column(
                  crossAxisAlignment: compact
                      ? CrossAxisAlignment.center
                      : CrossAxisAlignment.start,
                  children: [
                    Text('RESULTADO DA SIMULAÇÃO',
                        style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 1,
                            color: _secondaryText,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 7),
                    Text(_riskTitle,
                        textAlign: compact ? TextAlign.center : TextAlign.start,
                        style: TextStyle(
                            fontSize: 20,
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
                      borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _riskProbability == null
                            ? '—'
                            : '${(_riskProbability! * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            color: _riskColor),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                            _riskProbability == null
                                ? 'SEM PREVISÃO'
                                : 'SCORE PREVISTO DE ATRASO',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: _secondaryText)),
                      ),
                    ],
                  ),
                );
                return compact
                    ? Column(children: [
                        description,
                        const SizedBox(height: 18),
                        score
                      ])
                    : Row(children: [
                        Expanded(child: description),
                        const SizedBox(width: 18),
                        score
                      ]);
              }),
              if (response != null) ...[
                const SizedBox(height: 14),
                const Divider(height: 16),
                const SizedBox(height: 8),
                const Text('Retorno do modelo',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                    'Decisão: ${_predictedLate == true ? 'risco acima do limiar' : 'risco abaixo do limiar'}'),
                Text(
                    'Limiar de decisão: ${((_lastThreshold ?? 0) * 100).toStringAsFixed(1)}%'),
                Text('Versão: ${_modelVersion ?? 'não informada'}'),
                Text('Fonte do modelo: ${currentSource ?? 'não informada'}'),
                if (response['synthetic'] == true)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Atenção: este modelo usa dados sintéticos; o resultado não representa uma previsão operacional.',
                      style: TextStyle(color: Colors.deepOrange),
                    ),
                  ),
                if (_warnings.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ..._warnings.map((warning) => Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text('Aviso: $warning',
                            style:
                                TextStyle(fontSize: 12, color: _secondaryText)),
                      )),
                ],
              ],
            ],
          ),
        ),

        // ===== DISPATCH PANEL =====
        const SizedBox(height: 18),
        _buildDispatchPanel(),

        // ===== INTEGRATED MAP =====
        if (_dispatchResult != null || _dispatchError != null) ...[
          const SizedBox(height: 18),
          _buildDispatchMap(),
        ],

        // ===== SCENARIO DETAILS (legacy) =====
        if (scenario != null) ...[
          const SizedBox(height: 18),
          _scenarioCard(
            scenario,
            title: current == null
                ? 'Parâmetros da tentativa atual'
                : 'Parâmetros enviados nesta simulação',
          ),
        ],
        if (_previousScenario != null) ...[
          const SizedBox(height: 18),
          _comparisonCard(current),
        ],
      ],
    );
  }

  /// Dispatch results panel with hub cards, distances and warnings.
  Widget _buildDispatchPanel() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Despacho entre Hubs',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Os hubs de origem e destino são selecionados automaticamente com base nos CEPs informados.',
            style: TextStyle(fontSize: 12, color: _secondaryText),
          ),
          const SizedBox(height: 12),

          // Loading state
          if (_dispatchLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: CircularProgressIndicator(),
              ),
            ),

          // Error state
          if (!_dispatchLoading &&
              _dispatchError != null &&
              _dispatchResult == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _dispatchError!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

          // Success state
          if (_dispatchResult != null) _buildDispatchResults(),
        ],
      ),
    );
  }

  Widget _buildDispatchResults() {
    final data = _dispatchResult!;
    final origin = data['origin'] as Map<String, dynamic>? ?? {};
    final dest = data['destination'] as Map<String, dynamic>? ?? {};
    final originHub = data['origin_hub'] as Map<String, dynamic>? ?? {};
    final destHub = data['destination_hub'] as Map<String, dynamic>? ?? {};
    final distances = data['distances'] as Map<String, dynamic>? ?? {};
    final sameHub = data['same_hub'] as bool? ?? false;
    final warnings = data['warnings'] as List? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Same hub warning
        if (sameHub)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Origem e destino estão associados ao mesmo hub: ${originHub['name'] ?? originHub['id']}',
                    style: const TextStyle(color: Colors.orange, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),

        // Hub cards
        LayoutBuilder(builder: (context, constraints) {
          final sideBySide = constraints.maxWidth > 500;
          return sideBySide
              ? Row(
                  children: [
                    Expanded(
                      child: _hubCard('Hub de Origem', originHub, Colors.blue),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _hubCard('Hub de Destino', destHub, Colors.green),
                    ),
                  ],
                )
              : Column(
                  children: [
                    _hubCard('Hub de Origem', originHub, Colors.blue),
                    const SizedBox(height: 8),
                    _hubCard('Hub de Destino', destHub, Colors.green),
                  ],
                );
        }),

        const SizedBox(height: 12),

        // Distances
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _surfaceAlt,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Distâncias',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              // Use hub names in distance labels
              _distanceRow(
                'CEP de origem → ${originHub['name']?.toString() ?? originHub['code']?.toString() ?? 'Hub origem'}',
                distances['origin_to_origin_hub_km'],
              ),
              _distanceRow(
                'CEP de destino → ${destHub['name']?.toString() ?? destHub['code']?.toString() ?? 'Hub destino'}',
                distances['destination_to_dest_hub_km'],
              ),
              _distanceRow(
                '${originHub['name']?.toString() ?? originHub['code']?.toString() ?? 'Hub origem'} → ${destHub['name']?.toString() ?? destHub['code']?.toString() ?? 'Hub destino'}',
                distances['hub_to_hub_haversine_km'],
                subtitle: 'Distância geográfica (Haversine)',
              ),
              if (distances['route_distance_km'] != null)
                _distanceRow(
                  'Rota rodoviária',
                  distances['route_distance_km'],
                  color: Colors.green,
                  subtitle: 'Calculada via OpenRouteService',
                ),
              if (distances['route_duration_seconds'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Tempo estimado: ${_formatDuration(distances['route_duration_seconds'])}',
                    style: TextStyle(color: _secondaryText, fontSize: 13),
                  ),
                ),
            ],
          ),
        ),

        // Warnings — improved to distinguish Haversine vs road distance
        if (warnings.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Avisos',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ...warnings.map((w) {
                  final text = w.toString();
                  // Improve the OpenRouteService key missing warning
                  if (text.contains('OPENROUTE') ||
                      text.contains('OpenRouteService não configurada')) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 4, left: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• ',
                              style: TextStyle(
                                  color: Colors.orange, fontSize: 12)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Rota rodoviária indisponível',
                                  style: TextStyle(
                                      color: Colors.orange,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'A chave API do OpenRouteService não está configurada. A distância entre hubs apresentada é geográfica (Haversine), em linha reta, e não representa a distância rodoviária real.',
                                  style: const TextStyle(
                                      color: Colors.orange, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  // Improve the Haversine fallback warning
                  if (text.contains('Haversine') ||
                      text.contains('linha reta')) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 4, left: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• ',
                              style: TextStyle(
                                  color: Colors.orange, fontSize: 12)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Distância geográfica (Haversine)',
                                  style: TextStyle(
                                      color: Colors.orange,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'A distância entre hubs é calculada em linha reta. A rota rodoviária não pôde ser calculada porque o serviço de roteamento está indisponível.',
                                  style: TextStyle(
                                      color: Colors.orange, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  // Generic warning
                  return Padding(
                    padding: const EdgeInsets.only(top: 3, left: 8),
                    child: Text(
                      '• $text',
                      style:
                          const TextStyle(color: Colors.orange, fontSize: 12),
                    ),
                  );
                }),
              ],
            ),
          ),
      ],
    );
  }

  Widget _hubCard(String title, Map<String, dynamic> hub, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: color, fontSize: 13)),
          const SizedBox(height: 4),
          Text(hub['name']?.toString() ?? 'N/A',
              style: const TextStyle(fontWeight: FontWeight.w500)),
          Text('${hub['city'] ?? ''}, ${hub['state'] ?? ''}',
              style: const TextStyle(fontSize: 12)),
          Text('ID: ${hub['id'] ?? ''}',
              style: TextStyle(fontSize: 11, color: _secondaryText)),
        ],
      ),
    );
  }

  Widget _distanceRow(String label, dynamic value,
      {Color? color, String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(fontSize: 13, color: _secondaryText)),
                    if (subtitle != null)
                      Text(subtitle,
                          style: const TextStyle(
                              fontSize: 10, color: Colors.grey)),
                  ],
                ),
              ),
              Text(
                value != null
                    ? '${(value as num).toDouble().toStringAsFixed(2)} km'
                    : 'N/A',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: color ?? _primaryText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(dynamic seconds) {
    if (seconds == null) return 'N/A';
    final s = seconds as int;
    final hours = s ~/ 3600;
    final mins = (s % 3600) ~/ 60;
    if (hours > 0) return '${hours}h ${mins}min';
    return '${mins}min';
  }

  /// Integrated map showing origin, destination, hubs and route.
  Widget _buildDispatchMap() {
    if (_dispatchResult == null) {
      return const SizedBox.shrink();
    }

    final data = _dispatchResult!;
    final origin = data['origin'] as Map<String, dynamic>? ?? {};
    final dest = data['destination'] as Map<String, dynamic>? ?? {};
    final originHub = data['origin_hub'] as Map<String, dynamic>? ?? {};
    final destHub = data['destination_hub'] as Map<String, dynamic>? ?? {};
    final routeData = data['route'] as Map<String, dynamic>?;
    final warnings = data['warnings'] as List? ?? [];
    final sameHub = data['same_hub'] as bool? ?? false;

    final markers = <Marker>[];
    final allPoints = <LatLng>[];

    LatLng? toLatLng(Map<String, dynamic> point) {
      if (point.isEmpty ||
          point['latitude'] == null ||
          point['longitude'] == null) {
        return null;
      }
      return LatLng(
        (point['latitude'] as num).toDouble(),
        (point['longitude'] as num).toDouble(),
      );
    }

    // Origin location
    final originPoint = toLatLng(origin);
    if (originPoint != null) {
      markers.add(Marker(
        point: originPoint,
        child: const Icon(Icons.location_on, color: Colors.grey, size: 30),
      ));
      allPoints.add(originPoint);
    }
    // Destination location
    final destPoint = toLatLng(dest);
    if (destPoint != null) {
      markers.add(Marker(
        point: destPoint,
        child: const Icon(Icons.location_on, color: Colors.purple, size: 30),
      ));
      allPoints.add(destPoint);
    }
    // Origin hub
    final originHubPoint = toLatLng(originHub);
    if (originHubPoint != null) {
      markers.add(Marker(
        point: originHubPoint,
        child: const Icon(Icons.local_shipping, color: Colors.blue, size: 36),
      ));
      allPoints.add(originHubPoint);
    }
    // Destination hub
    final destHubPoint = toLatLng(destHub);
    if (destHubPoint != null) {
      markers.add(Marker(
        point: destHubPoint,
        child: const Icon(Icons.local_shipping, color: Colors.green, size: 36),
      ));
      allPoints.add(destHubPoint);
    }

    // Route polyline from OpenRouteService geometry
    final polylines = <Polyline>[];
    bool routeAvailable = false;
    bool routeFailed = false;
    String? routeFailureReason;

    if (sameHub) {
      // Same hub — no route needed
      routeFailed = false;
    } else if (routeData != null && routeData['geometry'] != null) {
      final geometry = routeData['geometry'];
      // Debug: log geometry type for troubleshooting
      debugPrint('Dispatch map: geometry type = ${geometry.runtimeType}');
      if (geometry is Map<String, dynamic> && geometry['coordinates'] is List) {
        final coordsList = geometry['coordinates'] as List;
        debugPrint(
            'Dispatch map: coordinates count = ${coordsList.length}, first item type = ${coordsList.isNotEmpty ? coordsList.first.runtimeType : "empty"}');
        // Convert coordinates: GeoJSON format is [longitude, latitude], but we need LatLng(latitude, longitude)
        // Accept any List that has at least 2 numeric elements, regardless of specific type
        final coords = <LatLng>[];
        for (final item in coordsList) {
          if (item is List && item.length >= 2) {
            try {
              final lng = (item[0] as num).toDouble();
              final lat = (item[1] as num).toDouble();
              if (lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) {
                coords.add(LatLng(lat, lng));
              } else {
                debugPrint(
                    'Dispatch map: skipping invalid coordinate [$lng, $lat]');
              }
            } catch (e) {
              debugPrint('Dispatch map: failed to convert coordinate: $e');
            }
          }
        }
        debugPrint(
            'Dispatch map: converted ${coords.length} valid coordinates');
        if (coords.length >= 2) {
          polylines.add(Polyline(
            points: coords,
            color: Colors.indigo,
            strokeWidth: 5,
          ));
          // Add route geometry points to allPoints for camera framing
          allPoints.addAll(coords);
          routeAvailable = true;
        } else {
          routeFailed = true;
          routeFailureReason = 'Geometria da rota com pontos insuficientes.';
        }
      } else {
        routeFailed = true;
        routeFailureReason = 'Geometria da rota em formato inválido.';
      }
    } else {
      // Check if route failed due to OpenRouteService issues
      final hasOpenRouteWarning = warnings.any((w) {
        final text = w.toString().toLowerCase();
        return text.contains('openroute') ||
            text.contains('haversine') ||
            text.contains('linha reta') ||
            text.contains('roteamento indisponível');
      });
      if (hasOpenRouteWarning) {
        routeFailed = true;
        routeFailureReason =
            'Rota rodoviária não disponível. Apenas distância geográfica (Haversine) está disponível.';
      }
    }

    // Calculate initial center and zoom from all points
    LatLng center = const LatLng(-14.235, -51.9253);
    double zoom = 4;
    if (allPoints.isNotEmpty) {
      double latMin = allPoints.first.latitude;
      double latMax = allPoints.first.latitude;
      double lngMin = allPoints.first.longitude;
      double lngMax = allPoints.first.longitude;
      for (final p in allPoints) {
        if (p.latitude < latMin) latMin = p.latitude;
        if (p.latitude > latMax) latMax = p.latitude;
        if (p.longitude < lngMin) lngMin = p.longitude;
        if (p.longitude > lngMax) lngMax = p.longitude;
      }
      center = LatLng((latMin + latMax) / 2, (lngMin + lngMax) / 2);
      // Calculate zoom based on bounding box
      final latDiff = latMax - latMin;
      final lngDiff = lngMax - lngMin;
      final maxDiff = latDiff > lngDiff ? latDiff : lngDiff;
      if (maxDiff > 10) {
        zoom = 4;
      } else if (maxDiff > 5) {
        zoom = 5;
      } else if (maxDiff > 2) {
        zoom = 6;
      } else if (maxDiff > 0.5) {
        zoom = 8;
      } else if (maxDiff > 0.1) {
        zoom = 10;
      } else if (maxDiff > 0.01) {
        zoom = 12;
      } else {
        zoom = 13;
      }
    }

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Mapa Logístico',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Pontos: origem (cinza), destino (roxo), hub de origem (azul), hub de destino (verde).',
            style: TextStyle(fontSize: 11, color: _secondaryText),
          ),
          if (routeAvailable)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Rota rodoviária calculada via OpenRouteService (origem → hub origem → hub destino → destino).',
                style: TextStyle(fontSize: 11, color: Colors.green.shade700),
              ),
            ),
          if (routeFailed && routeFailureReason != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Colors.orange, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        routeFailureReason,
                        style:
                            const TextStyle(color: Colors.orange, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 350,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: zoom,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  ),
                  MarkerLayer(markers: markers),
                  if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scenarioCard(Map<String, dynamic> scenario, {required String title}) {
    final payload = scenario['payload'] as Map<String, dynamic>;
    final route = scenario['route'] as Map<String, dynamic>;
    final origins = (route['origins'] as List).cast<Map<String, dynamic>>();
    final destination = route['destination'] as Map<String, dynamic>;
    String location(Map<String, dynamic> place) =>
        '${place['city']}, ${place['state']} (CEP ${place['cep']})';
    final volumeLabel = payload.containsKey('total_volume_cm3')
        ? '${payload['total_volume_cm3']} cm³'
        : 'não informado; imputado pelo pipeline';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Origem: ${origins.map(location).join('; ')}'),
            Text('Destino: ${location(destination)}'),
            Text(
                'Distância em linha reta: ${(route['distance_km'] as num).toStringAsFixed(1)} km'),
            Text(
                'Peso total: ${((payload['total_weight_g'] as num) / 1000).toStringAsFixed(3)} kg'),
            Text('Volume total: $volumeLabel'),
            Text(
                'Itens / vendedores: ${payload['items_count']} / ${payload['sellers_count']}'),
            Text(
                'Preço / frete: R\$ ${payload['price']} / R\$ ${payload['freight_value']}'),
            Text(
                'Compra: ${SimulatorDateFormat.format(SimulatorDateFormat.parse(payload['purchase_at'].toString())!)}'),
            Text(
                'Despacho: ${SimulatorDateFormat.format(SimulatorDateFormat.parse(payload['dispatched_at'].toString())!)}'),
            Text(
                'Entrega prometida: ${SimulatorDateFormat.format(SimulatorDateFormat.parse(payload['estimated_delivery_at'].toString())!)}'),
            const SizedBox(height: 6),
            Text(route['geolocation_source']?.toString() ?? '',
                style: TextStyle(fontSize: 11, color: _secondaryText)),
          ],
        ),
      ),
    );
  }

  Widget _comparisonCard(Map<String, dynamic>? current) {
    final previousResponse =
        _previousScenario!['response'] as Map<String, dynamic>;
    final previousProbability =
        (previousResponse['delay_probability'] as num).toDouble();
    final currentResponse = current?['response'] as Map<String, dynamic>?;
    final currentProbability =
        (currentResponse?['delay_probability'] as num?)?.toDouble();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Comparação com a execução anterior',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                  child: _comparisonValue('Anterior', previousProbability,
                      previousResponse['predicted_late'] as bool)),
              const SizedBox(width: 12),
              Expanded(
                child: currentProbability == null
                    ? const Text('Execução atual sem resultado.')
                    : _comparisonValue('Atual', currentProbability,
                        currentResponse!['predicted_late'] as bool),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _scenarioCard(_previousScenario!,
              title: 'Parâmetros da execução anterior'),
        ],
      ),
    );
  }

  Widget _comparisonValue(
          String label, double probability, bool predictedLate) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: _secondaryText)),
          Text(
            '${(probability * 100).toStringAsFixed(1)}% · ${predictedLate ? 'acima' : 'abaixo'} do limiar',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      );
}
