import 'package:flutter/material.dart';
import '../services/api_configuration.dart';
import '../services/server_connection.dart';

class ServerConnectionDialog extends StatefulWidget {
  const ServerConnectionDialog({super.key});
  @override
  State<ServerConnectionDialog> createState() => _ServerConnectionDialogState();
}

class _ServerConnectionDialogState extends State<ServerConnectionDialog> {
  final _form = GlobalKey<FormState>();
  final _address = TextEditingController(text: ApiConfiguration.baseUrl);
  bool _busy = false;
  String? _message;
  Color? _messageColor;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await ServerConnection.check(_address.text);
      if (!mounted) return;
      setState(() {
        _message = result.predictionReady
            ? 'Conexão disponível. O serviço de previsão está pronto.'
            : 'Servidor encontrado. O serviço de previsão ainda está indisponível.';
        _messageColor = result.predictionReady ? Colors.green : Colors.orange;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message =
            'Não foi possível conectar. Confira o endereço e se o servidor está ligado.';
        _messageColor = Colors.red;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ApiConfiguration.save(_address.text);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = 'Não foi possível salvar o endereço neste aparelho.';
          _messageColor = Colors.red;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Conexão com o servidor'),
        content: SizedBox(
          width: 430,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text(
                    'O serviço de previsão precisa estar ligado no computador ou servidor.'),
                const SizedBox(height: 8),
                const Text(
                    'Salvar recarrega as telas para o servidor escolhido.',
                    style: TextStyle(fontSize: 12)),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _address,
                  enabled: !_busy,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                      labelText: 'Endereço do servidor',
                      hintText: 'http://192.168.0.10:3001'),
                  validator: (value) {
                    try {
                      ApiConfiguration.normalize(value ?? '');
                      return null;
                    } on FormatException catch (error) {
                      return error.message;
                    }
                  },
                  onChanged: (_) => setState(() => _message = null),
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  ActionChip(
                    label: const Text('Conexão USB'),
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _address.text = ApiConfiguration.defaultUrl;
                              _message = null;
                            }),
                  ),
                  ActionChip(
                    label: const Text('Conexão Wi-Fi'),
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _address.clear();
                              _message = null;
                            }),
                  ),
                ]),
                const SizedBox(height: 12),
                const Text(
                    'No Wi-Fi, informe o IP do computador na mesma rede. Por USB, use a conexão encaminhada pelo computador.',
                    style: TextStyle(fontSize: 12)),
                if (_busy)
                  const Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator()),
                if (_message != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_message!,
                          style: TextStyle(color: _messageColor))),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: const Text('Cancelar')),
          OutlinedButton(
              onPressed: _busy ? null : _check,
              child: const Text('Testar conexão')),
          FilledButton(
              onPressed: _busy ? null : _save, child: const Text('Salvar')),
        ],
      );
}
