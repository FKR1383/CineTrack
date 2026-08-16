class AppConfig {
  const AppConfig._();

  static const tmdbBaseUrl = 'https://api.themoviedb.org/3';
  static const tmdbImageBaseUrl = 'https://image.tmdb.org/t/p';
  static const tmdbReadAccessToken = String.fromEnvironment('TMDB_READ_ACCESS_TOKEN');
  static const tmdbLanguage = String.fromEnvironment('TMDB_LANGUAGE', defaultValue: 'en-US');
  static const tmdbRegion = String.fromEnvironment('TMDB_REGION', defaultValue: 'US');

  static const requestTimeoutSeconds = 20;
  static const pageSize = 20;
  static const apiCacheMinutes = 30;
  static const detailsCacheHours = 24;

  static void validateForStartup() {
    if (tmdbReadAccessToken.trim().isEmpty) {
      throw StateError(
        'TMDB_READ_ACCESS_TOKEN is required. Run/build with '
        '--dart-define=TMDB_READ_ACCESS_TOKEN=<your token>.',
      );
    }
  }
}
