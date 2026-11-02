/// Widget para selecionar o hub responsável por um pedido.
library;

import 'package:flutter/material.dart';

import '../services/hubs_api.dart';

/// Dropdown para associar um pedido a um hub logístico.
///
/// Permite selecionar "Sem associação" ou um dos hubs disponíveis.
/// Se o hub selecionado não está mais na lista, exibe o fallback label.
class OrderHubSelector extends StatelessWidget {
  const OrderHubSelector({
    super.key,
    required this.selectedHubId,
    this.selectedHubFallbackLabel,
    required this.hubs,
    required this.onChanged,
  });

  final String? selectedHubId;
  final String? selectedHubFallbackLabel;
  final List<LogisticHub> hubs;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String?>(
        value: selectedHubId,
        decoration: const InputDecoration(
          labelText: 'Hub responsável',
          isDense: true,
        ),
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('Sem associação'),
          ),
          if (selectedHubId != null &&
              !hubs.any((hub) => hub.id == selectedHubId))
            DropdownMenuItem<String?>(
              value: selectedHubId,
              child: Text(selectedHubFallbackLabel ?? selectedHubId!),
            ),
          ...hubs.map((hub) => DropdownMenuItem<String?>(
                value: hub.id,
                child: Text(
                  '${hub.name} · ${hub.code}',
                  overflow: TextOverflow.ellipsis,
                ),
              )),
        ],
        onChanged: onChanged,
      );
}
