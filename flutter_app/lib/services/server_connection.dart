import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_configuration.dart';

class ServerConnectionStatus {
  const ServerConnectionStatus({required this.predictionReady});
  final bool predictionReady;
}

/// Verifica separadamente o servidor e a disponibilidade da previsão.
class ServerConnection {
  static Future<ServerConnectionStatus> check(String address,
      {http.Client? client}) async {
    final base = ApiConfiguration.normalize(address);
    final connection = client ?? http.Client();
    try {
      final health = await connection
          .get(Uri.parse('$base/health'))
          .timeout(const Duration(seconds: 8));
      final data = jsonDecode(health.body);
      if (health.statusCode != 200 ||
          data is! Map ||
          data['service'] != 'logipredict-api' ||
          data['status'] != 'ok') {
        throw const FormatException(
            'Este endereço não respondeu como LogiPredict.');
      }
      try {
        final ready = await connection
            .get(Uri.parse('$base/ready'))
            .timeout(const Duration(seconds: 15));
        final result = jsonDecode(ready.body);
        return ServerConnectionStatus(
            predictionReady: ready.statusCode == 200 &&
                result is Map &&
                result['status'] == 'ok');
      } catch (_) {
        return const ServerConnectionStatus(predictionReady: false);
      }
    } finally {
      if (client == null) connection.close();
    }
  }
}
