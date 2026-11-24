/// Preserva o formulário, mas monta somente o mapa que está visível.
library;

import 'package:flutter/material.dart';
import '../services/map_scenarios_api.dart';
import 'prediction_map_screen.dart';

class MapWorkspaceScreen extends StatefulWidget {
  const MapWorkspaceScreen(
      {super.key,
      required this.active,
      required this.historyBuilder,
      this.api});
  final bool active;
  final Widget Function(bool active) historyBuilder;
  final MapScenariosApi? api;
  @override
  State<MapWorkspaceScreen> createState() => _MapWorkspaceScreenState();
}

class _MapWorkspaceScreenState extends State<MapWorkspaceScreen> {
  int _view = 0;
  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: LayoutBuilder(
                builder: (context, constraints) => Align(
                    alignment: Alignment.centerLeft,
                    child: SegmentedButton<int>(
                      segments: [
                        ButtonSegment(
                            value: 0,
                            label: Text(constraints.maxWidth < 500
                                ? 'Simular'
                                : 'Simular nova entrega'),
                            tooltip: 'Simular nova entrega',
                            icon: const Icon(Icons.route_outlined)),
                        ButtonSegment(
                            value: 1,
                            label: Text(constraints.maxWidth < 500
                                ? 'Histórico'
                                : 'Histórico por região'),
                            tooltip: 'Histórico por região',
                            icon: const Icon(Icons.public))
                      ],
                      selected: {_view},
                      onSelectionChanged: (values) =>
                          setState(() => _view = values.single),
                      showSelectedIcon: false,
                    )))),
        const Divider(height: 1),
        Expanded(
            child: IndexedStack(index: _view, children: [
          PredictionMapScreen(
              api: widget.api, active: widget.active && _view == 0),
          widget.historyBuilder(widget.active && _view == 1),
        ])),
      ]);
}
