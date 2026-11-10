/// Tela unificada de gerenciamento de pedidos.
///
/// Combina:
/// - Resumo dos pedidos operacionais
/// - Importação de CSV operacional
/// - Listagem de pedidos com filtros e paginação
/// - Detalhes do pedido com alteração de hub
library;

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/orders_api.dart';
import '../services/shipment_csv_service.dart';
import '../services/hubs_api.dart';

class OrdersScreen extends StatefulWidget {
  /// Notifier que dispara quando a tela deve recarregar os dados
  /// (por exemplo, após associação de hub no Simulador Logístico).
  final ValueNotifier<int>? refreshTrigger;

  const OrdersScreen({super.key, this.refreshTrigger});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

enum _OrderFilter { all, withHub, withoutHub, withPrediction, withoutPrediction }

extension _OrderFilterExtension on _OrderFilter {
  String get label {
    switch (this) {
      case _OrderFilter.all:
        return 'Todos';
      case _OrderFilter.withHub:
        return 'Com hub';
      case _OrderFilter.withoutHub:
        return 'Sem hub';
      case _OrderFilter.withPrediction:
        return 'Com previsão';
      case _OrderFilter.withoutPrediction:
        return 'Sem previsão';
    }
  }
}

class _OrdersScreenState extends State<OrdersScreen> {
  final _ordersApi = OrdersApi();
  final _hubsApi = HubsApi();
  final _searchController = TextEditingController();

  // Summary
  Map<String, dynamic>? _summary;
  bool _loadingSummary = true;
  String? _summaryError;

  // CSV Import
  String? _csvContent;
  String? _csvFileName;
  int _csvRecordCount = 0;
  bool _isLoading = false;
  String? _error;
  String _status = 'Selecione um arquivo CSV para importar.';
  int? _imported;
  int? _ignored;
  int? _failed;
  List<Map<String, dynamic>> _importedData = [];
  List<Map<String, dynamic>> _ignoredData = [];
  List<Map<String, dynamic>> _failedData = [];

  // Orders list
  List<Map<String, dynamic>> _orders = [];
  int _total = 0;
  int _page = 1;
  static const int _perPage = 20;
  int _totalPages = 1;
  bool _loadingOrders = true;
  int _ordersRequest = 0;
  String? _ordersError;
  _OrderFilter _filter = _OrderFilter.all;

  // Hubs for manual change
  List<Map<String, dynamic>> _hubs = [];
  bool _loadingHubs = true;

  @override
  void initState() {
    super.initState();
    _loadSummary();
    _loadOrders();
    _loadHubs();
    // Listen for external refresh triggers (e.g., hub association in Simulator)
    if (widget.refreshTrigger != null) {
      widget.refreshTrigger!.addListener(_onRefreshTrigger);
    }
  }

  void _onRefreshTrigger() {
    if (mounted) {
      _reloadAll();
    }
  }

  /// Recarrega resumo e listagem de pedidos.
  /// Chamado quando a tela se torna visível ou após evento externo.
  Future<void> _reloadAll() async {
    await Future.wait([
      _loadSummary(),
      _loadOrders(),
    ]);
  }

  /// Chamado pelo pai quando a aba Pedidos se torna visível.
  void refresh() {
    _reloadAll();
  }

  @override
  void dispose() {
    widget.refreshTrigger?.removeListener(_onRefreshTrigger);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSummary() async {
    setState(() {
      _loadingSummary = true;
      _summaryError = null;
    });
    try {
      final summary = await _ordersApi.summary();
      if (mounted) {
        setState(() {
          _summary = summary;
          _loadingSummary = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _summary = null;
          _summaryError = e.toString();
          _loadingSummary = false;
        });
      }
    }
  }

  Future<void> _loadOrders({int? page}) async {
    final request = ++_ordersRequest;
    final targetPage = page ?? _page;
    setState(() {
      _loadingOrders = true;
      _ordersError = null;
    });
    try {
      final result = await _ordersApi.listOrders(
        page: targetPage,
        perPage: _perPage,
        query: _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
        source: 'operational',
      );
      if (!mounted || request != _ordersRequest) return;
      setState(() {
        _orders = (result['data'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .toList() ??
            [];
        _total = result['total'] as int? ?? 0;
        _page = result['page'] as int? ?? targetPage;
        _totalPages = result['total_pages'] as int? ?? 1;
        _loadingOrders = false;
      });
    } catch (e) {
      if (!mounted || request != _ordersRequest) return;
      setState(() {
        _ordersError = e.toString();
        _loadingOrders = false;
      });
    }
  }

  Future<void> _loadHubs() async {
    try {
      final hubs = await _hubsApi.list();
      if (mounted) {
        setState(() {
          _hubs = hubs.map((h) => {
            'id': h.id,
            'code': h.code,
            'name': h.name,
            'city': h.city,
            'state': h.state,
          }).toList();
          _loadingHubs = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hubs = [];
          _loadingHubs = false;
        });
      }
    }
  }

  /// Pick CSV file — Web-safe using bytes
  Future<void> _pickFile() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _status = 'Selecionando arquivo...';
      _csvContent = null;
      _csvFileName = null;
      _csvRecordCount = 0;
      _imported = null;
      _ignored = null;
      _failed = null;
      _importedData = [];
      _ignoredData = [];
      _failedData = [];
    });

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );
      if (!mounted) return;

      if (result == null || result.files.isEmpty) {
        setState(() {
          _isLoading = false;
          _status = 'Nenhum arquivo selecionado.';
        });
        return;
      }

      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw const FormatException('O arquivo CSV está vazio ou não pôde ser lido.');
      }
      final csv = utf8.decode(bytes).replaceFirst('\uFEFF', '');
      if (csv.trim().isEmpty) {
        throw const FormatException('O arquivo CSV está vazio.');
      }
      final records = ShipmentCsvService.parseCsv(csv);

      setState(() {
        _csvContent = csv;
        _csvFileName = file.name;
        _csvRecordCount = records.length - 1;
        _status = 'Arquivo "$_csvFileName" carregado ($_csvRecordCount registros). Clique em "Importar" para processar.';
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Erro ao ler arquivo: $e';
        _status = 'Erro';
      });
    }
  }

  Future<void> _import() async {
    if (_csvContent == null) {
      setState(() {
        _error = 'Selecione um arquivo CSV primeiro.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _status = 'Validando CSV...';
    });

    try {
      // Validate locally first
      ShipmentCsvService.parseShipments(_csvContent!, requireZipCodes: true);
      setState(() {
        _status = 'Enviando para o servidor...';
      });

      // Send to backend
      final response = await _ordersApi.importCsv(_csvContent!);

      setState(() {
        _imported = response['imported'] as int?;
        _ignored = response['ignored'] as int?;
        _failed = response['failed'] as int?;

        final data = response['data'] as Map<String, dynamic>? ?? {};
        _importedData = (data['imported'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        _ignoredData = (data['ignored'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        _failedData = (data['failed'] as List?)?.cast<Map<String, dynamic>>() ?? [];

        _status = 'Importação concluída!';
        _isLoading = false;
      });

      // Reload orders and summary
      _loadSummary();
      _loadOrders(page: 1);
    } catch (e) {
      setState(() {
        _error = 'Erro na importação: $e';
        _status = 'Erro';
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    _loadOrders(page: 1);
  }

  void _onFilterChanged(_OrderFilter? newFilter) {
    if (newFilter == null) return;
    setState(() {
      _filter = newFilter;
      _page = 1;
    });
    _loadOrders(page: 1);
  }

  String? _formatHub(Map<String, dynamic>? hub) {
    if (hub == null) return '—';
    final name = hub['name'] as String? ?? '';
    final code = hub['code'] as String? ?? '';
    if (name.isNotEmpty && code.isNotEmpty) return '$name · $code';
    return name.isNotEmpty ? name : code;
  }

  String? _formatDate(String? date) {
    if (date == null || date.isEmpty) return '—';
    try {
      final d = DateTime.parse(date);
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) {
      return date;
    }
  }

  String _statusLabel(String? status) {
    const labels = {
      'created': 'Criado',
      'approved': 'Aprovado',
      'invoiced': 'Faturado',
      'processing': 'Em preparação',
      'shipped': 'Em transporte',
      'delivered': 'Entregue',
      'canceled': 'Cancelado',
      'unavailable': 'Indisponível',
    };
    return labels[status] ?? 'Não informado';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF172338) : Colors.white;
    final surfaceAlt = isDark ? const Color(0xFF202F46) : const Color(0xFFF8FAFC);
    final border = isDark ? const Color(0xFF33445D) : const Color(0xFFE2E8F0);
    final primaryText = isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A);
    final secondaryText = isDark ? const Color(0xFFB5C2D4) : const Color(0xFF64748B);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.receipt_long_outlined,
                  color: const Color(0xFF2563EB), size: 20),
              const SizedBox(width: 8),
              Text('Pedidos',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: primaryText)),
            ],
          ),
          const SizedBox(height: 16),

          // ===== A. SUMMARY INDICATORS =====
          _buildSummary(surface, border, primaryText, secondaryText),
          const SizedBox(height: 20),

          // ===== B. CSV IMPORT SECTION =====
          _buildImportSection(surface, surfaceAlt, border, primaryText, secondaryText),
          const SizedBox(height: 20),

          // ===== C. ORDERS LISTING =====
          _buildOrdersListing(surface, surfaceAlt, border, primaryText, secondaryText),
        ],
      ),
    );
  }

  Widget _buildSummary(
      Color surface, Color border, Color primaryText, Color secondaryText) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Resumo',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: primaryText)),
          const SizedBox(height: 12),
          if (_loadingSummary)
            const Center(child: CircularProgressIndicator(strokeWidth: 2))
          else if (_summaryError != null) ...[
            Text('Erro ao carregar resumo: $_summaryError', style: const TextStyle(color: Colors.red)),
            TextButton(onPressed: _loadSummary, child: const Text('Tentar carregar resumo novamente')),
          ]
          else ...[
            Row(
              children: [
                Expanded(
                  child: _summaryCard(
                      'Total',
                      _summary?['total']?.toString() ?? '0',
                      Icons.receipt_long_outlined,
                      const Color(0xFF2563EB),
                      secondaryText),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _summaryCard(
                      'Com hub',
                      _summary?['withHub']?.toString() ?? '0',
                      Icons.check_circle_outline,
                      const Color(0xFF059669),
                      secondaryText),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _summaryCard(
                      'Sem hub',
                      _summary?['withoutHub']?.toString() ?? '0',
                      Icons.warning_amber_outlined,
                      const Color(0xFFD97706),
                      secondaryText),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _summaryCard(
                      'Com previsão',
                      _summary?['withPrediction']?.toString() ?? '0',
                      Icons.analytics_outlined,
                      const Color(0xFF7C3AED),
                      secondaryText),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryCard(
      String label, String value, IconData icon, Color color, Color secondaryText) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(fontSize: 11, color: secondaryText)),
            ],
          ),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: color)),
        ],
      ),
    );
  }

  Widget _buildImportSection(
      Color surface, Color surfaceAlt, Color border, Color primaryText, Color secondaryText) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Importação de Pedidos',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: primaryText)),
          const SizedBox(height: 4),
          Text(
              'Importe um CSV com pedidos operacionais. O sistema associará automaticamente cada pedido ao hub mais próximo.',
              style: TextStyle(fontSize: 12, color: secondaryText)),
          const SizedBox(height: 12),

          // Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isLoading ? null : _pickFile,
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: Text(_csvFileName != null
                      ? _csvFileName!
                      : 'Selecionar CSV'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primaryText,
                    side: BorderSide(color: border),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (_isLoading || _csvContent == null) ? null : _import,
                  icon: const Icon(Icons.cloud_upload, size: 18),
                  label: const Text('Importar'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Status
          if (_isLoading || _status.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: surfaceAlt,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  if (_isLoading)
                    const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _status,
                      style: TextStyle(fontSize: 12, color: primaryText),
                    ),
                  ),
                ],
              ),
            ),

          // Error
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),

          // Import results
          if (_imported != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _resultBadge(
                      'Importados', _imported ?? 0, Colors.green),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _resultBadge(
                      'Ignorados', _ignored ?? 0, Colors.orange),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _resultBadge(
                      'Com falha', _failed ?? 0, Colors.red),
                ),
              ],
            ),
            // Expandable details
            if (_importedData.isNotEmpty)
              _expandableSection(
                  'Pedidos Importados (${_importedData.length})',
                  _importedData, Colors.green),
            if (_ignoredData.isNotEmpty)
              _expandableSection(
                  'Pedidos Ignorados (${_ignoredData.length})',
                  _ignoredData, Colors.orange),
            if (_failedData.isNotEmpty)
              _expandableSection(
                  'Pedidos com Falha (${_failedData.length})',
                  _failedData, Colors.red),
          ],

          // CSV instructions
          if (_imported == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: surfaceAlt,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Colunas obrigatórias:',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: primaryText)),
                  const SizedBox(height: 4),
                  Text(
                      'order_id, origin_zip_code, destination_zip_code, purchase_at, dispatched_at, estimated_delivery_at, seller_state, customer_state, items_count, sellers_count, price, freight_value',
                      style: TextStyle(
                          fontSize: 10,
                          color: secondaryText,
                          fontFamily: 'monospace')),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _resultBadge(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$value',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color)),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }

  Widget _expandableSection(
      String title, List<Map<String, dynamic>> items, Color color) {
    return _Accordion(
      header: Text(title,
          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
      content: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return ListTile(
            dense: true,
            title: Text(item['order_id']?.toString() ?? '',
                style: const TextStyle(fontSize: 12)),
            subtitle: Text(item['reason']?.toString() ??
                item['hub_id']?.toString() ??
                ''),
            leading: Icon(Icons.info, color: color, size: 16),
          );
        },
      ),
    );
  }

  Widget _buildOrdersListing(
      Color surface, Color surfaceAlt, Color border, Color primaryText, Color secondaryText) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with count
          Row(
            children: [
              Text('Pedidos Operacionais',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: primaryText)),
              const SizedBox(width: 8),
              Text('$_total pedido${_total != 1 ? 's' : ''}',
                  style: TextStyle(fontSize: 12, color: secondaryText)),
            ],
          ),
          const SizedBox(height: 12),

          // Search + Filters
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Buscar por ID...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: border)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: border)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: Color(0xFF2563EB))),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    isDense: true,
                  ),
                  onChanged: _onSearchChanged,
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<_OrderFilter>(
                value: _filter,
                onChanged: _onFilterChanged,
                items: _OrderFilter.values
                    .map((f) => DropdownMenuItem(
                          value: f,
                          child: Text(f.label,
                              style: const TextStyle(fontSize: 12)),
                        ))
                    .toList(),
                underline: const SizedBox(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Content
          _loadingOrders
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : _ordersError != null
                  ? _buildErrorState(primaryText, secondaryText)
                  : _orders.isEmpty
                      ? _buildEmptyState(secondaryText)
                      : _buildTable(surfaceAlt, border, primaryText, secondaryText),

          // Pagination
          if (!_loadingOrders && _ordersError == null && _totalPages > 1)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: _page > 1
                        ? () => _loadOrders(page: _page - 1)
                        : null,
                    icon: const Icon(Icons.chevron_left, size: 16),
                    label: const Text('Anterior',
                        style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 8),
                  Text('Página $_page de $_totalPages',
                      style: TextStyle(fontSize: 12, color: secondaryText)),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _page < _totalPages
                        ? () => _loadOrders(page: _page + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right, size: 16),
                    label: const Text('Próxima',
                        style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorState(Color primaryText, Color secondaryText) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 40,
              color: Color(0xFFEF4444)),
          const SizedBox(height: 8),
          Text('Erro ao carregar pedidos',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFEF4444))),
          const SizedBox(height: 4),
          Text(_ordersError ?? 'Não foi possível conectar à API.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: secondaryText)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _loadOrders,
            child: const Text('Tentar novamente',
                style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(Color secondaryText) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox_outlined, size: 48,
              color: Color(0xFF94A3B8)),
          const SizedBox(height: 8),
          Text('Nenhum pedido operacional',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: secondaryText)),
          const SizedBox(height: 4),
          const Text(
              'Importe pedidos via CSV para começar.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
        ],
      ),
    );
  }

  Widget _buildTable(
      Color surfaceAlt, Color border, Color primaryText, Color secondaryText) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(surfaceAlt),
        border: TableBorder.all(color: border, width: 0.5),
        columns: const [
          DataColumn(label: Text('ID Pedido')),
          DataColumn(label: Text('CEP Origem')),
          DataColumn(label: Text('CEP Destino')),
          DataColumn(label: Text('Entrega prometida')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Hub')),
          DataColumn(label: Text('Importado em')),
          DataColumn(label: Text('Ações')),
        ],
        rows: _orders.map((order) {
          final hub = order['hub'];
          return DataRow(cells: [
            DataCell(
              Text(
                order['order_id']?.toString() ?? '',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 11),
              ),
            ),
            DataCell(Text(
              order['origin_zip_code']?.toString() ?? '—',
              style: const TextStyle(fontSize: 11),
            )),
            DataCell(Text(
              order['destination_zip_code']?.toString() ?? '—',
              style: const TextStyle(fontSize: 11),
            )),
            DataCell(Text(
              _formatDate(order['estimated_delivery_at']?.toString()) ?? '—',
              style: const TextStyle(fontSize: 11),
            )),
            DataCell(Text(
              _statusLabel(order['status']?.toString()),
              style: const TextStyle(fontSize: 11),
            )),
            DataCell(Text(
              _formatHub(hub) ?? '—',
              style: TextStyle(
                  fontSize: 11,
                  color: hub != null ? primaryText : Colors.orange),
            )),
            DataCell(Text(
              _formatDate(order['created_at']) ?? '—',
              style: const TextStyle(fontSize: 11),
            )),
            DataCell(Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.visibility, size: 16,
                      color: Color(0xFF2563EB)),
                  tooltip: 'Ver detalhes',
                  onPressed: () => _showOrderDetails(order),
                ),
                IconButton(
                  icon: const Icon(Icons.swap_horiz, size: 16,
                      color: Color(0xFF7C3AED)),
                  tooltip: 'Alterar hub',
                  onPressed: () => _showChangeHubDialog(order),
                ),
              ],
            )),
          ]);
        }).toList(),
      ),
    );
  }

  void _showOrderDetails(Map<String, dynamic> order) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText = isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A);
    final secondaryText = isDark ? const Color(0xFFB5C2D4) : const Color(0xFF64748B);

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.receipt_long, size: 20,
                color: Color(0xFF2563EB)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                order['order_id']?.toString() ?? '',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow('CEP de origem',
                  order['origin_zip_code']?.toString() ?? '—', primaryText),
              _detailRow('CEP de destino',
                  order['destination_zip_code']?.toString() ?? '—', primaryText),
              _detailRow('Entrega prometida',
                  _formatDate(order['estimated_delivery_at']?.toString()) ?? '—', primaryText),
              _detailRow('Status', _statusLabel(order['status']?.toString()), primaryText),
              _detailRow('UF do vendedor',
                  order['seller_state']?.toString() ?? '—', primaryText),
              _detailRow('UF do cliente',
                  order['customer_state']?.toString() ?? '—', primaryText),
              _detailRow('Hub associado',
                  _formatHub(order['hub']) ?? '—',
                  order['hub'] != null ? primaryText : Colors.orange),
              _detailRow('Origem dos dados',
                  order['source']?.toString() ?? 'operational', primaryText),
              _detailRow('Importado em',
                  _formatDate(order['created_at']) ?? '—', secondaryText),
              _detailRow('Atualizado em',
                  _formatDate(order['updated_at']) ?? '—', secondaryText),
              const SizedBox(height: 8),
              _detailRow('Preço',
                  order['price'] != null
                      ? 'R\$ ${order['price'].toStringAsFixed(2)}'
                      : '—',
                  primaryText),
              _detailRow('Frete',
                  order['freight_value'] != null
                      ? 'R\$ ${order['freight_value'].toStringAsFixed(2)}'
                      : '—',
                  primaryText),
              _detailRow('Itens',
                  order['items_count']?.toString() ?? '—', primaryText),
              _detailRow('Peso total (kg)',
                  order['total_weight_g'] == null ? '—' : ((order['total_weight_g'] as num) / 1000).toString(), primaryText),
              _detailRow('Volume total (cm³)',
                  order['total_volume_cm3']?.toString() ?? '—', primaryText),
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

  Widget _detailRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B))),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(fontSize: 12, color: valueColor)),
          ),
        ],
      ),
    );
  }

  void _showChangeHubDialog(Map<String, dynamic> order) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText = isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A);

    String? selectedHubId = order['hub_id'];

    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.swap_horiz, size: 20, color: Color(0xFF7C3AED)),
              const SizedBox(width: 8),
              const Expanded(child: Text('Alterar hub')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pedido: ${order['order_id']}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: primaryText)),
                const SizedBox(height: 8),
                Text('Hub atual:',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF64748B))),
                Text(_formatHub(order['hub']) ?? '—',
                    style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 12),
                Text('Selecionar novo hub:',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: primaryText)),
                const SizedBox(height: 8),
                if (_loadingHubs)
                  const Center(child: CircularProgressIndicator(strokeWidth: 2))
                else
                  DropdownButtonFormField<String?>(
                    value: selectedHubId,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('(Sem hub)'),
                      ),
                      ..._hubs.map((hub) => DropdownMenuItem(
                            value: hub['id'] as String?,
                            child: Text(
                                '${hub['name']} · ${hub['code']} (${hub['city']}/${hub['state']})'),
                          )),
                    ],
                    onChanged: (value) {
                      setDialogState(() {
                        selectedHubId = value;
                      });
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: (selectedHubId != order['hub_id'])
                  ? () async {
                      Navigator.pop(context);
                      try {
                        await _ordersApi.setHub(
                            order['order_id'] as String, selectedHubId);
                        if (mounted) {
                          _loadOrders();
                          _loadSummary();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Hub atualizado com sucesso')),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Erro: $e')),
                          );
                        }
                      }
                    }
                  : null,
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Accordion extends StatefulWidget {
  final Widget header;
  final Widget content;

  const _Accordion({required this.header, required this.content});

  @override
  State<_Accordion> createState() => _AccordionState();
}

class _AccordionState extends State<_Accordion> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                widget.header,
                Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18),
              ],
            ),
          ),
        ),
        if (_expanded)
          Container(
            constraints: const BoxConstraints(maxHeight: 250),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF172338) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
            ),
            child: widget.content,
          ),
      ],
    );
  }
}
