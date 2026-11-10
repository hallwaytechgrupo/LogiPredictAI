/// Tela de importação de pedidos operacionais via CSV.
///
/// Substitui a tela de simulação Olist em lote.
library;

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/orders_api.dart';
import '../services/shipment_csv_service.dart';

class OrdersImportScreen extends StatefulWidget {
  const OrdersImportScreen({super.key});

  @override
  State<OrdersImportScreen> createState() => _OrdersImportScreenState();
}

class _OrdersImportScreenState extends State<OrdersImportScreen> {
  final _ordersApi = OrdersApi();
  bool _isLoading = false;
  String? _error;
  String? _csvContent;
  String _status = 'Selecione um arquivo CSV para importar.';

  int? _imported;
  int? _ignored;
  int? _failed;
  List<Map<String, dynamic>> _importedData = [];
  List<Map<String, dynamic>> _ignoredData = [];
  List<Map<String, dynamic>> _failedData = [];

  Future<void> _pickFile() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _status = 'Selecionando arquivo...';
      _csvContent = null;
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

      final bytes = result.files.single.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw const FormatException('O arquivo CSV está vazio ou não pôde ser lido.');
      }
      final csv = utf8.decode(bytes).replaceFirst('\uFEFF', '');
      if (csv.trim().isEmpty) {
        throw const FormatException('O arquivo CSV está vazio.');
      }
      setState(() {
        _csvContent = csv;
        _status = 'Arquivo carregado. Clique em "Importar" para processar.';
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
      // Validar localmente primeiro
      ShipmentCsvService.parseShipments(_csvContent!, requireZipCodes: true);
      setState(() {
        _status = 'Enviando para o servidor...';
      });

      // Enviar para o backend
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
    } catch (e) {
      setState(() {
        _error = 'Erro na importação: $e';
        _status = 'Erro';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF172338) : Colors.white;
    final primaryText = isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A);
    final secondaryText = isDark ? const Color(0xFFB5C2D4) : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Importação de Pedidos',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: primaryText,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Importe um CSV com pedidos operacionais. O sistema associará automaticamente cada pedido ao hub mais próximo.',
                style: TextStyle(fontSize: 14, color: secondaryText),
              ),
              const SizedBox(height: 24),

              // Botões de ação
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _pickFile,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Selecionar CSV'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (_isLoading || _csvContent == null) ? null : _import,
                      icon: const Icon(Icons.cloud_upload),
                      label: const Text('Importar'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Status
              if (_isLoading || _status.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isDark ? const Color(0xFF33445D) : const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      if (_isLoading) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _status,
                          style: TextStyle(color: primaryText),
                        ),
                      ),
                    ],
                  ),
                ),

              // Erro
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),

              const SizedBox(height: 16),

              // Resultados
              if (_imported != null) ...[
                // Resumo
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isDark ? const Color(0xFF33445D) : const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _statCard('Importados', _imported ?? 0, Colors.green),
                          _statCard('Ignorados', _ignored ?? 0, Colors.orange),
                          _statCard('Com falha', _failed ?? 0, Colors.red),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Detalhes expansíveis
                if (_importedData.isNotEmpty)
                  _expandableSection('Pedidos Importados (${_importedData.length})', _importedData, Colors.green),
                if (_ignoredData.isNotEmpty)
                  _expandableSection('Pedidos Ignorados (${_ignoredData.length})', _ignoredData, Colors.orange),
                if (_failedData.isNotEmpty)
                  _expandableSection('Pedidos com Falha (${_failedData.length})', _failedData, Colors.red),
              ],

              const Spacer(),

              // Instruções
              if (_imported == null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isDark ? const Color(0xFF33445D) : const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Colunas obrigatórias do CSV:', style: TextStyle(fontWeight: FontWeight.bold, color: primaryText)),
                      const SizedBox(height: 8),
                      Text(
                        'order_id, origin_zip_code, destination_zip_code, purchase_at, dispatched_at, estimated_delivery_at, seller_state, customer_state, items_count, sellers_count, price, freight_value',
                        style: TextStyle(fontSize: 11, color: secondaryText, fontFamily: 'monospace'),
                      ),
                      const SizedBox(height: 8),
                      Text('Campos opcionais: distance_km, total_weight_g, total_volume_cm3',
                          style: TextStyle(fontSize: 11, color: secondaryText)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statCard(String label, int value, Color color) {
    return Column(
      children: [
        Text('$value', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _expandableSection(String title, List<Map<String, dynamic>> items, Color color) {
    return Accordion(
      header: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      content: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return ListTile(
            dense: true,
            title: Text(item['order_id']?.toString() ?? ''),
            subtitle: Text(item['reason']?.toString() ?? item['hub_id']?.toString() ?? ''),
            leading: Icon(Icons.info, color: color, size: 18),
          );
        },
      ),
    );
  }
}

class Accordion extends StatefulWidget {
  final Widget header;
  final Widget content;

  const Accordion({super.key, required this.header, required this.content});

  @override
  State<Accordion> createState() => _AccordionState();
}

class _AccordionState extends State<Accordion> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                widget.header,
                Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              ],
            ),
          ),
        ),
        if (_expanded)
          Container(
            constraints: const BoxConstraints(maxHeight: 300),
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
