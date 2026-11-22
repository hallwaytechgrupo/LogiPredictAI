/// Mapa de pedidos reais, classificação preservada e comparação de cenários.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_geojson2/flutter_map_geojson2.dart';
import 'package:latlong2/latlong.dart';
import '../services/map_scenarios_api.dart';

class PredictionMapScreen extends StatefulWidget {
  const PredictionMapScreen({super.key, this.api});
  final MapScenariosApi? api;

  @override
  State<PredictionMapScreen> createState() => _PredictionMapScreenState();
}

class _PredictionMapScreenState extends State<PredictionMapScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  late final MapScenariosApi _api = widget.api ?? MapScenariosApi();
  final _map = MapController();
  final _form = GlobalKey<FormState>();
  final _scenarioAnchor = GlobalKey();
  final _resultAnchor = GlobalKey();
  final _start = TextEditingController();
  final _end = TextEditingController();
  final _originPrefix = TextEditingController();
  final _destinationPrefix = TextEditingController();
  final _id = TextEditingController();
  final _purchase = TextEditingController();
  final _dispatch = TextEditingController();
  final _deadline = TextEditingController();
  final _destination = TextEditingController();
  final _weight = TextEditingController();
  final _volume = TextEditingController();
  final _price = TextEditingController();
  final _freight = TextEditingController();
  Map<String, dynamic>? _catalog, _page, _selected, _simulation;
  List<Map<String, dynamic>> _orders = [];
  String? _originState, _destinationState, _region, _risk, _sellerId;
  String? _error;
  String _sellerLabel = '';
  bool _loading = true,
      _searching = false,
      _selecting = false,
      _simulating = false;
  bool _streets = false, _mapReady = false;
  int _offset = 0, _selectionId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _start,
      _end,
      _originPrefix,
      _destinationPrefix,
      _id,
      _purchase,
      _dispatch,
      _deadline,
      _destination,
      _weight,
      _volume,
      _price,
      _freight
    ]) {
      c.dispose();
    }
    if (widget.api == null) _api.close();
    _map.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.get('catalog');
      if (!mounted) return;
      setState(() {
        _catalog = data;
        _start.text = data['start_date'] as String;
        _end.text = data['end_date'] as String;
        _loading = false;
      });
      await _search();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _search({int offset = 0}) async {
    setState(() {
      _searching = true;
      _error = null;
    });
    final query = <String, String>{'offset': '$offset', 'limit': '30'};
    for (final entry in <String, String?>{
      'start_date': _start.text.trim(),
      'end_date': _end.text.trim(),
      'origin_state': _originState,
      'destination_state': _destinationState,
      'region': _region,
      'risk': _risk,
      'origin_prefix': _originPrefix.text.trim(),
      'destination_prefix': _destinationPrefix.text.trim(),
      'order_id': _id.text.trim(),
    }.entries) {
      if (entry.value != null && entry.value!.isNotEmpty) {
        query[entry.key] = entry.value!;
      }
    }
    try {
      final result = await _api.get('orders', query);
      if (!mounted) return;
      setState(() {
        _page = result;
        _orders = (result['data'] as List).cast<Map<String, dynamic>>();
        _offset = offset;
        _selected = null;
        _simulation = null;
        _selectionId++;
        _selecting = false;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _select(Map<String, dynamic> item) async {
    final requestId = ++_selectionId;
    setState(() {
      _selecting = true;
      _simulation = null;
      _error = null;
    });
    try {
      final data =
          await _api.get('order', {'order_id': item['order_id'] as String});
      if (!mounted || requestId != _selectionId) return;
      final s = data['shipment'] as Map<String, dynamic>;
      setState(() {
        _selected = data;
        _sellerId = null;
        _sellerLabel =
            '${s['seller_state']} · CEP ${s['origin_prefix5']} · vendedor ${s['seller_id']}';
        _purchase.text = s['purchase_at'] as String;
        _dispatch.text = s['dispatched_at'] as String;
        _deadline.text = s['estimated_delivery_at'] as String;
        _destination.text = s['destination_prefix5'] as String;
        _weight.text = s['total_weight_g'] == null
            ? ''
            : '${(s['total_weight_g'] as num) / 1000}';
        _volume.text = s['total_volume_cm3']?.toString() ?? '';
        _price.text = s['price'].toString();
        _freight.text = s['freight_value'].toString();
      });
      _fit();
      _scrollTo(_scenarioAnchor);
    } catch (e) {
      if (mounted && requestId == _selectionId) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted && requestId == _selectionId) {
        setState(() => _selecting = false);
      }
    }
  }

  Future<void> _run() async {
    if (!_form.currentState!.validate()) return;
    final id = _selected!['order_id'];
    final selectionId = _selectionId;
    final body = <String, dynamic>{
      'order_id': id,
      'purchase_at': _purchase.text.trim().replaceFirst(' ', 'T'),
      'dispatched_at': _dispatch.text.trim().replaceFirst(' ', 'T'),
      'estimated_delivery_at': _deadline.text.trim().replaceFirst(' ', 'T'),
      'destination_prefix5':
          _destination.text.trim().replaceAll('-', '').substring(0, 5),
      if (_sellerId != null) 'seller_id': _sellerId,
    };
    for (final entry in <String, TextEditingController>{
      'total_weight_g': _weight,
      'total_volume_cm3': _volume,
      'price': _price,
      'freight_value': _freight,
    }.entries) {
      if (entry.value.text.trim().isNotEmpty) {
        final value =
            double.parse(entry.value.text.trim().replaceAll(',', '.'));
        body[entry.key] = entry.key == 'total_weight_g' ? value * 1000 : value;
      }
    }
    setState(() {
      _simulating = true;
      _error = null;
    });
    try {
      final result = await _api.simulate(body);
      if (!mounted || selectionId != _selectionId) return;
      setState(() => _simulation = result);
      _fit();
      _scrollTo(_resultAnchor);
    } catch (e) {
      if (mounted && selectionId == _selectionId) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) setState(() => _simulating = false);
    }
  }

  LatLng? _point(dynamic value) {
    if (value is! Map ||
        value['latitude'] is! num ||
        value['longitude'] is! num) {
      return null;
    }
    return LatLng((value['latitude'] as num).toDouble(),
        (value['longitude'] as num).toDouble());
  }

  void _fit() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_mapReady) return;
      final data = _simulation ?? _selected;
      final a = _point(data?['origin']), b = _point(data?['destination']);
      if (a == null || b == null) return;
      _map.fitCamera(CameraFit.bounds(
          bounds: LatLngBounds.fromPoints([a, b]),
          padding: const EdgeInsets.all(45),
          maxZoom: 10));
    });
  }

  void _scrollTo(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || key.currentContext == null) return;
      Scrollable.ensureVisible(key.currentContext!,
          alignment: .1, duration: const Duration(milliseconds: 250));
    });
  }

  Color _color(String? risk) => switch (risk) {
        'Alto' => const Color(0xFFDC2626),
        'Médio' => const Color(0xFFD97706),
        _ => const Color(0xFF15803D),
      };

  Widget _badge(String risk) => Chip(
      avatar: Icon(Icons.circle, size: 12, color: _color(risk)),
      label: Text('$risk risco'),
      visualDensity: VisualDensity.compact);

  Widget _card(Widget child) => Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(padding: const EdgeInsets.all(18), child: child));

  Widget _text(TextEditingController c, String label,
          {double width = 190,
          String? hint,
          bool number = false,
          String? Function(String?)? validator,
          Key? key}) =>
      SizedBox(
          width: width,
          child: TextFormField(
            key: key,
            controller: c,
            enabled: !_simulating && !_searching,
            keyboardType: number
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
            decoration: InputDecoration(
                labelText: label,
                hintText: hint,
                border: const OutlineInputBorder()),
            validator: validator ??
                (number
                    ? (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final n =
                            double.tryParse(v.trim().replaceAll(',', '.'));
                        return n == null || !n.isFinite || n < 0
                            ? 'Informe um número positivo ou zero.'
                            : null;
                      }
                    : null),
          ));

  Widget _dateField(TextEditingController c, String label,
          {bool time = false, Key? key}) =>
      SizedBox(
          width: time ? 260 : 190,
          child: TextFormField(
            key: key,
            controller: c,
            enabled: !_searching && !_simulating,
            validator: time
                ? (v) => DateTime.tryParse(v ?? '') == null
                    ? 'Use uma data válida.'
                    : null
                : null,
            decoration: InputDecoration(
                labelText: label,
                hintText: time ? 'AAAA-MM-DDTHH:MM:SS' : 'AAAA-MM-DD',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                    icon: const Icon(Icons.calendar_month),
                    tooltip: 'Escolher $label',
                    onPressed: _simulating || _searching
                        ? null
                        : () async {
                            final current = DateTime.tryParse(c.text) ??
                                DateTime(2018, 6, 1);
                            final picked = await showDatePicker(
                                context: context,
                                initialDate:
                                    current.year >= 2016 && current.year <= 2035
                                        ? current
                                        : DateTime(2018, 6, 1),
                                firstDate: DateTime(2016),
                                lastDate: DateTime(2035, 12, 31));
                            if (picked != null && mounted) {
                              c.text = time
                                  ? DateTime(
                                          picked.year,
                                          picked.month,
                                          picked.day,
                                          current.hour,
                                          current.minute,
                                          current.second)
                                      .toIso8601String()
                                      .split('.')
                                      .first
                                  : picked.toIso8601String().substring(0, 10);
                            }
                          })),
          ));

  Widget _dropdown(String label, String? value, List<String> options,
          ValueChanged<String?> changed) =>
      SizedBox(
          width: 185,
          child: DropdownButtonFormField<String>(
              key: ValueKey('$label-$value'),
              initialValue: value,
              isExpanded: true,
              decoration: InputDecoration(
                  labelText: label, border: const OutlineInputBorder()),
              items: [
                const DropdownMenuItem<String>(
                    value: null, child: Text('Todos')),
                ...options
                    .map((x) => DropdownMenuItem(value: x, child: Text(x)))
              ],
              onChanged: _searching || _simulating ? null : changed));

  Widget _filters() =>
      _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Pesquisar pedidos reais',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text(
            'As datas filtram a compra. Os riscos são previsões preservadas do teste histórico do modelo 564 + filtro.'),
        const SizedBox(height: 18),
        Wrap(spacing: 12, runSpacing: 14, children: [
          _dateField(_start, 'Compra a partir de'),
          _dateField(_end, 'Compra até'),
          _dropdown(
              'UF de origem',
              _originState,
              List<String>.from(_catalog!['states']),
              (v) => setState(() => _originState = v)),
          _dropdown(
              'UF de destino',
              _destinationState,
              List<String>.from(_catalog!['states']),
              (v) => setState(() => _destinationState = v)),
          _dropdown(
              'Região de destino',
              _region,
              List<String>.from(_catalog!['regions']),
              (v) => setState(() => _region = v)),
          _dropdown('Classificação', _risk, ['Baixo', 'Médio', 'Alto'],
              (v) => setState(() => _risk = v)),
          _text(_originPrefix, 'Prefixo CEP origem', hint: '1 a 5 dígitos'),
          _text(_destinationPrefix, 'Prefixo CEP destino',
              hint: '1 a 5 dígitos'),
          _text(_id, 'Parte do ID do pedido', width: 290),
        ]),
        const SizedBox(height: 16),
        Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                  key: const ValueKey('map-search'),
                  onPressed: _searching || _simulating ? null : () => _search(),
                  icon: const Icon(Icons.search),
                  label:
                      Text(_searching ? 'Pesquisando...' : 'Aplicar filtros')),
              OutlinedButton(
                  onPressed: _searching || _simulating
                      ? null
                      : () {
                          setState(() {
                            _originState = null;
                            _destinationState = null;
                            _region = null;
                            _risk = null;
                            _originPrefix.clear();
                            _destinationPrefix.clear();
                            _id.clear();
                            _start.text = _catalog!['start_date'] as String;
                            _end.text = _catalog!['end_date'] as String;
                          });
                          _search();
                        },
                  child: const Text('Limpar filtros')),
              for (final band in ['Baixo', 'Médio', 'Alto'])
                ActionChip(
                    label: Text('Exemplos: $band'),
                    onPressed: _searching || _simulating
                        ? null
                        : () {
                            setState(() => _risk = band);
                            _search();
                          }),
            ]),
        if (_searching)
          const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator()),
      ]));

  Widget _mapView() {
    final selected = _simulation ?? _selected;
    final origin = _point(selected?['origin']);
    final destination = _point(selected?['destination']);
    final risk =
        (_simulation?['result']?['risk'] ?? _selected?['risk']) as String?;
    final markers = <Marker>[
      for (final row in _orders)
        if (_point(row['destination']) != null &&
            row['order_id'] != _selected?['order_id'])
          Marker(
              point: _point(row['destination'])!,
              width: 38,
              height: 46,
              child: Tooltip(
                  message: '${row['risk']} risco · ${row['order_id']}',
                  child: IconButton(
                      padding: EdgeInsets.zero,
                      onPressed:
                          _selecting || _simulating ? null : () => _select(row),
                      icon: Icon(Icons.location_on,
                          color: _color(row['risk'] as String), size: 32)))),
      if (origin != null)
        Marker(
            point: origin,
            width: 44,
            height: 44,
            child: const Tooltip(
                message: 'Origem do pedido selecionado',
                child:
                    Icon(Icons.warehouse, color: Color(0xFF2563EB), size: 32))),
      if (destination != null)
        Marker(
            point: destination,
            width: 44,
            height: 44,
            child: Tooltip(
                message: 'Destino · $risk risco',
                child: Icon(Icons.location_on, color: _color(risk), size: 40))),
    ];
    return _card(
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Previsões no mapa',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
      Wrap(spacing: 8, children: [
        for (final band in ['Baixo', 'Médio', 'Alto']) _badge(band)
      ]),
      const Text(
          'Toque em um destino ou selecione um pedido na lista. A linha mostra a ligação geográfica, sem representar uma rodovia.'),
      SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Mostrar ruas (requer internet)'),
          value: _streets,
          onChanged: (v) => setState(() => _streets = v)),
      SizedBox(
          height: 440,
          child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: FlutterMap(
                mapController: _map,
                options: MapOptions(
                    initialCenter: const LatLng(-15, -51),
                    initialZoom: 3.4,
                    minZoom: 2,
                    maxZoom: 14,
                    backgroundColor: const Color(0xFFE5EEF5),
                    onMapReady: () {
                      _mapReady = true;
                      _fit();
                    }),
                children: [
                  if (_streets)
                    TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'br.edu.fatec.logipredict'),
                  GeoJsonLayer.asset('assets/geojson/brazil_regions.geojson',
                      onPolygon: (points, holes, properties) => Polygon(
                          points: points,
                          holePointsList: holes,
                          color: const Color(0x302563EB),
                          borderColor: const Color(0xFF64748B),
                          borderStrokeWidth: 1.2)),
                  if (origin != null && destination != null)
                    PolylineLayer(polylines: [
                      Polyline(
                          points: [origin, destination],
                          color: _color(risk),
                          strokeWidth: 3)
                    ]),
                  MarkerLayer(markers: markers),
                  RichAttributionWidget(attributions: [
                    const TextSourceAttribution(
                        'Regiões: IBGE · Pontos aproximados: Olist'),
                    if (_streets)
                      const TextSourceAttribution(
                          '© OpenStreetMap contributors'),
                  ]),
                ],
              ))),
      const SizedBox(height: 8),
      const Text(
          'O contorno do Brasil e os pontos funcionam sem internet. CEP de 5 dígitos representa uma área aproximada.'),
    ]));
  }

  Widget _list() {
    final total = (_page?['total'] as num?)?.toInt() ?? 0;
    final counts = _page?['counts'] as Map? ?? {};
    return _card(
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$total pedidos encontrados',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      Text(
          'Nos filtros aplicados: ${counts['Baixo'] ?? 0} baixos · ${counts['Médio'] ?? 0} médios · ${counts['Alto'] ?? 0} altos'),
      if (_orders.isEmpty)
        const Padding(
            padding: EdgeInsets.all(20),
            child: Text('Nenhum pedido corresponde aos filtros.')),
      for (final row in _orders)
        ListTile(
          key: ValueKey('order-${row['order_id']}'),
          selected: row['order_id'] == _selected?['order_id'],
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: Icon(Icons.circle,
              color: _color(row['risk'] as String), size: 14),
          title: Text(row['order_id'] as String,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
              '${row['origin']?['state'] ?? '?'} → ${row['destination']?['state'] ?? '?'} · compra ${_day(row['purchase_at'])} · ${row['risk']} risco${row['already_overdue'] == true ? ' · prazo já vencido' : ''}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _simulating || _selecting ? null : () => _select(row),
        ),
      Row(children: [
        IconButton(
            tooltip: 'Página anterior',
            onPressed: _offset == 0 || _searching || _simulating
                ? null
                : () => _search(offset: _offset - 30),
            icon: const Icon(Icons.chevron_left)),
        Expanded(
            child: Text(
                total == 0
                    ? '0 resultados'
                    : '${_offset + 1}–${_offset + _orders.length} de $total',
                textAlign: TextAlign.center)),
        IconButton(
            tooltip: 'Próxima página',
            onPressed:
                _offset + _orders.length >= total || _searching || _simulating
                    ? null
                    : () => _search(offset: _offset + 30),
            icon: const Icon(Icons.chevron_right)),
      ]),
    ]));
  }

  String _day(dynamic value) {
    final s = value?.toString() ?? '';
    if (s.length < 10) return s;
    return '${s.substring(8, 10)}/${s.substring(5, 7)}/${s.substring(0, 4)}';
  }

  Future<void> _chooseSeller() async {
    final chosen = await showDialog<Map<String, dynamic>>(
        context: context, builder: (_) => _SellerDialog(api: _api));
    if (chosen != null && mounted) {
      setState(() {
        _sellerId = chosen['seller_id'] as String;
        _sellerLabel =
            '${chosen['city']} / ${chosen['state']} · CEP ${chosen['prefix5']} · $_sellerId';
      });
    }
  }

  Widget _scenario() {
    if (_selecting) {
      return _card(const Center(child: CircularProgressIndicator()));
    }
    if (_selected == null) {
      return _card(const Text(
          'Selecione um pedido para ver os detalhes e simular mudanças.'));
    }
    final single = _selected!['shipment']['sellers_count'] == 1;
    return _card(Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Simular este pedido',
              key: _scenarioAnchor,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SelectableText('Pedido: ${_selected!['order_id']}'),
          _badge(_selected!['risk'] as String),
          const Text(
              'Altere os dados e compare cenários. A simulação não altera o pedido salvo e não treina novamente o modelo.'),
          const Text(
              'Campos numéricos em branco mantêm o valor original do pedido.'),
          const SizedBox(height: 16),
          Wrap(spacing: 12, runSpacing: 14, children: [
            _dateField(_purchase, 'Data/hora da compra', time: true),
            _dateField(_dispatch, 'Data/hora do despacho',
                time: true, key: const ValueKey('scenario-dispatch')),
            _dateField(_deadline, 'Prazo prometido', time: true),
            _text(_destination, 'CEP destino (5 ou 8 dígitos)',
                width: 246,
                key: const ValueKey('scenario-destination'),
                validator: (v) =>
                    RegExp(r'^\d{5}(-?\d{3})?$').hasMatch((v ?? '').trim())
                        ? null
                        : 'Use 5 ou 8 dígitos de CEP.'),
            _text(_weight, 'Peso total (kg)', number: true),
            _text(_volume, 'Volume total (cm³)', number: true),
            _text(_price, 'Preço total (R\$)', number: true),
            _text(_freight, 'Frete (R\$)', number: true),
          ]),
          const SizedBox(height: 12),
          Text('Origem: $_sellerLabel'),
          TextButton.icon(
              onPressed: !single || _simulating ? null : _chooseSeller,
              icon: const Icon(Icons.warehouse_outlined),
              label: const Text('Escolher outro vendedor real')),
          if (!single)
            const Text(
                'A rota de pedidos com vários vendedores é mantida; selecione um pedido com um vendedor para mudar a rota.'),
          const SizedBox(height: 6),
          FilledButton.icon(
              key: const ValueKey('map-simulate'),
              onPressed: _simulating ? null : _run,
              icon: const Icon(Icons.science_outlined),
              label: Text(_simulating
                  ? 'Comparando cenários...'
                  : 'Simular e comparar cenários')),
          if (_simulating)
            const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator()),
          if (_simulation != null) ..._result(),
          ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Conferir o resultado histórico real'),
              children: [
                Text(_selected!['observed_late'] == true
                    ? 'Este pedido foi entregue com atraso na base Olist.'
                    : 'Este pedido foi entregue no prazo na base Olist.'),
                const Text(
                    'Informação posterior à entrega, usada apenas para conferência. Não entra na previsão nem nos cenários.'),
              ]),
        ])));
  }

  List<Widget> _result() {
    final data = _simulation!;
    final r = data['result'] as Map<String, dynamic>;
    final calendar = data['calendar'] as Map<String, dynamic>;
    final holidays = calendar['fixed_national_holidays'] as List;
    return [
      const Divider(height: 32),
      Text('Resultado do cenário informado',
          key: _resultAnchor,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
      _badge(r['risk'] as String),
      Text(r['predicted_late'] == true
          ? 'O modelo final manteve o alerta de atraso.'
          : 'O modelo final não manteve alerta. Ainda pode ocorrer atraso.'),
      Text(
          'Prazo disponível: ${r['remaining_days']} dias corridos · distância: ${(data['shipment']['distance_km'] as num?)?.toStringAsFixed(1) ?? 'não disponível'} km em linha reta.'),
      if (r['already_overdue'] == true)
        const Text('O prazo já estava vencido no despacho.',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: Color(0xFFDC2626))),
      const SizedBox(height: 12),
      for (final text in data['suggestions'] as List)
        Padding(
            padding: const EdgeInsets.only(bottom: 8), child: Text('• $text')),
      const Text('Calendário', style: TextStyle(fontWeight: FontWeight.bold)),
      Text(calendar['dispatch_holiday'] != null
          ? 'Despacho em ${calendar['dispatch_holiday']}.'
          : calendar['dispatch_weekend'] == true
              ? 'Despacho no fim de semana.'
              : 'Despacho fora dos feriados fixos nacionais cadastrados.'),
      Text(holidays.isEmpty
          ? 'Nenhum feriado fixo nacional entre o despacho e o prazo.'
          : holidays
              .map((h) => '${_day(h['date'])}: ${h['name']}')
              .join(' · ')),
      Text(calendar['coverage'] as String),
      const Text(
          'Feriados são contexto do calendário; não são um atributo explícito deste modelo.'),
      const SizedBox(height: 16),
      const Text('Alternativas comparadas',
          style: TextStyle(fontWeight: FontWeight.bold)),
      for (final a
          in (data['alternatives'] as List).cast<Map<String, dynamic>>())
        Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    border: Border.all(
                        color:
                            _color(a['risk'] as String).withValues(alpha: .45)),
                    borderRadius: BorderRadius.circular(10)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a['label'] as String,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                          '${a['risk']} risco · despacho ${_day(a['dispatched_at'])} · prazo ${_day(a['estimated_delivery_at'])}'),
                      Text(a['lower_risk'] == true
                          ? 'Faixa de risco menor nesta simulação.'
                          : 'Sem redução da faixa de risco.'),
                    ]))),
      const SizedBox(height: 8),
      Text(data['comparison_policy'] as String),
      ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Como o modelo tomou esta decisão'),
          children: [
            SelectableText('Modelo: ${data['model_version']}\n'
                'Random Forest: ${(r['base_score'] as num).toStringAsFixed(4)} · corte ${(r['base_threshold'] as num).toStringAsFixed(4)}\n'
                'Score final: ${(r['score'] as num).toStringAsFixed(5)} · corte ${(r['threshold'] as num).toStringAsFixed(5)}\n'
                'Entregas anteriores do vendedor: ${r['history']['seller_orders']}\n'
                'Entregas anteriores na rota entre UFs: ${r['history']['route_orders']}\n'
                'Histórico disponível até: ${r['history']['history_asof']}'),
            const Text(
                'Scores não são porcentagens de chance. Baixo: sem alerta inicial. Médio: alerta inicial retirado pelo filtro. Alto: alerta mantido.'),
          ]),
      for (final warning in data['warnings'] as List)
        Padding(
            padding: const EdgeInsets.only(top: 6),
            child:
                Text('Aviso: $warning', style: const TextStyle(fontSize: 12))),
    ];
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_catalog == null) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_error ?? 'Mapa indisponível',
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                    onPressed: _load,
                    child: const Text('Tentar carregar novamente')),
              ])));
    }
    final metrics = _catalog!['metrics'] as Map;
    final tp = (metrics['TP'] as num).toInt();
    final missed = (metrics['FN'] as num).toInt();
    final recall =
        (100 * tp / (tp + missed)).toStringAsFixed(1).replaceAll('.', ',');
    return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _filters(),
          if (_error != null)
            _card(Text(_error!,
                key: const ValueKey('map-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error))),
          _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(
                'Modelo 564 + filtro · Olist real · pesquisa retrospectiva',
                style: TextStyle(fontWeight: FontWeight.bold)),
            Text(
                'No teste histórico: $tp de ${tp + missed} atrasos encontrados ($recall%) e ${metrics['FP']} falsos alertas. Entre os $tp, ${metrics['known_overdue_TP']} já estavam vencidos no despacho.'),
            ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Entender as faixas e os limites'),
                children: [
                  for (final entry
                      in (_catalog!['risk_definitions'] as Map).entries)
                    Text('${entry.key}: ${entry.value}'),
                  for (final limitation in _catalog!['limitations'] as List)
                    Text('• $limitation'),
                ]),
          ])),
          LayoutBuilder(
              builder: (context, constraints) => constraints.maxWidth >= 1050
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          Expanded(
                              flex: 6,
                              child: Column(children: [_mapView(), _list()])),
                          const SizedBox(width: 16),
                          Expanded(flex: 5, child: _scenario()),
                        ])
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [_mapView(), _scenario(), _list()])),
        ]));
  }
}

/// A origem sempre identifica um vendedor existente; nunca cria um seller_id.
class _SellerDialog extends StatefulWidget {
  const _SellerDialog({required this.api});
  final MapScenariosApi api;
  @override
  State<_SellerDialog> createState() => _SellerDialogState();
}

class _SellerDialogState extends State<_SellerDialog> {
  final _query = TextEditingController();
  List<Map<String, dynamic>> _sellers = [];
  bool _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.api.get('sellers', {'q': _query.text.trim()});
      if (mounted) {
        setState(() =>
            _sellers = (result['data'] as List).cast<Map<String, dynamic>>());
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Vendedores reais da Olist'),
        content: SizedBox(
            width: 560,
            height: 420,
            child: Column(children: [
              TextField(
                  controller: _query,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                      labelText: 'Cidade, UF, prefixo ou ID',
                      suffixIcon: IconButton(
                          onPressed: _busy ? null : _search,
                          icon: const Icon(Icons.search)))),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null) Text(_error!),
              Expanded(
                  child: ListView(children: [
                if (!_busy && _sellers.isEmpty)
                  const ListTile(title: Text('Nenhum vendedor encontrado.')),
                for (final s in _sellers)
                  ListTile(
                      title: Text(
                          '${s['city']} / ${s['state']} · ${s['prefix5']}'),
                      subtitle: Text(s['seller_id'] as String),
                      onTap: () => Navigator.of(context).pop(s)),
              ])),
            ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'))
        ],
      );
}
