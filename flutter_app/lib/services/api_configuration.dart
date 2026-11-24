import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Endereço compilado no Web e configuração persistida no Android.
class ApiConfiguration {
  static const defaultUrl = 'http://127.0.0.1:3001';
  static const _compiled = String.fromEnvironment('API_BASE_URL');
  static const _legacy = String.fromEnvironment('LOGIPREDICT_API_URL');
  static const _preferenceKey = 'logipredict.server_url';
  static SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  static String? _savedUrl;

  static bool get canConfigure =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static String get baseUrl =>
      _savedUrl ?? (_compiled.isEmpty ? defaultUrl : _compiled);

  static String legacyBaseUrl({String fallback = defaultUrl}) =>
      _savedUrl ??
      (_legacy.isNotEmpty
          ? _legacy
          : _compiled.isNotEmpty
              ? _compiled
              : fallback);

  static Future<void> initialize({SharedPreferencesAsync? storage}) async {
    _savedUrl = null;
    if (!canConfigure) return;
    try {
      _preferences = storage ?? SharedPreferencesAsync();
      final saved = await _preferences.getString(_preferenceKey);
      if (saved != null) _savedUrl = normalize(saved);
    } catch (error) {
      debugPrint('Configuração de conexão indisponível: $error');
    }
  }

  static String normalize(String value) {
    final text = value.trim();
    if (text.isEmpty) throw const FormatException('Informe o servidor.');
    if (RegExp(r'\s').hasMatch(text)) {
      throw const FormatException('O endereço não pode conter espaços.');
    }
    final input = text.contains('://') ? text : 'http://$text';
    final uri = Uri.tryParse(input);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.host.contains(RegExp(r'\s')) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException(
          'Use um endereço como http://192.168.0.10:3001 ou https://servidor.');
    }
    try {
      if (uri.port < 1 || uri.port > 65535) throw const FormatException();
    } on FormatException {
      throw const FormatException('A porta deve estar entre 1 e 65535.');
    }
    return uri.toString().replaceFirst(RegExp(r'/+$'), '');
  }

  static Future<void> save(String value) async {
    if (!canConfigure) {
      throw UnsupportedError(
          'O servidor desta plataforma é definido no build.');
    }
    final normalized = normalize(value);
    await _preferences.setString(_preferenceKey, normalized);
    _savedUrl = normalized;
  }
}
