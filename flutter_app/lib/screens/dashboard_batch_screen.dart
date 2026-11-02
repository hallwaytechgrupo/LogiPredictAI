part of 'dashboard_screen.dart';

extension _DashboardBatchScreen on _DashboardScreenState {
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
      await _loadShipmentCsvContent(content, file.name);
    } catch (e) {
      if (!mounted) return;
      _updateBatchState(
          () => _batchError = 'Não foi possível importar o CSV: $e');
    }
  }

  Future<void> _loadShipmentCsvContent(
    String content,
    String fileName, {
    bool olistDemo = false,
    String? demoHubId,
  }) async {
    final parsed = ShipmentCsvService.parseShipments(content);
    final shipments = parsed.shipments;
    final storedOrders = <Map<String, dynamic>>[];
    for (var start = 0;
        start < shipments.length;
        start += OrdersApi.importBatchLimit) {
      final end =
          (start + OrdersApi.importBatchLimit).clamp(0, shipments.length);
      storedOrders.addAll(await _ordersApi.importOrders(
        shipments
            .sublist(start, end)
            .map((order) => order['id'] as String)
            .toList(),
        defaultHubId: olistDemo ? demoHubId : null,
        source: olistDemo ? 'olist' : null,
      ));
    }
    final storedById = {
      for (final order in storedOrders) order['order_id'].toString(): order,
    };
    if (storedById.length != shipments.length ||
        shipments.any((shipment) => !storedById.containsKey(shipment['id']))) {
      throw const FormatException(
          'A API não confirmou a persistência de todos os pedidos.');
    }
    for (final shipment in shipments) {
      final stored = storedById[shipment['id']];
      shipment['hub_id'] = stored?['hub_id'];
      shipment['hub'] = stored?['hub'];
      shipment['imported'] = stored?['imported'] == true;
      shipment['demo_hub_assigned'] = stored?['demo_hub_assigned'] == true;
      shipment['hub_preserved'] = stored?['hub_preserved'] == true;
    }
    if (!mounted) return;
    _updateBatchState(() {
      _batchShipments = shipments;
      _batchResults = [];
      _batchAssociationError = null;
      _batchError = null;
      _batchCompleted = 0;
      _batchTotal = shipments.length;
      _batchFileName = fileName;
      _batchIsOlist = olistDemo;
      _batchDemoHubId = olistDemo ? demoHubId : null;
      _batchSkipped = parsed.duplicateCount + parsed.invalidCount;
      _batchExistingCount =
          storedOrders.where((order) => order['imported'] != true).length;
      _batchDemoAssignedCount = storedOrders
          .where((order) => order['demo_hub_assigned'] == true)
          .length;
      _batchPreservedHubCount =
          storedOrders.where((order) => order['hub_preserved'] == true).length;
      _batchAlerts = [
        if (parsed.duplicateCount > 0)
          '${parsed.duplicateCount} linhas duplicadas foram ignoradas pelo order_id.',
        if (parsed.invalidCount > 0)
          '${parsed.invalidCount} linhas com dados incompatíveis com o contrato do ML foram ignoradas.',
        ...parsed.invalidExamples,
      ];
      _batchPhase = 'Pedidos importados';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text('${shipments.length} pedidos carregados de $fileName.')),
    );
  }

  Future<bool> _confirmOlistDemoDistribution() async {
    final hubs = _mapHubs
        .where((hub) => hub.isActive && hub.validationStatus == 'APROVADO')
        .toList();
    if (hubs.isEmpty) {
      _updateBatchState(() => _batchError =
          'Cadastre e aprove pelo menos um hub antes de executar a demonstração Olist.');
      return false;
    }
    return await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Executar simulação Olist'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Os pedidos Olist serão distribuídos entre os hubs aprovados com base no estado de destino de cada pedido.'),
              const SizedBox(height: 8),
              const Text(
                  'Esta associação é demonstrativa; não representa a logística histórica real da Olist.'),
              const SizedBox(height: 8),
              Text(
                  'Hubs aprovados disponíveis: ${hubs.length} em ${_getUniqueStates(hubs).length} estados.'),
              const SizedBox(height: 8),
              const Text(
                  'Pedidos cujos estados não possuem hub não serão atribuídos. Pedidos com previsão existente terão o hub atualizado, mas a previsão não será reprocessada.'),
              const SizedBox(height: 10),
              const Text(
                  'Deseja continuar com a distribuição automática?',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    ) ??
        false;
  }

  Set<String> _getUniqueStates(List<dynamic> hubs) {
    final states = <String>{};
    for (final hub in hubs) {
      final state = hub.state ?? hub['state'];
      if (state != null && state.toString().isNotEmpty) {
        states.add(state.toString());
      }
    }
    return states;
  }

  Future<void> _runOlistSimulation() async {
    if (_isBatchAnalyzing) return;
    _updateBatchState(() {
      _batchError = null;
      _batchAlerts = [];
      _batchSkipped = 0;
      _batchExistingCount = 0;
      _batchDemoAssignedCount = 0;
      _batchPreservedHubCount = 0;
      _batchResults = [];
    });
    final confirmed = await _confirmOlistDemoDistribution();
    if (!mounted || !confirmed) return;
    _updateBatchState(() {
      _isBatchAnalyzing = true;
      _batchCancellation = BatchCancellationToken();
      _batchIsOlist = true;
      _batchPhase = 'Carregando CSV';
      _batchCompleted = 0;
      _batchTotal = 0;
      _batchFileName = 'Dataset Olist preparado';
      _batchDemoHubId = null;
      _batchExistingCount = 0;
      _batchDemoAssignedCount = 0;
      _batchPreservedHubCount = 0;
    });

    var shipments = <Map<String, dynamic>>[];
    try {
      final content = await OlistDatasetApi().loadPreparedCsv();
      if (_batchCancellation.isCancelled) {
        _updateBatchState(() {
          _isBatchAnalyzing = false;
          _batchPhase = 'Cancelada';
          _batchError = 'Execução cancelada antes da importação dos pedidos.';
        });
        return;
      }
      final parsed = ShipmentCsvService.parseShipments(content);
      shipments = parsed.shipments;
      _updateBatchState(() {
        _batchTotal = shipments.length;
        _batchSkipped = parsed.duplicateCount + parsed.invalidCount;
        _batchPhase = 'Importando pedidos';
        if (parsed.duplicateCount > 0) {
          _batchAlerts.add(
              '${parsed.duplicateCount} linhas duplicadas foram ignoradas pelo order_id.');
        }
        if (parsed.invalidCount > 0) {
          _batchAlerts.add(
              '${parsed.invalidCount} linhas com dados incompatíveis com o contrato do ML foram ignoradas.');
          _batchAlerts.addAll(parsed.invalidExamples);
        }
      });

      // Step 1: Import orders without a default hub
      final stored = <String, Map<String, dynamic>>{};
      var importOffset = 0;
      for (;
          importOffset < shipments.length;
          importOffset += OrdersApi.importBatchLimit) {
        if (_batchCancellation.isCancelled) break;
        final end = (importOffset + OrdersApi.importBatchLimit)
            .clamp(0, shipments.length);
        final chunk = shipments.sublist(importOffset, end);
        try {
          final rows = await _ordersApi.importOrders(
            chunk.map((order) => order['id'] as String).toList(),
            source: 'olist',
          );
          if (rows.length != chunk.length ||
              rows.any((row) => !chunk
                  .any((shipment) => shipment['id'] == row['order_id']))) {
            throw const FormatException(
                'A API confirmou uma quantidade diferente de pedidos neste lote.');
          }
          for (final row in rows) {
            stored[row['order_id'].toString()] = row;
          }
          _updateBatchState(() {
            _batchCompleted = end;
            _batchExistingCount +=
                rows.where((row) => row['imported'] != true).length;
            _batchDemoAssignedCount +=
                rows.where((row) => row['demo_hub_assigned'] == true).length;
            _batchPreservedHubCount +=
                rows.where((row) => row['hub_preserved'] == true).length;
          });
        } catch (error) {
          _updateBatchState(() {
            _batchSkipped += chunk.length;
            _batchAlerts.add(
                'Falha ao importar pedidos ${importOffset + 1}–$end: $error');
          });
        }
      }
      if (_batchCancellation.isCancelled) {
        _batchSkipped += shipments.length - importOffset;
      }
      if (_batchCancellation.isCancelled) {
        _updateBatchState(() {
          _isBatchAnalyzing = false;
          _batchPhase = 'Cancelada';
          _batchError =
              'Execução cancelada antes da distribuição de hubs.';
        });
        return;
      }

      // Step 2: Distribute hubs by destination state
      _updateBatchState(() {
        _batchPhase = 'Distribuindo hubs por estado';
      });
      try {
        final assignOrders = shipments
            .where((s) => stored.containsKey(s['id']))
            .map((s) => {
                  'order_id': s['id'] as String,
                  'customer_state': (s['customer_state'] as String? ?? '').toUpperCase(),
                })
            .toList();

        // Process in chunks of 2000 (API limit)
        var assignOffset = 0;
        var totalAssigned = 0;
        var totalUnchanged = 0;
        var totalWouldChange = 0;
        var totalUnassigned = 0;
        var totalWithPrediction = 0;
        final allUncoveredStates = <Map<String, dynamic>>[];
        final hubAssignments = <String, String?>{};

        // Aggregated report data across chunks
        final allStateCounts = <String, int>{};
        final allHubCounts = <String, int>{};
        final allReasonCounts = <String, int>{};

        while (assignOffset < assignOrders.length &&
            !_batchCancellation.isCancelled) {
          final end =
              (assignOffset + OrdersApi.importBatchLimit).clamp(0, assignOrders.length);
          final chunk = assignOrders.sublist(assignOffset, end);

          // Dry-run preview
          final dryRunResult =
              await _ordersApi.assignHubsByState(chunk, dryRun: true);
          final dryRunSummary =
              dryRunResult['summary'] as Map<String, dynamic>? ?? {};
          totalWouldChange +=
              (dryRunSummary['total_would_change'] as int?) ?? 0;
          totalUnassigned +=
              (dryRunSummary['total_unassigned'] as int?) ?? 0;
          totalWithPrediction +=
              (dryRunSummary['total_with_prediction'] as int?) ?? 0;

          final uncovered = dryRunResult['uncovered_states'] as List? ?? [];
          for (final s in uncovered) {
            if (!allUncoveredStates.any(
                (u) => u['state'] == (s as Map<String, dynamic>)['state'])) {
              allUncoveredStates.add(s);
            }
          }

          // Aggregate state counts
          final stateCounts = dryRunResult['state_counts'] as List? ?? [];
          for (final sc in stateCounts) {
            final scMap = sc as Map<String, dynamic>;
            final state = scMap['state'] as String;
            final count = scMap['orders_count'] as int;
            allStateCounts[state] = (allStateCounts[state] ?? 0) + count;
          }

          // Aggregate hub counts
          final hubCounts = dryRunResult['hub_counts'] as List? ?? [];
          for (final hc in hubCounts) {
            final hcMap = hc as Map<String, dynamic>;
            final hubId = hcMap['hub_id'] as String;
            final count = hcMap['orders_count'] as int;
            allHubCounts[hubId] = (allHubCounts[hubId] ?? 0) + count;
          }

          // Aggregate reasons
          final reasons = dryRunResult['reasons'] as List? ?? [];
          for (final r in reasons) {
            final rMap = r as Map<String, dynamic>;
            final reason = rMap['reason'] as String;
            final count = rMap['count'] as int;
            allReasonCounts[reason] = (allReasonCounts[reason] ?? 0) + count;
          }

          // Apply the distribution
          final applyResult =
              await _ordersApi.assignHubsByState(chunk, dryRun: false);
          final applySummary =
              applyResult['summary'] as Map<String, dynamic>? ?? {};
          totalAssigned += (applySummary['assigned'] as int?) ?? 0;
          totalUnchanged += (applySummary['unchanged'] as int?) ?? 0;

          // Collect assignments from dry-run for local update
          final assignments = dryRunResult['assignments'] as List? ?? [];
          for (final a in assignments) {
            final aMap = a as Map<String, dynamic>;
            hubAssignments[aMap['order_id'] as String] =
                aMap['assigned_hub_id'] as String?;
          }

          assignOffset = end;
        }

        // Build final report summaries
        final totalAssignedWithHub = allHubCounts.values.fold(0, (a, b) => a + b);
        final totalAnalyzedAll = allStateCounts.values.fold(0, (a, b) => a + b);

        _batchAlerts.add('=== Relatório de Associação de Hubs ===');
        _batchAlerts.add('Total de pedidos analisados: $totalAnalyzedAll');
        _batchAlerts.add('Pedidos com hub atribuído: $totalAssignedWithHub');
        _batchAlerts.add('Pedidos sem associação: $totalUnassigned');
        _batchAlerts.add('Pedidos ignorados por validação: $_batchSkipped');

        // State distribution
        if (allStateCounts.isNotEmpty) {
          _batchAlerts.add('');
          _batchAlerts.add('Pedidos por estado de destino:');
          final sortedStates = allStateCounts.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          for (final entry in sortedStates) {
            _batchAlerts.add('  ${entry.key}: ${entry.value} pedidos');
          }
        }

        // Hub distribution with percentages
        if (allHubCounts.isNotEmpty) {
          _batchAlerts.add('');
          _batchAlerts.add('Pedidos por hub:');
          final sortedHubs = allHubCounts.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          for (final entry in sortedHubs) {
            final hub = _mapHubs.firstWhere(
              (h) => h.id == entry.key,
              orElse: () => LogisticHub.fromJson({
                'id': entry.key,
                'code': 'DESCONHECIDO',
                'name': 'Hub ${entry.key}',
                'city': '',
                'state': '',
              }),
            );
            final pct = totalAnalyzedAll > 0
                ? (entry.value / totalAnalyzedAll * 100).toStringAsFixed(1)
                : '0.0';
            _batchAlerts.add('  ${hub.name} (${hub.code}): ${entry.value} pedidos ($pct%)');
          }
        }

        // Reasons breakdown
        if (allReasonCounts.isNotEmpty) {
          _batchAlerts.add('');
          _batchAlerts.add('Motivos de associação:');
          final sortedReasons = allReasonCounts.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          for (final entry in sortedReasons) {
            final label = switch (entry.key) {
              'NO_HUB_FOR_STATE' => 'Sem hub para o estado',
              'HAS_PREDICTION' => 'Já possui previsão',
              'WOULD_CHANGE' => 'Mudaria de hub',
              'UNCHANGED' => 'Hub inalterado',
              _ => entry.key,
            };
            _batchAlerts.add('  $label: ${entry.value}');
          }
        }

        // Uncovered states detail
        if (totalUnassigned > 0) {
          _batchAlerts.add('');
          _batchAlerts.add('Estados sem hub configurado:');
          for (final s in allUncoveredStates) {
            final stateMap = s as Map<String, dynamic>;
            _batchAlerts.add(
                '  ${stateMap['state']}: ${stateMap['orders_count']} pedidos sem hub');
          }
        }

        if (totalWouldChange > 0) {
          _batchAlerts.add('');
          _batchAlerts.add(
              '$totalWouldChange pedidos mudariam de hub com a distribuição por estado.');
        }
        if (totalWithPrediction > 0) {
          _batchAlerts.add(
              '$totalWithPrediction pedidos já possuem previsão — o hub será atualizado, mas a previsão não será reprocessada.');
        }

        _batchAlerts.add('');
        _batchAlerts.add(
            'Distribuição aplicada: $totalAssigned hubs atualizados, $totalUnchanged inalterados.');

        // Update stored orders with new hub assignments (local, no API calls)
        for (final shipment in shipments) {
          final orderId = shipment['id'] as String;
          final newHubId = hubAssignments[orderId];
          if (newHubId != null && stored.containsKey(orderId)) {
            final existing = stored[orderId]!;
            stored[orderId] = Map<String, dynamic>.from(existing)..['hub_id'] = newHubId;
          }
        }
      } catch (error) {
        _batchAlerts.add('Falha ao distribuir hubs por estado: $error');
        // Continue with existing assignments
      }
      final importedShipments = <Map<String, dynamic>>[];
      for (final shipment in shipments) {
        final row = stored[shipment['id']];
        if (row == null) continue;
        importedShipments.add({
          ...shipment,
          'hub_id': row['hub_id'],
          'hub': row['hub'],
          'imported': row['imported'] == true,
          'demo_hub_assigned': row['demo_hub_assigned'] == true,
          'hub_preserved': row['hub_preserved'] == true,
        });
      }
      _updateBatchState(() {
        _batchShipments = importedShipments;
        _batchTotal = importedShipments.length;
        _batchCompleted = 0;
        _batchPhase = _batchCancellation.isCancelled
            ? 'Cancelada durante importação'
            : 'Enviando previsões';
        if (_batchPreservedHubCount > 0) {
          _batchAlerts.add(
              '$_batchPreservedHubCount pedidos mantiveram o hub associado anteriormente.');
        }
      });
      if (_batchCancellation.isCancelled) {
        _updateBatchState(() {
          _isBatchAnalyzing = false;
          _batchError =
              'Execução cancelada durante a importação; pedidos já importados e associados permanecem salvos.';
        });
        await _loadMapHubs();
        return;
      }
      if (importedShipments.isEmpty) {
        _updateBatchState(() {
          _isBatchAnalyzing = false;
          _batchError =
              'Nenhum pedido foi importado para análise. Consulte os alertas.';
        });
        return;
      }
      await _runBatchAnalysis(alreadyRunning: true);
      if (mounted) await _loadMapHubs();
    } catch (error) {
      if (!mounted) return;
      _updateBatchState(() {
        _isBatchAnalyzing = false;
        _batchError = 'Não foi possível executar a simulação Olist: $error';
      });
    }
  }

  List<LogisticHub> get _selectableBatchHubs {
    final selectedIds = _batchShipments
        .map((order) => order['hub_id'])
        .whereType<String>()
        .toSet();
    return _mapHubs
        .where((hub) =>
            (hub.isActive && hub.validationStatus == 'APROVADO') ||
            selectedIds.contains(hub.id))
        .toList();
  }

  String _batchHubLabel(Map<String, dynamic> order) {
    final registered = _selectableBatchHubs
        .where((hub) => hub.id == order['hub_id'])
        .firstOrNull;
    if (registered != null) return '${registered.name} · ${registered.code}';
    final summary = order['hub'];
    if (summary is Map && summary['name'] != null) {
      return summary['name'].toString();
    }
    return order['hub_id'] == null
        ? 'Sem associação'
        : 'Hub ${order['hub_id']}';
  }

  Future<void> _updateOrderHub(String orderId, String? hubId) async {
    if (_savingOrderHubIds.contains(orderId)) return;
    final index = _batchShipments.indexWhere((order) => order['id'] == orderId);
    if (index < 0 || _batchShipments[index]['hub_id'] == hubId) return;
    _updateBatchState(() {
      _savingOrderHubIds.add(orderId);
      _batchAssociationError = null;
    });
    try {
      final association = await _ordersApi.setHub(orderId, hubId);
      if (!mounted) return;
      _updateBatchState(() {
        _batchShipments[index]['hub_id'] = association['hub_id'];
        _batchShipments[index]['hub'] = association['hub'];
        _batchResults = [];
      });
    } catch (error) {
      if (!mounted) return;
      _updateBatchState(() => _batchAssociationError =
          'Não foi possível salvar o hub do pedido $orderId: $error');
    } finally {
      if (mounted) _updateBatchState(() => _savingOrderHubIds.remove(orderId));
    }
  }

  Future<void> _runBatchAnalysis({bool alreadyRunning = false}) async {
    if (_isBatchAnalyzing && !alreadyRunning) return;
    if (_batchShipments.isEmpty) {
      _updateBatchState(() {
        _isBatchAnalyzing = false;
        _batchError = 'Importe um CSV de pedidos antes de executar a análise.';
      });
      return;
    }
    final shipments = List<Map<String, dynamic>>.from(_batchShipments);
    _updateBatchState(() {
      _isBatchAnalyzing = true;
      if (!alreadyRunning) _batchCancellation = BatchCancellationToken();
      _batchCompleted = 0;
      _batchTotal = shipments.length;
      _batchError = null;
      _batchResults = [];
      _batchStopwatch.reset();
      _batchStopwatch.start();
      _batchTimer?.cancel();
      _batchTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && _isBatchAnalyzing) {
          _updateBatchState(() {});
        }
      });
      if (!alreadyRunning) {
        _batchSkipped = 0;
        _batchAlerts = [];
        _batchPhase = 'Analisando previsões';
      }
    });

    // Build payloads for batch endpoint
    final payloads = <Map<String, dynamic>>[];
    final orderIds = <String>[];
    for (final order in shipments) {
      if (_batchCancellation.isCancelled) break;
      payloads.add(<String, dynamic>{
        'purchase_at':
            (order['purchase_at'] as DateTime).toIso8601String(),
        'dispatched_at':
            (order['dispatched_at'] as DateTime).toIso8601String(),
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
      });
      orderIds.add(order['id'] as String);
    }

    if (_batchCancellation.isCancelled) {
      _updateBatchState(() {
        _isBatchAnalyzing = false;
        _batchStopwatch.stop();
        _batchTimer?.cancel();
        _batchPhase = 'Cancelada';
        _batchError = 'Execução cancelada antes do envio.';
      });
      return;
    }

    final batchApi = BatchPredictionApi();
    final resultsByIndex = <int, Map<String, dynamic>>{};
    const chunkSize = 20000;

    // Split into chunks if needed and process sequentially
    for (var chunkStart = 0; chunkStart < payloads.length; chunkStart += chunkSize) {
      if (_batchCancellation.isCancelled) break;

      final chunkEnd = (chunkStart + chunkSize).clamp(0, payloads.length);
      final chunkPayloads = payloads.sublist(chunkStart, chunkEnd);
      final chunkOrderIds = orderIds.sublist(chunkStart, chunkEnd);

      _updateBatchState(() {
        _batchPhase = 'Enviando lote ${chunkStart ~/ chunkSize + 1}';
      });

      await batchApi.predictBatch(
        shipments: chunkPayloads,
        orderIds: chunkOrderIds,
        onProgress: (event) {
          if (!mounted || _batchCancellation.isCancelled) return;
          _updateBatchState(() {
            _batchCompleted = chunkStart + event.completed;
          });
        },
        onComplete: (event) {
          if (!mounted) return;

          // Track skipped count
          _batchSkipped += event.skipped;

          // Map results back to shipments with global index offset
          for (final result in event.results) {
            final localIdx = result['index'] as int;
            final globalIdx = chunkStart + localIdx;
            if (globalIdx >= shipments.length) continue;
            final order = shipments[globalIdx];

            // Handle skipped results (already had a prediction)
            if (result['status'] == 'skipped') {
              final probability = (result['delay_probability'] as num).toDouble();
              final threshold = (result['threshold'] as num).toDouble();
              resultsByIndex[globalIdx] = {
                ...order,
                'probability': probability,
                'predicted_late': result['predicted_late'],
                'threshold': threshold,
                'model_version': result['model_version']?.toString(),
                'prediction_id': result['prediction_id']?.toString(),
                'persisted': true,
                'skipped': true,
                'error': null,
              };
              continue;
            }

            if (result['error'] != null) {
              resultsByIndex[globalIdx] = {
                ...order,
                'error': result['message']?.toString() ?? result['error'].toString(),
              };
            } else {
              final probability = (result['delay_probability'] as num).toDouble();
              final threshold = (result['threshold'] as num).toDouble();
              resultsByIndex[globalIdx] = {
                ...order,
                'probability': probability,
                'predicted_late': result['predicted_late'],
                'threshold': threshold,
                'model_version': result['model_version']?.toString(),
                'prediction_id': result['prediction_id']?.toString(),
                'persisted': result['persisted'] == true,
                'error': null,
              };
            }
          }
        },
        onError: (error) {
          if (!mounted) return;
          _batchStopwatch.stop();
          _batchTimer?.cancel();
          _updateBatchState(() {
            _isBatchAnalyzing = false;
            _batchError = 'Falha no lote ${chunkStart ~/ chunkSize + 1}: $error';
            _batchPhase = 'Erro';
          });
        },
      );
    }

    // Finalize
    if (!mounted) return;
    if (_batchCancellation.isCancelled) {
      _batchStopwatch.stop();
      _batchTimer?.cancel();
      _updateBatchState(() {
        _isBatchAnalyzing = false;
        _batchPhase = 'Cancelada';
        _batchError = 'Execução cancelada; previsões já registradas permanecem salvas.';
      });
      return;
    }

    _batchStopwatch.stop();
    _batchTimer?.cancel();

    final allResults = <Map<String, dynamic>>[];
    for (var i = 0; i < shipments.length; i++) {
      allResults.add(resultsByIndex[i] ?? {...shipments[i], 'error': 'Resultado ausente'});
    }
    allResults.sort((a, b) =>
        ((b['probability'] as num?)?.toDouble() ?? -1)
            .compareTo((a['probability'] as num?)?.toDouble() ?? -1));

    final failed = allResults.where((row) => row['error'] != null).length;
    _updateBatchState(() {
      _isBatchAnalyzing = false;
      _batchCompleted = allResults.length;
      _batchResults = allResults;
      _batchPhase = 'Concluída';
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
            'Execute o dataset Olist preparado ou importe outro CSV. As previsões são enviadas ao serviço real de ML e persistidas por order_id.',
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
              'A associação de demonstração a um hub não comprova que ele expediu pedidos históricos Olist. Atribuímos o hub escolhido apenas a pedidos sem vínculo; hubs já associados são preservados. Nenhuma associação é inferida por localização.',
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
          if (_batchIsOlist) ...[
            Text(
              'Execução Olist: associação demonstrativa a ${_mapHubs.where((hub) => hub.id == _batchDemoHubId).map((hub) => '${hub.name} · ${hub.code}').firstOrNull ?? _batchDemoHubId ?? 'hub selecionado'}; vínculos anteriores preservados.',
              style: TextStyle(fontSize: 12, color: _secondaryText),
            ),
            const SizedBox(height: 8),
          ],
          if (_batchShipments.isNotEmpty) ...[
            Text(
              'Hub de expedição por pedido (opcional). A seleção é salva na API; nenhum hub é associado automaticamente.',
              style: TextStyle(fontSize: 12, color: _secondaryText),
            ),
            const SizedBox(height: 8),
            if (_loadingMapHubs) const LinearProgressIndicator(),
            if (_mapHubsError != null)
              Text(
                'Não foi possível carregar os hubs: $_mapHubsError. Os pedidos podem continuar sem associação.',
                style: const TextStyle(color: Colors.red),
              ),
            if (!_loadingMapHubs &&
                _mapHubsError == null &&
                _selectableBatchHubs.isEmpty)
              Text(
                'Não há hubs ativos e aprovados. Os pedidos permanecerão sem associação.',
                style: TextStyle(fontSize: 12, color: _secondaryText),
              ),
            if (_batchIsOlist)
              Text(
                'Pedidos importados nesta execução: ${_batchShipments.length}. A configuração de demonstração não representa a expedição histórica da Olist.',
                style: TextStyle(fontSize: 12, color: _secondaryText),
              )
            else
              ..._batchShipments.map((order) {
                final orderId = order['id'] as String;
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(orderId),
                  trailing: _savingOrderHubIds.contains(orderId)
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  subtitle: OrderHubSelector(
                    key: ValueKey('order-hub-$orderId'),
                    selectedHubId: order['hub_id'] as String?,
                    selectedHubFallbackLabel:
                        ((order['hub'] as Map?)?['name']?.toString() ??
                            order['hub_id']?.toString()),
                    hubs: _selectableBatchHubs,
                    onChanged: _isBatchAnalyzing ||
                            _loadingMapHubs ||
                            _mapHubsError != null ||
                            _savingOrderHubIds.contains(orderId)
                        ? null
                        : (hubId) => _updateOrderHub(orderId, hubId),
                  ),
                );
              }),
            if (_batchAssociationError != null) ...[
              const SizedBox(height: 6),
              Text(
                _batchAssociationError!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
            const Divider(),
          ],
          Wrap(spacing: 10, runSpacing: 10, children: [
            FilledButton.tonalIcon(
              key: const ValueKey('run-olist-simulation'),
              onPressed: _isBatchAnalyzing ? null : _runOlistSimulation,
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('Executar simulação Olist'),
            ),
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
            if (_isBatchAnalyzing)
              OutlinedButton.icon(
                key: const ValueKey('cancel-batch-simulation'),
                onPressed: () => _updateBatchState(() {
                  _batchCancellation.cancel();
                  _batchPhase = 'Cancelamento solicitado';
                }),
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Cancelar'),
              ),
            OutlinedButton.icon(
              onPressed: _batchResults.isEmpty || _isBatchAnalyzing
                  ? null
                  : () => _updateBatchState(() {
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
            Text('$_batchPhase · $_batchCompleted/$_batchTotal'),
            LinearProgressIndicator(
                value: _batchTotal == 0 ? 0 : _batchCompleted / _batchTotal),
            const SizedBox(height: 4),
            Text(
              'Tempo decorrido: ${_formatDuration(_batchStopwatch.elapsed)}',
              style: TextStyle(fontSize: 11, color: _secondaryText),
            ),
          ],
          if (_batchAlerts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Alertas e relatório da simulação',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Container(
              constraints: const BoxConstraints(maxHeight: 400),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _surfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _border),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _batchAlerts.map((alert) {
                    if (alert.isEmpty) return const SizedBox(height: 6);
                    final isHeader = alert.startsWith('===');
                    return Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        isHeader ? alert : '• $alert',
                        style: TextStyle(
                          fontSize: isHeader ? 13 : 12,
                          fontWeight: isHeader ? FontWeight.bold : null,
                          color: isHeader ? null : _secondaryText,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
          if (_batchError != null) ...[
            const SizedBox(height: 12),
            Text(_batchError!, style: const TextStyle(color: Colors.red)),
          ],
          if (_batchIsOlist && _batchFileName != null) ...[
            const SizedBox(height: 14),
            Wrap(spacing: 12, runSpacing: 8, children: [
              _miniMetric('Pedidos importados', '${_batchShipments.length}'),
              _miniMetric('Já existentes', '$_batchExistingCount'),
              _miniMetric('Hub demo atribuído', '$_batchDemoAssignedCount'),
              _miniMetric('Vínculos preservados', '$_batchPreservedHubCount'),
              _miniMetric('Ignorados', '$_batchSkipped'),
            ]),
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
                  DataColumn(label: Text('Hub responsável')),
                  DataColumn(label: Text('Origem → Destino')),
                  DataColumn(label: Text('Prazo estimado')),
                  DataColumn(label: Text('Probabilidade')),
                  DataColumn(label: Text('Resultado do modelo')),
                  DataColumn(label: Text('Modelo')),
                  DataColumn(label: Text('Histórico')),
                ],
                rows: _batchResults.take(200).map((row) {
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
                    DataCell(Text(_batchHubLabel(row))),
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
                    DataCell(Text(failed
                        ? 'Não registrada'
                        : row['persisted'] == true
                            ? 'Registrada'
                            : 'Pendente')),
                  ]);
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ordenação: maior probabilidade primeiro. Exibindo até 200 resultados nesta tabela. “Sem alerta” não significa garantia de entrega no prazo.',
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

  String _formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}
