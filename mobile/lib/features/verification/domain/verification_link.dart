import 'verification_repository.dart';

/// Web base from trusted configuration, independent of the backend origin.
class VerificationLink {
  VerificationLink(String base, {bool allowLocalHttp = false}) {
    final uri = Uri.tryParse(base);
    final loopback =
        uri != null &&
        const ['localhost', '127.0.0.1', '::1'].contains(uri.host);
    if (uri == null ||
        base.isEmpty ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        RegExp(r'(^|/)(\.|\.\.)(/|$)').hasMatch(base) ||
        (uri.scheme != 'https' &&
            !(allowLocalHttp && loopback && uri.scheme == 'http')) ||
        uri.pathSegments.any((part) => part == '..' || part == '.') ||
        base.length > 1024) {
      throw const FormatException('Invalid public Web base');
    }
    _base = uri.replace(
      path: uri.path.endsWith('/') ? uri.path : '${uri.path}/',
    );
  }
  late final Uri _base;
  String forCode(String input) {
    final code = normalizeCredentialCode(input);
    if (code == null) {
      throw const VerificationException(VerificationFailure.invalidInput);
    }
    return _base.replace(fragment: '/verify/$code').toString();
  }

  /// Only the canonical link emitted by 8B or a strict direct UUID.
  String? codeFromQr(String raw) {
    if (raw.isEmpty ||
        raw.length > 2048 ||
        raw != raw.trim() ||
        RegExp(r'[\x00-\x20\x7f\\]').hasMatch(raw)) {
      return null;
    }
    if (raw.length == 36) return normalizeCredentialCode(raw);
    final prefix = '${_base.toString()}#/verify/';
    if (!raw.startsWith(prefix)) return null;
    final code = raw.substring(prefix.length);
    return code.length == 36 ? normalizeCredentialCode(code) : null;
  }

  static VerificationLink? tryCreate(
    String base, {
    bool allowLocalHttp = false,
  }) {
    try {
      return VerificationLink(base, allowLocalHttp: allowLocalHttp);
    } on FormatException {
      return null;
    }
  }
}
