/// Previsão de risco de atraso em lote com progresso em tempo real.
///
/// Usa Server-Sent Events (SSE) para receber atualizações de progresso
/// enquanto o backend processa múltiplos pedidos simultaneamente.
///
/// [BatchProgressEvent] é emitido a cada lote concluído.
/// [BatchCompleteEvent] é emitido quando todos os pedidos são processados.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'logipredict_api.dart';

/// Evento de progresso emitido durante a previsão em lote.
class BatchProgressEvent {
  const BatchProgressEvent({
    required this.completed,
    required this.total,
    required this.elapsedMs,
  });

  final int completed;
  final int total;
  final int elapsedMs;

  double get progress => total == 0 ? 0.0 : completed / total;
}

/// Evento de conclusão emitido quando o lote é totalmente processado.
class BatchCompleteEvent {
  const BatchCompleteEvent({
    required this.results,
    required this.total,
    required this.succeeded,
    required this.failed,
    required this.elapsedMs,
    this.skipped = 0,
  });

  final List<Map<String, dynamic>> results;
  final int total;
  final int succeeded;
  final int failed;
  final int skipped;
  final int elapsedMs;
}

/// Cliente para previsão em lote com streaming SSE.
///
/// Envia múltiplos pedidos ao endpoint /api/v1/predictions/batch
/// e recebe progresso em tempo real via Server-Sent Events.
class BatchPredictionApi {
  BatchPredictionApi({String? baseUrl})
      : _baseUrl = (baseUrl ?? LogiPredictApi.baseUrl).replaceFirst(
          RegExp(r'/$'),
          '',
        );

  final String _baseUrl;

  /// Sends [shipments] with optional [orderIds] to the batch endpoint.
  ///
  /// [onProgress] is called after each batch chunk completes on the server.
  /// [onComplete] receives the final results.
  /// Returns a [Future] that completes when the stream is closed.
  Future<void> predictBatch({
    required List<Map<String, dynamic>> shipments,
    List<String>? orderIds,
    void Function(BatchProgressEvent)? onProgress,
    void Function(BatchCompleteEvent)? onComplete,
    void Function(Object error)? onError,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/v1/predictions/batch');
    final body = jsonEncode({
      'shipments': shipments,
      if (orderIds != null) 'orderIds': orderIds,
    });

    final request = http.Request('POST', uri);
    request.headers.addAll({
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
    });
    request.body = body;

    try {
      final response = await request.send();

      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        onError?.call(Exception(
            'Erro na previsão em lote: HTTP ${response.statusCode} - $errorBody'));
        return;
      }

      final stream = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in stream) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed == 'data: ') continue;

        final jsonStr = trimmed.startsWith('data: ')
            ? trimmed.substring(6)
            : trimmed;

        try {
          final data = jsonDecode(jsonStr) as Map<String, dynamic>;
          final type = data['type'] as String?;

          if (type == 'progress') {
            onProgress?.call(BatchProgressEvent(
              completed: data['completed'] as int,
              total: data['total'] as int,
              elapsedMs: data['elapsed_ms'] as int,
            ));
          } else if (type == 'complete') {
            onComplete?.call(BatchCompleteEvent(
              results: List<Map<String, dynamic>>.from(data['results'] ?? []),
              total: data['total'] as int,
              succeeded: data['succeeded'] as int,
              failed: data['failed'] as int,
              skipped: (data['skipped'] as int?) ?? 0,
              elapsedMs: data['elapsed_ms'] as int,
            ));
          }
        } on FormatException catch (e) {
          onError?.call(Exception('Evento SSE inválido: $e'));
        }
      }
    } on SocketException catch (e) {
      onError?.call(Exception('Conexão perdida: $e'));
    } catch (e) {
      onError?.call(Exception('Falha na previsão em lote: $e'));
    }
  }
}
