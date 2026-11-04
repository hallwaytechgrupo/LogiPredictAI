part of 'dashboard_screen.dart';

extension _DashboardSimulatorScreen on _DashboardScreenState {
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
                      width: constraints.maxWidth * .43,
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
            const _SectionTitle(
              icon: Icons.tune,
              title: 'Parâmetros do Despacho',
              subtitle: 'Uma simulação por pedido, no momento do despacho.',
            ),
            const SizedBox(height: 8),
            Text(
              'A distância é calculada em linha reta a partir da geolocalização Olist por prefixo de CEP (5 dígitos). Para pedidos com vários vendedores, informe um CEP de origem por vendedor; o primeiro define a UF de origem.',
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
              onPressed: _isAnalyzing ? null : _analyze,
              icon: _isAnalyzing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: Text(_isAnalyzing
                    ? 'Resolvendo localização e consultando o modelo...'
                    : 'Simular risco de atraso'),
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
        _card(
          child: LayoutBuilder(builder: (context, constraints) {
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
                  Text(
                      _riskProbability == null
                          ? 'SEM PREVISÃO'
                          : 'PROBABILIDADE',
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
        if (response != null) ...[
          const SizedBox(height: 12),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Retorno do modelo',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
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
                  const SizedBox(height: 10),
                  ..._warnings.map((warning) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('Aviso: $warning',
                            style:
                                TextStyle(fontSize: 12, color: _secondaryText)),
                      )),
                ],
              ],
            ),
          ),
        ],
        if (scenario != null)
          _scenarioCard(
            scenario,
            title: current == null
                ? 'Parâmetros da tentativa atual'
                : 'Parâmetros enviados nesta simulação',
          ),
        if (_previousScenario != null) ...[
          const SizedBox(height: 12),
          _comparisonCard(current),
        ],
      ],
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
            Text('Compra: ${payload['purchase_at']}'),
            Text('Despacho: ${payload['dispatched_at']}'),
            Text('Entrega prometida: ${payload['estimated_delivery_at']}'),
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
