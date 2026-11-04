/// Tela de gerenciamento de hubs logísticos.
///
/// Permite criar, editar, aprovar, desaprovar e excluir hubs.
/// Suporta importação em lote a partir de CSV.
library;

import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/hubs_api.dart';
import '../services/shipment_csv_service.dart';

/// Tela com lista de hubs e ações de CRUD.
class HubsManagementScreen extends StatefulWidget {
  const HubsManagementScreen({super.key, this.api});
  final HubsApi? api;
  @override
  State<HubsManagementScreen> createState() => _HubsManagementScreenState();
}

class _HubsManagementScreenState extends State<HubsManagementScreen> {
  late final HubsApi _api = widget.api ?? HubsApi();
  final _search = TextEditingController();
  List<LogisticHub> _hubs = [];
  final Set<String> _selectedHubIds = {};
  bool _loading = true;
  bool _importing = false;
  bool _includeInactive = true;
  String _validationStatusFilter = 'all';
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _selectedHubIds.clear();
    });
    try {
      final hubs = await _api.list(
        includeInactive: _includeInactive,
        query: _search.text,
        validationStatus: _validationStatusFilter,
      );
      if (!mounted) return;
      setState(() {
        _hubs = hubs;
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

  Future<void> _addMany() async {
    final selected = _hubs
        .where((hub) => _selectedHubIds.contains(hub.id))
        .toList();
    final pending = selected
        .where((hub) => hub.validationStatus == 'PENDENTE_VALIDACAO')
        .length;
    if (pending == 0) {
      _snack('Selecione ao menos um candidato pendente para adicionar.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Adicionar hubs selecionados?'),
        content: Text('$pending candidatos pendentes serão aprovados e ativados.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Adicionar')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final result = await _api.approveMany(
        selected.map((hub) => hub.id).toList(),
      );
      if (!mounted) return;
      _snack(result['added'].toString() +
          ' hubs adicionados; ' +
          result['skipped'].toString() +
          ' já estavam aprovados ou rejeitados.');
      await _load();
    } catch (e) {
      _snack('Não foi possível adicionar os hubs: ' + e.toString());
    }
  }

  Future<void> _deleteSelected() async {
    final ids = List<String>.from(_selectedHubIds);
    if (ids.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir hubs selecionados?'),
        content: Text(ids.length.toString() + ' hubs serão removidos permanentemente.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final deleted = await _api.deleteMany(ids);
      if (!mounted) return;
      _selectedHubIds.clear();
      _snack(deleted.toString() + ' hubs excluídos.');
      await _load();
    } catch (e) {
      _snack('Não foi possível excluir os hubs: ' + e.toString());
    }
  }

  Future<void> _importCsv() async {
    if (_importing) return;
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
        throw const FormatException('O arquivo CSV está vazio ou não pôde ser lido.');
      }
      final records = ShipmentCsvService.parseCsv(
        utf8.decode(bytes, allowMalformed: true).replaceFirst('\uFEFF', ''),
      );
      if (records.length < 2) throw const FormatException('O CSV precisa conter cabeçalho e candidatos.');
      final headers = records.first.map((value) => value.trim().toLowerCase()).toList();
      String value(List<String> row, List<String> aliases) {
        for (final alias in aliases) {
          final index = headers.indexOf(alias);
          if (index >= 0 && index < row.length) return row[index].trim();
        }
        return '';
      }
      double? number(String raw, String column, int line) {
        if (raw.isEmpty) return null;
        final parsed = double.tryParse(raw.replaceAll(',', '.'));
        if (parsed == null || !parsed.isFinite) throw FormatException('Linha $line: valor inválido em $column.');
        return parsed;
      }
      final candidates = <Map<String, dynamic>>[];
      for (var i = 1; i < records.length; i++) {
        final row = records[i];
        if (row.every((cell) => cell.trim().isEmpty)) continue;
        final line = i + 1;
        final code = value(row, ['code']);
        final name = value(row, ['name', 'name_ficticio']);
        final city = value(row, ['city', 'city_osm']);
        final state = value(row, ['state']);
        final osmId = value(row, ['osm_id']);
        final latitude = number(value(row, ['latitude']), 'latitude', line);
        final longitude = number(value(row, ['longitude']), 'longitude', line);
        if (code.isEmpty || name.length < 2 || state.length != 2 || osmId.isEmpty) {
          throw FormatException('Linha $line: code, nome, UF e osm_id são obrigatórios.');
        }
        if (latitude == null || longitude == null || latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
          throw FormatException('Linha $line: latitude ou longitude inválida.');
        }
        candidates.add({
          'code': code.toUpperCase(),
          'name': name,
          'city': city,
          'state': state.toUpperCase(),
          'validationStatus': 'PENDENTE_VALIDACAO',
          'osmId': osmId,
          'latitude': latitude,
          'longitude': longitude,
          'provisionalCategory': value(row, ['categoria_provisoria', 'tipo_provisorio']),
          'osmTags': value(row, ['etiquetas_osm', 'osm_tags']),
          'operator': value(row, ['operador']),
          'owner': value(row, ['proprietario']),
          'brand': value(row, ['marca', 'osm_name']),
          'osmUrl': value(row, ['url_osm', 'osm_url']),
          'classification': value(row, ['classe']),
          'justification': value(row, ['justificativa', 'status']),
        });
      }
      if (candidates.isEmpty) throw const FormatException('Nenhum candidato foi encontrado no CSV.');
      setState(() => _importing = true);
      final result = await _api.importCandidates(candidates);
      if (!mounted) return;
      _snack('Importação concluída: ${result['added']} novos, ${result['updated']} atualizados, ${result['unchanged']} sem alterações.');
      await _load();
    } catch (e) {
      _snack('Não foi possível importar o CSV: $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _edit([LogisticHub? hub]) async {
    final formKey = GlobalKey<FormState>();
    final code = TextEditingController(text: hub?.code ?? '');
    final name = TextEditingController(text: hub?.name ?? '');
    final city = TextEditingController(text: hub?.city ?? '');
    String state = hub?.state ?? 'SP';
    final validationStatus = hub?.validationStatus ?? 'APROVADO';
    const allStates = [
      'AC',
      'AL',
      'AP',
      'AM',
      'BA',
      'CE',
      'DF',
      'ES',
      'GO',
      'MA',
      'MT',
      'MS',
      'MG',
      'PA',
      'PB',
      'PR',
      'PE',
      'PI',
      'RJ',
      'RN',
      'RS',
      'RO',
      'RR',
      'SC',
      'SP',
      'SE',
      'TO'
    ];
    final Set<String> selectedStates = (hub?.statesServed ?? [])
        .where((uf) => allStates.contains(uf))
        .toSet();

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(hub == null ? 'Cadastrar hub' : 'Editar hub'),
          content: SizedBox(
            width: 480,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: code,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Código',
                        hintText: 'HUB-001',
                      ),
                      validator: (v) {
                        final x = (v ?? '').trim();
                        return RegExp(r'^[A-Za-z0-9_-]{2,32}$').hasMatch(x)
                            ? null
                            : 'Use 2–32 letras, números, hífen ou _.';
                      },
                    ),
                    TextFormField(
                      controller: name,
                      decoration: const InputDecoration(labelText: 'Nome'),
                      validator: (v) => (v ?? '').trim().length >= 2
                          ? null
                          : 'Informe o nome.',
                    ),
                    TextFormField(
                      controller: city,
                      decoration: const InputDecoration(labelText: 'Cidade'),
                      validator: (v) => validationStatus != 'APROVADO' ||
                              (v ?? '').trim().length >= 2
                          ? null
                          : 'Informe a cidade antes de aprovar.',
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: state,
                      decoration: const InputDecoration(labelText: 'UF do hub'),
                      items: allStates
                          .map((uf) => DropdownMenuItem(
                                value: uf,
                                child: Text(uf),
                              ))
                          .toList(),
                      onChanged: (v) {
                        setDialogState(() => state = v ?? state);
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Estados atendidos (cobertura)',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Selecione as UFs que este hub atende. '
                      'Se deixar vazio, o hub atenderá apenas à UF do hub.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: allStates.map((uf) {
                        final isSelected = selectedStates.contains(uf);
                        return FilterChip(
                          label: Text(uf),
                          selected: isSelected,
                          onSelected: (selected) {
                            setDialogState(() {
                              if (selected) {
                                selectedStates.add(uf);
                              } else {
                                selectedStates.remove(uf);
                              }
                            });
                          },
                          selectedColor: Colors.blue[100],
                          checkmarkColor: Colors.blue[700],
                        );
                      }).toList(),
                    ),
                    if (selectedStates.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Nenhum estado selecionado — o hub usará a UF do hub como cobertura padrão.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[700],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      try {
        final statesServedList =
            selectedStates.isNotEmpty ? selectedStates.toList() : null;
        if (hub == null) {
          await _api.create(
              code: code.text.trim().toUpperCase(),
              name: name.text.trim(),
              city: city.text.trim(),
              state: state,
              statesServed: statesServedList);
        } else {
          await _api.update(hub,
              code: code.text.trim().toUpperCase(),
              name: name.text.trim(),
              city: city.text.trim(),
              state: state,
              statesServed: statesServedList);
        }
        _snack(hub == null ? 'Hub cadastrado.' : 'Hub atualizado.');
        await _load();
      } catch (e) {
        _snack(e.toString());
      }
    }
    code.dispose();
    name.dispose();
    city.dispose();
  }

  Future<void> _toggle(LogisticHub hub) async {
    try {
      await _api.setActive(hub, !hub.isActive);
      _snack(hub.isActive ? 'Hub desativado.' : 'Hub ativado.');
      await _load();
    } catch (e) {
      _snack(e.toString());
    }
  }

  Future<void> _setValidationStatus(
    LogisticHub hub,
    String validationStatus,
  ) async {
    try {
      await _api.setValidationStatus(hub, validationStatus);
      final message = switch (validationStatus) {
        'APROVADO' => 'Hub aprovado e ativado.',
        'REJEITADO' => 'Candidato rejeitado.',
        _ => 'Candidato devolvido para validação.',
      };
      _snack(message);
      await _load();
    } catch (e) {
      _snack(e.toString());
    }
  }

  Future<void> _showDetails(LogisticHub hub) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(hub.name),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _detail('Código', hub.code),
                _detail('Cidade/UF', _locationLabel(hub)),
                _detail('Validação', hub.validationStatus),
                if (hub.hasPendingCoverage)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Cobertura',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '⚠ Configuração pendente — o hub usará ${hub.state} como cobertura padrão.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.orange[700],
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Estados atendidos',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: hub.statesServed!
                              .map((uf) => Chip(
                                    label: Text(uf),
                                    visualDensity: VisualDensity.compact,
                                  ))
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                _detail('Categoria OSM', hub.provisionalCategory),
                _detail('Classificação', hub.classification),
                _detail('Operador', hub.operatorName),
                _detail('Proprietário', hub.owner),
                _detail('Marca', hub.brand),
                _detail('Coordenadas', hub.latitude == null || hub.longitude == null
                    ? null
                    : '${hub.latitude}, ${hub.longitude}'),
                _detail('ID OpenStreetMap', hub.osmId),
                _detail('URL OpenStreetMap', hub.osmUrl),
                _detail('Etiquetas OSM', hub.osmTags),
                _detail('Justificativa', hub.justification),
              ],
            ),
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

  Widget _detail(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          SelectableText(value),
        ],
      ),
    );
  }

  String _locationLabel(LogisticHub hub) => hub.city.isEmpty
      ? 'Município não informado/${hub.state}'
      : '${hub.city}/${hub.state}';

  Future<void> _delete(LogisticHub hub) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Excluir hub?'),
              content: Text('O hub ${hub.name} será removido permanentemente.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Excluir'))
              ],
            ));
    if (confirmed != true) return;
    try {
      await _api.delete(hub.id);
      _snack('Hub excluído.');
      await _load();
    } catch (e) {
      _snack(e.toString());
    }
  }

  void _snack(String message) {
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Gestão de hubs'), actions: [
          IconButton(tooltip: 'Importar candidatos CSV', onPressed: _importing ? null : _importCsv, icon: _importing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.upload_file)),
          IconButton(
              tooltip: 'Atualizar',
              onPressed: _load,
              icon: const Icon(Icons.refresh))
        ]),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _edit(),
            icon: const Icon(Icons.add),
            label: const Text('Novo hub')),
        body: SafeArea(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  TextField(
                      controller: _search,
                      decoration: InputDecoration(
                          labelText: 'Buscar hubs',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: IconButton(
                              onPressed: _load,
                              icon: const Icon(Icons.search))),
                      onSubmitted: (_) => _load()),
                  DropdownButtonFormField<String>(
                    value: _validationStatusFilter,
                    decoration: const InputDecoration(labelText: 'Validação'),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('Todos')),
                      DropdownMenuItem(
                        value: 'PENDENTE_VALIDACAO',
                        child: Text('Pendentes de validação'),
                      ),
                      DropdownMenuItem(
                        value: 'APROVADO',
                        child: Text('Aprovados'),
                      ),
                      DropdownMenuItem(
                        value: 'REJEITADO',
                        child: Text('Rejeitados'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() => _validationStatusFilter = value ?? 'all');
                      _load();
                    },
                  ),
                  SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Incluir hubs inativos'),
                      value: _includeInactive,
                      onChanged: (v) {
                        setState(() => _includeInactive = v);
                        _load();
                      }),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _loading || _hubs.isEmpty
                              ? null
                              : () {
                                  setState(() {
                                    if (_selectedHubIds.length == _hubs.length) {
                                      _selectedHubIds.clear();
                                    } else {
                                      _selectedHubIds
                                        ..clear()
                                        ..addAll(_hubs.map((hub) => hub.id));
                                    }
                                  });
                                },
                          icon: Icon(_selectedHubIds.length == _hubs.length &&
                                  _hubs.isNotEmpty
                              ? Icons.deselect
                              : Icons.select_all),
                          label: Text(
                              _selectedHubIds.length == _hubs.length &&
                                      _hubs.isNotEmpty
                                  ? 'Limpar seleção'
                                  : 'Selecionar todos'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _loading || _selectedHubIds.isEmpty
                              ? null
                              : _addMany,
                          icon: const Icon(Icons.playlist_add),
                          label: Text('Adicionar selecionados (' +
                              _selectedHubIds.length.toString() +
                              ')'),
                        ),
                        if (_selectedHubIds.isNotEmpty)
                          FilledButton.icon(
                            onPressed: _loading ? null : _deleteSelected,
                            icon: const Icon(Icons.delete_outline),
                            label: Text('Excluir selecionados (' +
                                _selectedHubIds.length.toString() +
                                ')'),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : _error != null
                              ? Center(
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                      const Icon(Icons.cloud_off, size: 40),
                                      const SizedBox(height: 8),
                                      Text(_error!,
                                          textAlign: TextAlign.center),
                                      const SizedBox(height: 8),
                                      OutlinedButton(
                                          onPressed: _load,
                                          child: const Text('Tentar novamente'))
                                    ]))
                              : _hubs.isEmpty
                                  ? const Center(
                                      child: Text(
                                          'Nenhum hub cadastrado. Use “Novo hub” para começar.'))
                                  : ListView.separated(
                                      itemCount: _hubs.length,
                                      separatorBuilder: (_, __) =>
                                          const Divider(height: 1),
                                      itemBuilder: (context, index) {
                                        final hub = _hubs[index];
                                        return ListTile(
                                            leading: Checkbox(
                                                value: _selectedHubIds
                                                    .contains(hub.id),
                                                onChanged: (selected) {
                                                  setState(() {
                                                    if (selected == true) {
                                                      _selectedHubIds.add(hub.id);
                                                    } else {
                                                      _selectedHubIds
                                                          .remove(hub.id);
                                                    }
                                                  });
                                                }),
                                            title: Row(
                                              children: [
                                                Expanded(child: Text(hub.name)),
                                                if (hub.hasPendingCoverage)
                                                  Tooltip(
                                                    message:
                                                        'Cobertura pendente — apenas ${hub.state}',
                                                    child: Icon(
                                                      Icons.warning_amber_rounded,
                                                      size: 18,
                                                      color: Colors.orange[700],
                                                    ),
                                                  )
                                                else
                                                  Tooltip(
                                                    message:
                                                        'Atende ${hub.statesServed!.length} estado(s): ${hub.statesServed!.join(', ')}',
                                                    child: Icon(
                                                      Icons.check_circle,
                                                      size: 18,
                                                      color: Colors.green[700],
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            onTap: () => _showDetails(hub),
                                            subtitle: Text(
                                                '${hub.code} · ${_locationLabel(hub)} · ${hub.validationStatus}'),
                                            trailing: PopupMenuButton<String>(
                                                onSelected: (action) {
                                                  if (action == 'edit')
                                                    _edit(hub);
                                                  if (action == 'toggle')
                                                    _toggle(hub);
                                                  if (action == 'delete')
                                                    _delete(hub);
                                                  if (action == 'details')
                                                    _showDetails(hub);
                                                  if (action == 'approve')
                                                    _setValidationStatus(
                                                        hub, 'APROVADO');
                                                  if (action == 'reject')
                                                    _setValidationStatus(
                                                        hub, 'REJEITADO');
                                                  if (action == 'review')
                                                    _setValidationStatus(hub,
                                                        'PENDENTE_VALIDACAO');
                                                },
                                                itemBuilder: (_) => [
                                                      const PopupMenuItem(
                                                          value: 'details',
                                                          child: Text('Detalhes da fonte')),
                                                      if (hub.validationStatus == 'PENDENTE_VALIDACAO') ...[
                                                        const PopupMenuItem(
                                                            value: 'approve',
                                                            child: Text('Aprovar candidato')),
                                                        const PopupMenuItem(
                                                            value: 'reject',
                                                            child: Text('Rejeitar candidato')),
                                                      ],
                                                      if (hub.validationStatus != 'PENDENTE_VALIDACAO')
                                                        const PopupMenuItem(
                                                            value: 'review',
                                                            child: Text('Devolver para validação')),
                                                      const PopupMenuItem(
                                                          value: 'edit',
                                                          child:
                                                              Text('Editar')),
                                                      if (hub.validationStatus == 'APROVADO')
                                                        PopupMenuItem(
                                                            value: 'toggle',
                                                            child: Text(
                                                                hub.isActive
                                                                    ? 'Desativar'
                                                                    : 'Ativar')),
                                                      const PopupMenuItem(
                                                          value: 'delete',
                                                          child:
                                                              Text('Excluir'))
                                                    ]));
                                      })),
                  const SizedBox(height: 8),
                  const Text(
                      'Candidatos do OpenStreetMap precisam de validação antes de serem usados como hubs operacionais.',
                      style: TextStyle(fontSize: 12),
                      textAlign: TextAlign.center),
                ]))),
      );
}
