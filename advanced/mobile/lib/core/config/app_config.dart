class AppConfig {
  const AppConfig._();

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://31.57.118.82/api/v1',
  );

  /// SHA-256 of the server leaf certificate DER bytes, with or without colons.
  /// Production builds should pass `--dart-define=CERT_SHA256=YOUR_FINGERPRINT`.
  static const certificateSha256 = String.fromEnvironment(
    'CERT_SHA256',
    defaultValue: '',
  );

  static const allowUnpinnedDevelopment = bool.fromEnvironment(
    'ALLOW_UNPINNED_DEV',
    defaultValue: false,
  );


  static void validateForStartup() {
    final uri = Uri.parse(apiBaseUrl);
    final localHost = {'localhost', '127.0.0.1', '10.0.2.2'}.contains(uri.host);
    if (uri.scheme != 'https' && !localHost && !allowUnpinnedDevelopment) {
      throw StateError('CineTrack requires HTTPS outside local development.');
    }
    if (uri.scheme == 'https' &&
        !localHost &&
        certificateSha256.trim().isEmpty &&
        !allowUnpinnedDevelopment) {
      throw StateError(
        'CERT_SHA256 is required for production certificate pinning. '
        'Build with --dart-define=CERT_SHA256=<server fingerprint>.',
      );
    }
  }

  static const requestTimeoutSeconds = 20;
  static const pageSize = 20;
}
