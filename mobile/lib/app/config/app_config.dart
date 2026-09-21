import 'dart:convert';

class AppConfig {
  AppConfig({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    bool allowLocalHttp = false,
  }) {
    final uri = Uri.tryParse(supabaseUrl);
    final local =
        uri != null &&
        const ['127.0.0.1', 'localhost', '10.0.2.2', '::1'].contains(uri.host);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.scheme != 'https' &&
            !(allowLocalHttp && local && uri.scheme == 'http'))) {
      throw const FormatException(
        'SUPABASE_URL ausente o no válida; usa HTTPS o HTTP local en debug.',
      );
    }
    if (!_isPublicKey(supabasePublishableKey)) {
      throw const FormatException(
        'SUPABASE_PUBLISHABLE_KEY ausente o no válida; usa una clave pública publishable/anon.',
      );
    }
  }

  factory AppConfig.fromEnvironment({bool allowLocalHttp = false}) => AppConfig(
    supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
    supabasePublishableKey: const String.fromEnvironment(
      'SUPABASE_PUBLISHABLE_KEY',
    ),
    allowLocalHttp: allowLocalHttp,
  );

  final String supabaseUrl;
  final String supabasePublishableKey;

  static bool _isPublicKey(String key) {
    if (RegExp(r'^sb_publishable_[A-Za-z0-9_-]+$').hasMatch(key)) return true;
    // Legacy anon JWTs are supported; reject service keys before SDK creation.
    // This checks configuration, not token authenticity (the server does that).
    try {
      final parts = key.split('.');
      if (parts.length != 3) return false;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      return payload is Map<String, dynamic> && payload['role'] == 'anon';
    } catch (_) {
      return false;
    }
  }
}
