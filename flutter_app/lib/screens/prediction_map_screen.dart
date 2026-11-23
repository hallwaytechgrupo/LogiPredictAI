/// Planejamento de um pedido novo, com formulário lateral e mapa Leaflet.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/map_scenarios_api.dart';
import '../widgets/leaflet_map.dart';

class PredictionMapScreen extends StatefulWidget {
  const PredictionMapScreen({super.key, this.api, this.active = true});
  final MapScenariosApi? api;
  final bool active;
  @override
  State<PredictionMapScreen> createState() => _PredictionMapScreenState();
}

class _PredictionMapScreenState extends State<PredictionMapScreen> {
  late final MapScenariosApi _api = widget.api ?? MapScenariosApi();
  final _form = GlobalKey<FormState>();
  final _purchase = TextEditingController();
  final _dispatch = TextEditingController();
  final _deadline = TextEditingController();
  final _weight = TextEditingController();
  final _volume = TextEditingController();
  final _price = TextEditingController();
  final _freight = TextEditingController();
  final _items = TextEditingController(text: '1');
  final _seller = TextEditingController();
  Map<String, dynamic>? _origin, _destination, _result;
  String? _error;
  bool _busy = false, _exampleBusy = false, _modal = false;
  int _fit = 0, _reset = 0;
  bool get _disabled => _busy || _exampleBusy;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final purchase = DateTime(now.year, now.month, now.day + 1, 9);
    _setDates(purchase, purchase.add(const Duration(days: 1, hours: 6)),
        purchase.add(const Duration(days: 8, hours: 9)));
  }

  static String _format(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  static DateTime? _parse(String text) {
    final match = RegExp(r'^(\d{2})/(\d{2})/(\d{4})(?:\s+(\d{2}):(\d{2}))?$')
        .firstMatch(text.trim());
    if (match == null) return null;
    final parts = [
      for (final i in [1, 2, 3]) int.parse(match.group(i)!)
    ];
    final hour = int.parse(match.group(4) ?? '9'),
        minute = int.parse(match.group(5) ?? '0');
    final d = DateTime(parts[2], parts[1], parts[0], hour, minute);
    return d.year == parts[2] &&
            d.month == parts[1] &&
            d.day == parts[0] &&
            hour < 24 &&
            minute < 60
        ? d
        : null;
  }

  void _setDates(DateTime p, DateTime d, DateTime e) {
    _purchase.text = _format(p);
    _dispatch.text = _format(d);
    _deadline.text = _format(e);
  }

  void _invalidate() {
    if (_result != null) setState(() => _result = null);
  }

  @override
  void dispose() {
    for (final c in [
      _purchase,
      _dispatch,
      _deadline,
      _weight,
      _volume,
      _price,
      _freight,
      _items,
      _seller
    ]) {
      c.dispose();
    }
    if (widget.api == null) _api.close();
    super.dispose();
  }

  Future<void> _example() async {
    setState(() {
      _exampleBusy = true;
      _error = null;
      _result = null;
    });
    try {
      final places = await Future.wait([
        _api.get('locations', {'q': '01001'}),
        _api.get('locations', {'q': '20040'})
      ]);
      if (!mounted) return;
      final origins = (places[0]['data'] as List).cast<Map<String, dynamic>>();
      final destinations =
          (places[1]['data'] as List).cast<Map<String, dynamic>>();
      if (origins.isEmpty || destinations.isEmpty) {
        throw Exception('Exemplo indisponível no catálogo de CEPs.');
      }
      final now = DateTime.now();
      final year =
          DateTime(now.year, 12, 23).isBefore(now) ? now.year + 1 : now.year;
      setState(() {
        _origin = origins.first;
        _destination = destinations.first;
        _fit++;
        _reset++;
        _setDates(DateTime(year, 12, 23, 9), DateTime(year, 12, 24, 15),
            DateTime(year + 1, 1, 4, 18));
        _weight.text = '0,5';
        _volume.text = '1200';
        _price.text = '100';
        _freight.text = '20';
        _items.text = '1';
        _seller.clear();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _exampleBusy = false);
    }
  }

  Future<void> _run() async {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    if (_origin == null || _destination == null) {
      setState(() => _error =
          'Pesquise e selecione a origem e o destino pelas sugestões.');
      return;
    }
    double number(TextEditingController c) =>
        double.parse(c.text.trim().replaceAll(',', '.'));
    final body = <String, dynamic>{
      'purchase_at': _parse(_purchase.text)!.toIso8601String(),
      'dispatched_at': _parse(_dispatch.text)!.toIso8601String(),
      'estimated_delivery_at': _parse(_deadline.text)!.toIso8601String(),
      'origin_prefix5': _origin!['prefix5'],
      'destination_prefix5': _destination!['prefix5'],
      'total_weight_g': number(_weight) * 1000,
      if (_volume.text.trim().isNotEmpty) 'total_volume_cm3': number(_volume),
      'items_count': int.parse(_items.text.trim()),
      'price': number(_price),
      'freight_value': number(_freight),
      if (_seller.text.trim().isNotEmpty) 'seller_id': _seller.text.trim(),
    };
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _api.forecast(body);
      if (mounted) {
        setState(() {
          _result = result;
          _fit++;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDate(TextEditingController c, String label) async {
    setState(() => _modal = true);
    try {
      final parsed = _parse(c.text);
      final current =
          parsed != null && parsed.year >= 2016 && parsed.year <= 2035
              ? parsed
              : DateTime.now();
      final d = await showDatePicker(
          context: context,
          initialDate: current,
          firstDate: DateTime(2016),
          lastDate: DateTime(2035, 12, 31),
          helpText: label,
          cancelText: 'Cancelar',
          confirmText: 'Confirmar');
      if (d != null && mounted) {
        c.text = _format(
            DateTime(d.year, d.month, d.day, current.hour, current.minute));
        _invalidate();
      }
    } finally {
      if (mounted) setState(() => _modal = false);
    }
  }

  Widget _section(String title, IconData icon) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 12),
      child: Row(children: [
        Icon(icon, size: 18, color: const Color(0xFF2563EB)),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))
      ]));
  Widget _date(TextEditingController c, String label, Key key) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
          key: key,
          controller: c,
          enabled: !_disabled,
          decoration: InputDecoration(
              labelText: label,
              hintText: 'DD/MM/AAAA HH:mm',
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                  tooltip: 'Escolher $label',
                  onPressed: _disabled ? null : () => _pickDate(c, label),
                  icon: const Icon(Icons.calendar_month_outlined, size: 19))),
          validator: (v) =>
              _parse(v ?? '') == null ? 'Use DD/MM/AAAA HH:mm.' : null));
  Widget _number(TextEditingController c, String label,
          {bool optional = false, bool integer = false, Key? key}) =>
      TextFormField(
          key: key,
          controller: c,
          enabled: !_disabled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
              labelText: label,
              isDense: true,
              border: const OutlineInputBorder()),
          validator: (v) {
            if (optional && (v ?? '').trim().isEmpty) return null;
            final n = double.tryParse((v ?? '').trim().replaceAll(',', '.'));
            if (n == null || !n.isFinite || n < 0) return 'Valor inválido.';
            if (integer &&
                (int.tryParse((v ?? '').trim()) == null || n < 1 || n > 10000)) {
              return 'Informe de 1 a 10.000 itens.';
            }
            return null;
          });

  Widget _sidebar() => Form(
      key: _form,
      onChanged: _invalidate,
      child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Planejar uma entrega',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text(
                'Informe uma compra futura e compare o risco antes de fechar o pedido.',
                style: TextStyle(color: Color(0xFF64748B), height: 1.45)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
                key: const ValueKey('future-example'),
                onPressed: _disabled ? null : _example,
                icon: const Icon(Icons.auto_awesome_outlined, size: 17),
                label: Text(_exampleBusy
                    ? 'Carregando exemplo…'
                    : 'Exemplo: compra em 23/12')),
            _section('Origem e destino', Icons.route_outlined),
            _LocationPicker(
                key: ValueKey('origin-$_reset'),
                label: 'De onde? CEP ou cidade',
                api: _api,
                value: _origin,
                enabled: !_disabled,
                onSelected: (p) => setState(() {
                      _origin = p;
                      _result = null;
                      _fit++;
                    })),
            const SizedBox(height: 12),
            _LocationPicker(
                key: ValueKey('destination-$_reset'),
                label: 'Para onde? CEP ou cidade',
                api: _api,
                value: _destination,
                enabled: !_disabled,
                onSelected: (p) => setState(() {
                      _destination = p;
                      _result = null;
                      _fit++;
                    })),
            _section('Quando?', Icons.event_outlined),
            _date(_purchase, 'Data/hora da compra',
                const ValueKey('future-purchase')),
            _date(_dispatch, 'Data/hora do despacho',
                const ValueKey('future-dispatch')),
            _date(_deadline, 'Prazo prometido',
                const ValueKey('future-deadline')),
            _section('O que será enviado?', Icons.inventory_2_outlined),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                  child: _number(_weight, 'Peso (kg)',
                      key: const ValueKey('future-weight'))),
              const SizedBox(width: 10),
              Expanded(child: _number(_items, 'Qtd. de itens', integer: true))
            ]),
            const SizedBox(height: 12),
            _number(_volume, 'Volume (cm³, opcional)', optional: true),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _number(_price, 'Produtos (R\$)')),
              const SizedBox(width: 10),
              Expanded(child: _number(_freight, 'Frete (R\$)'))
            ]),
            const SizedBox(height: 8),
            ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Vendedor conhecido',
                    style: TextStyle(fontSize: 13)),
                children: [
                  TextFormField(
                      controller: _seller,
                      enabled: !_disabled,
                      decoration: const InputDecoration(
                          labelText: 'ID Olist do vendedor (opcional)',
                          isDense: true,
                          border: OutlineInputBorder())),
                  const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                          'Deixe vazio se não conhece o ID. A análise usará a rota e a região, sem atribuir o histórico de outro vendedor.',
                          style: TextStyle(
                              fontSize: 12, color: Color(0xFF64748B)))),
                ]),
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!,
                      key: const ValueKey('future-error'),
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error))),
            FilledButton.icon(
                key: const ValueKey('map-simulate'),
                onPressed: _disabled ? null : _run,
                icon: _busy
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.insights_outlined),
                label: Text(_busy ? 'Analisando…' : 'Calcular risco'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: const Color(0xFF2563EB))),
            const SizedBox(height: 10),
            const Text(
                'Uma origem por simulação. Os valores do exemplo são hipotéticos; o treinamento permanece o mesmo.',
                style: TextStyle(
                    fontSize: 11, color: Color(0xFF64748B), height: 1.4)),
          ])));

  Color _riskColor(String? risk) => risk == 'Alto'
      ? const Color(0xFFDC2626)
      : risk == 'Médio'
          ? const Color(0xFFD97706)
          : const Color(0xFF15803D);
  String _shortDate(dynamic text) {
    final d = DateTime.tryParse(text?.toString() ?? '');
    return d == null
        ? ''
        : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  Widget _resultPanel() {
    if (_result == null) {
      return const Padding(
          padding: EdgeInsets.all(22),
          child: Row(children: [
            Icon(Icons.travel_explore, size: 32, color: Color(0xFF2563EB)),
            SizedBox(width: 14),
            Expanded(
                child: Text(
                    'Monte sua entrega no painel à esquerda. O mapa mostrará a origem, o destino e a classificação calculada pelo modelo.',
                    style: TextStyle(color: Color(0xFF64748B), height: 1.5)))
          ]));
    }
    final r = _result!['result'] as Map<String, dynamic>;
    final calendar = _result!['calendar'] as Map<String, dynamic>;
    final holidays = calendar['fixed_national_holidays'] as List;
    final color = _riskColor(r['risk'] as String);
    return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(
              spacing: 18,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: .09),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text('Risco ${r['risk'].toString().toLowerCase()}',
                        style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w800,
                            fontSize: 19))),
                Text(
                    '${r['remaining_days']} dias disponíveis · ${(_result!['shipment']['distance_km'] as num).toStringAsFixed(0)} km em linha reta',
                    style: const TextStyle(color: Color(0xFF64748B))),
              ]),
          const SizedBox(height: 10),
          Text(r['predicted_late'] == true
              ? 'O modelo manteve o alerta de atraso para este cenário.'
              : 'O modelo não manteve um alerta de atraso para este cenário.'),
          if (r['already_overdue'] == true)
            const Text('O prazo informado já estará vencido no despacho.',
                style: TextStyle(
                    color: Color(0xFFDC2626), fontWeight: FontWeight.w600)),
          if (holidays.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                    'No período: ${holidays.map((h) => '${h['name']} (${_shortDate(h['date'])})').join(' · ')}',
                    style: const TextStyle(
                        color: Color(0xFFB45309),
                        fontWeight: FontWeight.w600))),
          const SizedBox(height: 14),
          const Text('Compare outras possibilidades',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final a in (_result!['alternatives'] as List)
                .cast<Map<String, dynamic>>())
              SizedBox(
                  width: 242,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        border:
                            Border.all(color: Theme.of(context).dividerColor),
                        borderRadius: BorderRadius.circular(10)),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a['label'] as String,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 12)),
                          const SizedBox(height: 5),
                          Text('${a['risk']} risco',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: _riskColor(a['risk'] as String))),
                          Text(
                              'Despacho ${_shortDate(a['dispatched_at'])} · prazo ${_shortDate(a['estimated_delivery_at'])}',
                              style: const TextStyle(
                                  fontSize: 11, color: Color(0xFF64748B))),
                        ]),
                  ))
          ]),
          const SizedBox(height: 12),
          for (final suggestion in _result!['suggestions'] as List)
            Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text('• $suggestion',
                    style: const TextStyle(fontSize: 12))),
          const SizedBox(height: 6),
          const Text(
              'Estimativa exploratória com dados Olist de 2016–2018. Não é garantia de entrega nem uma porcentagem calibrada. Feriados aparecem como contexto, sem efeito causal comprovado no modelo.',
              style: TextStyle(
                  fontSize: 11, color: Color(0xFF64748B), height: 1.4)),
          ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Detalhes da análise',
                  style: TextStyle(fontSize: 12)),
              children: [
                Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(
                        'Modelo: ${_result!['model_version']}\nEntregas anteriores na rota: ${r['history']['route_orders']}\nEntregas do vendedor identificado: ${r['history']['seller_orders']}\nScore do modelo: ${(r['score'] as num).toStringAsFixed(5)}\nCorte preservado: ${(r['threshold'] as num).toStringAsFixed(5)}',
                        style: const TextStyle(fontSize: 12))),
                for (final w in _result!['warnings'] as List)
                  Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text('• $w',
                              style: const TextStyle(fontSize: 11)))),
              ]),
        ]));
  }

  Widget _mapArea() =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            color: Theme.of(context).colorScheme.surface,
            child: Row(children: [
              const Icon(Icons.route, size: 18, color: Color(0xFF2563EB)),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(
                      _origin == null || _destination == null
                          ? 'Selecione de onde sai e para onde vai a entrega'
                          : '${_origin!['city']} / ${_origin!['state']}  →  ${_destination!['city']} / ${_destination!['state']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13))),
            ])),
        Expanded(
            child: widget.active
                ? LeafletMap(
                    key: const ValueKey('forecast-leaflet'),
                    blocked: _modal,
                    config: {
                        'mode': 'forecast',
                        'origin': _result?['origin'] ?? _origin,
                        'destination': _result?['destination'] ?? _destination,
                        'risk': _result?['result']?['risk'],
                        'fitToken': _fit,
                      })
                : const SizedBox.shrink()),
      ]);

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final sidebar = ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: Material(color: Colors.transparent, child: _sidebar()));
        final resultPanel = Material(
            color: Colors.transparent, child: _resultPanel());
        if (c.maxWidth < 900) {
          return SingleChildScrollView(
              child: Column(children: [
            SizedBox(height: 430, child: _mapArea()),
            sidebar,
            resultPanel
          ]));
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(width: 350, child: sidebar),
          const VerticalDivider(width: 1),
          Expanded(
              child: Column(children: [
            Expanded(child: _mapArea()),
            const Divider(height: 1),
            ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: _result == null ? 110 : c.maxHeight * .46),
                child: SingleChildScrollView(child: resultPanel)),
          ])),
        ]);
      });
}

/// Busca coordenadas reais por CEP ou cidade; não depende de um pedido importado.
class _LocationPicker extends StatefulWidget {
  const _LocationPicker(
      {super.key,
      required this.label,
      required this.api,
      required this.value,
      required this.enabled,
      required this.onSelected});
  final String label;
  final MapScenariosApi api;
  final Map<String, dynamic>? value;
  final bool enabled;
  final ValueChanged<Map<String, dynamic>?> onSelected;
  @override
  State<_LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<_LocationPicker> {
  final _text = TextEditingController();
  Timer? _timer;
  List<Map<String, dynamic>> _matches = [];
  bool _busy = false;
  String? _error;
  int _request = 0;
  String _label(Map<String, dynamic> p) =>
      '${p['city']} / ${p['state']} · ${p['prefix5']}';
  @override
  void initState() {
    super.initState();
    if (widget.value != null) _text.text = _label(widget.value!);
  }

  @override
  void didUpdateWidget(covariant _LocationPicker old) {
    super.didUpdateWidget(old);
    if (widget.value != null && widget.value != old.value) {
      _text.text = _label(widget.value!);
      _matches = [];
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _timer?.cancel();
    final id = ++_request;
    widget.onSelected(null);
    setState(() {
      _matches = [];
      _error = null;
      _busy = value.trim().length >= 2;
    });
    if (value.trim().length < 2) return;
    _timer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final response = await widget.api.get('locations', {'q': value.trim()});
        if (mounted && id == _request) {
          setState(() {
            _matches = (response['data'] as List)
                .cast<Map<String, dynamic>>()
                .take(5)
                .toList();
            _error = _matches.isEmpty
                ? 'Nenhum CEP encontrado. Tente outra cidade ou prefixo.'
                : null;
          });
        }
      } catch (e) {
        if (mounted && id == _request) setState(() => _error = e.toString());
      } finally {
        if (mounted && id == _request) setState(() => _busy = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
            controller: _text,
            enabled: widget.enabled,
            onChanged: _changed,
            decoration: InputDecoration(
                labelText: widget.label,
                hintText: 'CEP com 5/8 dígitos ou cidade',
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: widget.value != null
                    ? const Icon(Icons.check_circle_outline,
                        color: Color(0xFF15803D), size: 20)
                    : const Icon(Icons.search, size: 20))),
        if (_busy)
          const Padding(
              padding: EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(minHeight: 2)),
        if (_error != null)
          Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(_error!,
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFFB45309)))),
        for (final p in _matches)
          ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: Text('${p['city']} / ${p['state']}',
                  style: const TextStyle(fontSize: 12)),
              subtitle: Text('CEP ${p['prefix5']}',
                  style: const TextStyle(fontSize: 11)),
              onTap: widget.enabled
                  ? () {
                      _timer?.cancel();
                      _request++;
                      setState(() {
                        _matches = [];
                        _text.text = _label(p);
                      });
                      widget.onSelected(p);
                    }
                  : null),
      ]);
}
