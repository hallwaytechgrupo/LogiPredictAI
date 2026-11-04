/// Tela de listagem de pedidos importados.
///
/// Exibe os pedidos registrados no backend via GET /api/v1/orders,
/// com busca, paginação e enriquecimento com dados do hub associado.
library;

import 'package:flutter/material.dart';
import '../services/orders_api.dart';

/// Tela com lista de pedidos importados e ações de navegação.
class OrdersManagementScreen extends StatefulWidget {
  const OrdersManagementScreen({super.key, this.api});
  final OrdersApi? api;

  @override
  State<OrdersManagementScreen> createState() => _OrdersManagementScreenState();
}

class _OrdersManagementScreenState extends State<OrdersManagementScreen> {
  late final OrdersApi _api = widget.api ?? OrdersApi();
  final _search = TextEditingController();
  List<Map<String, dynamic>> _orders = [];
  int _total = 0;
  int _page = 1;
  static const int _perPage = 50;
  int _totalPages = 1;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({int? page}) async {
    final targetPage = page ?? _page;
    setState(() {
      if (page == null) _loading = true;
      _error = null;
    });
    try {
      final result = await _api.listOrders(
        page: targetPage,
        perPage: _perPage,
        query: _search.text.trim().isEmpty ? null : _search.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _orders = (result['data'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .toList() ??
            [];
        _total = result['total'] as int? ?? 0;
        _page = result['page'] as int? ?? targetPage;
        _totalPages = result['total_pages'] as int? ?? 1;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    _load(page: 1);
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF172338) : Colors.white;
    final surfaceAlt = isDark ? const Color(0xFF202F46) : const Color(0xFFF8FAFC);
    final border = isDark ? const Color(0xFF33445D) : const Color(0xFFE2E8F0);
    final primaryText = isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A);
    final secondaryText = isDark ? const Color(0xFFB5C2D4) : const Color(0xFF64748B);

    return Padding(
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
              Text('Pedidos Importados',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: primaryText)),
              const SizedBox(width: 12),
              Text('$_total pedido${_total != 1 ? 's' : ''}',
                  style: TextStyle(fontSize: 12, color: secondaryText)),
            ],
          ),
          const SizedBox(height: 12),

          // Search bar
          TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'Buscar por ID do pedido...',
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF2563EB))),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
            ),
            onChanged: _onSearchChanged,
          ),
          const SizedBox(height: 16),

          // Content
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildErrorState()
                    : _orders.isEmpty
                        ? _buildEmptyState()
                        : _buildTable(surface, surfaceAlt, border, primaryText,
                            secondaryText),
          ),

          // Pagination
          if (!_loading && _error == null && _totalPages > 1)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: _page > 1
                        ? () => _load(page: _page - 1)
                        : null,
                    icon: const Icon(Icons.chevron_left, size: 18),
                    label: const Text('Anterior'),
                  ),
                  const SizedBox(width: 8),
                  Text('Página $_page de $_totalPages',
                      style: TextStyle(fontSize: 13, color: secondaryText)),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _page < _totalPages
                        ? () => _load(page: _page + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right, size: 18),
                    label: const Text('Próxima'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48,
              color: Color(0xFFEF4444)),
          const SizedBox(height: 12),
          Text('Erro ao carregar pedidos',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFEF4444))),
          const SizedBox(height: 8),
          Text(_error ?? 'Não foi possível conectar à API.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _load,
            child: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox_outlined, size: 56,
              color: Color(0xFF94A3B8)),
          const SizedBox(height: 12),
          Text('Nenhum pedido importado',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF64748B))),
          const SizedBox(height: 8),
          const Text(
              'Importe pedidos via CSV ou execute uma simulação em lote para registrar pedidos.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8))),
        ],
      ),
    );
  }

  Widget _buildTable(
      Color surface, Color surfaceAlt, Color border, Color primaryText,
      Color secondaryText) {
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(surfaceAlt),
          border: TableBorder.all(color: border, width: 0.5),
          columns: const [
            DataColumn(label: Text('ID Pedido')),
            DataColumn(label: Text('Hub responsável')),
            DataColumn(label: Text('Origem')),
            DataColumn(label: Text('Criado em')),
            DataColumn(label: Text('Atualizado em')),
          ],
          rows: _orders.map((order) {
            final hub = order['hub'];
            return DataRow(cells: [
              DataCell(Text(
                order['order_id']?.toString() ?? '',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              )),
              DataCell(Text(
                _formatHub(hub) ?? '—',
                style: const TextStyle(fontSize: 12),
              )),
              DataCell(Text(
                (order['source'] as String?) ?? '—',
                style: const TextStyle(fontSize: 12),
              )),
              DataCell(Text(
                _formatDate(order['createdAt']) ?? '—',
                style: const TextStyle(fontSize: 12),
              )),
              DataCell(Text(
                _formatDate(order['updatedAt']) ?? '—',
                style: const TextStyle(fontSize: 12),
              )),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}
