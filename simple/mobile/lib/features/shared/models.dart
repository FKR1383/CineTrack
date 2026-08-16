import 'dart:convert';

int _int(dynamic value, [int fallback = 0]) =>
    value is int ? value : int.tryParse(value?.toString() ?? '') ?? fallback;
double? _doubleOrNull(dynamic value) =>
    value == null ? null : (value is num ? value.toDouble() : double.tryParse(value.toString()));
DateTime? _dateTime(dynamic value) =>
    value == null ? null : DateTime.tryParse(value.toString());
List<String> _strings(dynamic value) =>
    value is List ? value.map((item) => item.toString()).toList() : <String>[];
Map<String, dynamic> _map(dynamic value) =>
    value is Map<String, dynamic> ? value : <String, dynamic>{};

class UserModel {
  const UserModel({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.username,
    required this.email,
    required this.role,
    required this.isActive,
    this.avatarUrl,
    this.bio,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String username;
  final String email;
  final String? avatarUrl;
  final String? bio;
  final String role;
  final bool isActive;

  String get fullName => '$firstName $lastName'.trim();
  bool get isAdmin => role == 'admin';

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'].toString(),
        firstName: json['first_name']?.toString() ?? '',
        lastName: json['last_name']?.toString() ?? '',
        username: json['username']?.toString() ?? '',
        email: json['email']?.toString() ?? '',
        avatarUrl: json['avatar_url']?.toString(),
        bio: json['bio']?.toString(),
        role: json['role']?.toString() ?? 'user',
        isActive: json['is_active'] == true,
      );
}

class AuthResult {
  const AuthResult({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final UserModel user;

  factory AuthResult.fromJson(Map<String, dynamic> json) => AuthResult(
        accessToken: json['access_token'].toString(),
        refreshToken: json['refresh_token'].toString(),
        user: UserModel.fromJson(_map(json['user'])),
      );
}

class MediaSummary {
  const MediaSummary({
    required this.mediaId,
    required this.mediaType,
    required this.title,
    required this.genres,
    required this.ratingCount,
    this.originalTitle,
    this.posterUrl,
    this.plot,
    this.releaseYear,
    this.endYear,
    this.providerRating,
    this.appRating,
    this.releaseStatus,
    this.seasonCount,
    this.episodeCount,
  });

  final String mediaId;
  final String mediaType;
  final String title;
  final String? originalTitle;
  final String? posterUrl;
  final String? plot;
  final List<String> genres;
  final int? releaseYear;
  final int? endYear;
  final double? providerRating;
  final double? appRating;
  final int ratingCount;
  final String? releaseStatus;
  final int? seasonCount;
  final int? episodeCount;

  bool get isSeries => mediaType == 'series';

  factory MediaSummary.fromJson(Map<String, dynamic> json) => MediaSummary(
        mediaId: json['media_id']?.toString() ?? '',
        mediaType: json['media_type']?.toString() ?? 'movie',
        title: json['title']?.toString() ?? '',
        originalTitle: json['original_title']?.toString(),
        posterUrl: json['poster_url']?.toString(),
        plot: json['plot']?.toString(),
        genres: _strings(json['genres']),
        releaseYear: json['release_year'] == null ? null : _int(json['release_year']),
        endYear: json['end_year'] == null ? null : _int(json['end_year']),
        providerRating: _doubleOrNull(json['provider_rating']),
        appRating: _doubleOrNull(json['app_rating']),
        ratingCount: _int(json['rating_count']),
        releaseStatus: json['release_status']?.toString(),
        seasonCount: json['season_count'] == null ? null : _int(json['season_count']),
        episodeCount: json['episode_count'] == null ? null : _int(json['episode_count']),
      );
}

class RatingDistribution {
  const RatingDistribution({required this.total, required this.percentages, required this.counts});

  final int total;
  final Map<int, double> percentages;
  final Map<int, int> counts;

  factory RatingDistribution.fromJson(Map<String, dynamic> json) {
    final percentagesRaw = _map(json['percentages']);
    final countsRaw = _map(json['counts']);
    return RatingDistribution(
      total: _int(json['total']),
      percentages: {
        for (var star = 1; star <= 5; star++)
          star: _doubleOrNull(percentagesRaw['$star']) ?? 0,
      },
      counts: {
        for (var star = 1; star <= 5; star++)
          star: _int(countsRaw['$star']),
      },
    );
  }
}

class UserMediaState {
  const UserMediaState({
    this.watchStatus,
    required this.isFavorite,
    this.userRating,
    required this.watchedEpisodes,
    required this.remainingEpisodes,
    required this.progressPercent,
    required this.progressColor,
    required this.progressHex,
  });

  final String? watchStatus;
  final bool isFavorite;
  final int? userRating;
  final int watchedEpisodes;
  final int remainingEpisodes;
  final double progressPercent;
  final String progressColor;
  final String progressHex;

  factory UserMediaState.fromJson(Map<String, dynamic> json) => UserMediaState(
        watchStatus: json['watch_status']?.toString(),
        isFavorite: json['is_favorite'] == true,
        userRating: json['user_rating'] == null ? null : _int(json['user_rating']),
        watchedEpisodes: _int(json['watched_episodes']),
        remainingEpisodes: _int(json['remaining_episodes']),
        progressPercent: _doubleOrNull(json['progress_percent']) ?? 0,
        progressColor: json['progress_color']?.toString() ?? 'black',
        progressHex: json['progress_hex']?.toString() ?? '#212121',
      );
}

class MediaDetail extends MediaSummary {
  MediaDetail({
    required super.mediaId,
    required super.mediaType,
    required super.title,
    required super.genres,
    required super.ratingCount,
    required this.countries,
    required this.directors,
    required this.cast,
    required this.ratingDistribution,
    super.originalTitle,
    super.posterUrl,
    super.plot,
    super.releaseYear,
    super.endYear,
    super.providerRating,
    super.appRating,
    super.releaseStatus,
    super.seasonCount,
    super.episodeCount,
    this.releaseDate,
    this.runtimeMinutes,
    this.providerVoteCount,
    this.userState,
  });

  final DateTime? releaseDate;
  final int? runtimeMinutes;
  final List<String> countries;
  final List<String> directors;
  final List<String> cast;
  final int? providerVoteCount;
  final RatingDistribution ratingDistribution;
  final UserMediaState? userState;

  factory MediaDetail.fromJson(Map<String, dynamic> json) {
    final summary = MediaSummary.fromJson(json);
    return MediaDetail(
      mediaId: summary.mediaId,
      mediaType: summary.mediaType,
      title: summary.title,
      originalTitle: summary.originalTitle,
      posterUrl: summary.posterUrl,
      plot: summary.plot,
      genres: summary.genres,
      releaseYear: summary.releaseYear,
      endYear: summary.endYear,
      providerRating: summary.providerRating,
      appRating: summary.appRating,
      ratingCount: summary.ratingCount,
      releaseStatus: summary.releaseStatus,
      seasonCount: summary.seasonCount,
      episodeCount: summary.episodeCount,
      releaseDate: _dateTime(json['release_date']),
      runtimeMinutes: json['runtime_minutes'] == null ? null : _int(json['runtime_minutes']),
      countries: _strings(json['countries']),
      directors: _strings(json['directors']),
      cast: _strings(json['cast']),
      providerVoteCount: json['provider_vote_count'] == null ? null : _int(json['provider_vote_count']),
      ratingDistribution: RatingDistribution.fromJson(_map(json['rating_distribution'])),
      userState: json['user_state'] is Map<String, dynamic>
          ? UserMediaState.fromJson(_map(json['user_state']))
          : null,
    );
  }
}

class EpisodeModel {
  const EpisodeModel({
    required this.episodeId,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.title,
    required this.watched,
    this.releaseDate,
    this.runtimeMinutes,
    this.plot,
  });

  final String episodeId;
  final int seasonNumber;
  final int episodeNumber;
  final String title;
  final DateTime? releaseDate;
  final int? runtimeMinutes;
  final String? plot;
  final bool watched;

  factory EpisodeModel.fromJson(Map<String, dynamic> json) => EpisodeModel(
        episodeId: json['episode_id']?.toString() ?? '',
        seasonNumber: _int(json['season_number']),
        episodeNumber: _int(json['episode_number']),
        title: json['title']?.toString() ?? '',
        releaseDate: _dateTime(json['release_date']),
        runtimeMinutes: json['runtime_minutes'] == null ? null : _int(json['runtime_minutes']),
        plot: json['plot']?.toString(),
        watched: json['watched'] == true,
      );
}

class SeasonModel {
  const SeasonModel({
    required this.seasonNumber,
    required this.episodeCount,
    required this.episodes,
    this.title,
  });

  final int seasonNumber;
  final String? title;
  final int episodeCount;
  final List<EpisodeModel> episodes;

  factory SeasonModel.fromJson(Map<String, dynamic> json) => SeasonModel(
        seasonNumber: _int(json['season_number']),
        title: json['title']?.toString(),
        episodeCount: _int(json['episode_count']),
        episodes: (json['episodes'] as List<dynamic>? ?? const [])
            .map((item) => EpisodeModel.fromJson(_map(item)))
            .toList(),
      );
}

class CommentModel {
  const CommentModel({
    required this.id,
    required this.text,
    required this.username,
    required this.createdAt,
    required this.updatedAt,
    required this.isSpoiler,
    required this.isHidden,
    required this.ownComment,
    this.userAvatarUrl,
  });

  final String id;
  final String text;
  final String username;
  final String? userAvatarUrl;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isSpoiler;
  final bool isHidden;
  final bool ownComment;

  factory CommentModel.fromJson(Map<String, dynamic> json) => CommentModel(
        id: json['id'].toString(),
        text: json['text']?.toString() ?? '',
        username: json['username']?.toString() ?? '',
        userAvatarUrl: json['user_avatar_url']?.toString(),
        createdAt: _dateTime(json['created_at']) ?? DateTime.now(),
        updatedAt: _dateTime(json['updated_at']) ?? DateTime.now(),
        isSpoiler: json['is_spoiler'] == true,
        isHidden: json['is_hidden'] == true,
        ownComment: json['own_comment'] == true,
      );
}

class ProgressModel {
  const ProgressModel({
    required this.mediaId,
    required this.watchedEpisodes,
    required this.totalEpisodes,
    required this.remainingEpisodes,
    required this.progressPercent,
    required this.progressColor,
    required this.progressHex,
    this.releaseStatus,
  });

  final String mediaId;
  final int watchedEpisodes;
  final int totalEpisodes;
  final int remainingEpisodes;
  final double progressPercent;
  final String progressColor;
  final String progressHex;
  final String? releaseStatus;

  factory ProgressModel.fromJson(Map<String, dynamic> json) => ProgressModel(
        mediaId: json['media_id']?.toString() ?? '',
        watchedEpisodes: _int(json['watched_episodes']),
        totalEpisodes: _int(json['total_episodes']),
        remainingEpisodes: _int(json['remaining_episodes']),
        progressPercent: _doubleOrNull(json['progress_percent']) ?? 0,
        progressColor: json['progress_color']?.toString() ?? 'black',
        progressHex: json['progress_hex']?.toString() ?? '#212121',
        releaseStatus: json['release_status']?.toString(),
      );
}

class LibraryEntry {
  const LibraryEntry({
    required this.media,
    required this.isFavorite,
    required this.updatedAt,
    this.watchStatus,
    this.progress,
  });

  final MediaSummary media;
  final String? watchStatus;
  final bool isFavorite;
  final ProgressModel? progress;
  final DateTime updatedAt;

  factory LibraryEntry.fromJson(Map<String, dynamic> json) => LibraryEntry(
        media: MediaSummary.fromJson(_map(json['media'])),
        watchStatus: json['watch_status']?.toString(),
        isFavorite: json['is_favorite'] == true,
        progress: json['progress'] is Map<String, dynamic>
            ? ProgressModel.fromJson(_map(json['progress']))
            : null,
        updatedAt: _dateTime(json['updated_at']) ?? DateTime.now(),
      );
}

class CustomListModel {
  const CustomListModel({
    required this.id,
    required this.name,
    required this.isPublic,
    required this.itemCount,
    required this.createdAt,
    required this.updatedAt,
    required this.items,
    this.description,
  });

  final String id;
  final String name;
  final String? description;
  final bool isPublic;
  final int itemCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<MediaSummary> items;

  factory CustomListModel.fromJson(Map<String, dynamic> json) => CustomListModel(
        id: json['id'].toString(),
        name: json['name']?.toString() ?? '',
        description: json['description']?.toString(),
        isPublic: json['is_public'] == true,
        itemCount: _int(json['item_count']),
        createdAt: _dateTime(json['created_at']) ?? DateTime.now(),
        updatedAt: _dateTime(json['updated_at']) ?? DateTime.now(),
        items: (json['items'] as List<dynamic>? ?? const [])
            .map((item) => MediaSummary.fromJson(_map(item)))
            .toList(),
      );
}

class UserStats {
  const UserStats({
    required this.watchedMovies,
    required this.watchedSeries,
    required this.watchedEpisodes,
    required this.approximateWatchMinutes,
    required this.approximateWatchHours,
    required this.favoritesCount,
    required this.customListsCount,
    this.favoriteGenre,
    this.averageUserRating,
  });

  final int watchedMovies;
  final int watchedSeries;
  final int watchedEpisodes;
  final int approximateWatchMinutes;
  final double approximateWatchHours;
  final String? favoriteGenre;
  final double? averageUserRating;
  final int favoritesCount;
  final int customListsCount;

  factory UserStats.fromJson(Map<String, dynamic> json) => UserStats(
        watchedMovies: _int(json['watched_movies']),
        watchedSeries: _int(json['watched_series']),
        watchedEpisodes: _int(json['watched_episodes']),
        approximateWatchMinutes: _int(json['approximate_watch_minutes']),
        approximateWatchHours: _doubleOrNull(json['approximate_watch_hours']) ?? 0,
        favoriteGenre: json['favorite_genre']?.toString(),
        averageUserRating: _doubleOrNull(json['average_user_rating']),
        favoritesCount: _int(json['favorites_count']),
        customListsCount: _int(json['custom_lists_count']),
      );
}

class ActivityItem {
  const ActivityItem({
    required this.kind,
    required this.mediaId,
    required this.mediaTitle,
    required this.mediaType,
    required this.occurredAt,
    this.detail,
  });

  final String kind;
  final String mediaId;
  final String mediaTitle;
  final String mediaType;
  final DateTime occurredAt;
  final String? detail;

  factory ActivityItem.fromJson(Map<String, dynamic> json) => ActivityItem(
        kind: json['kind']?.toString() ?? '',
        mediaId: json['media_id']?.toString() ?? '',
        mediaTitle: json['media_title']?.toString() ?? '',
        mediaType: json['media_type']?.toString() ?? '',
        occurredAt: _dateTime(json['occurred_at']) ?? DateTime.now(),
        detail: json['detail']?.toString(),
      );
}

class HomeSections {
  const HomeSections({
    required this.popularMovies,
    required this.popularSeries,
    required this.newReleases,
    required this.topRated,
    required this.recommendations,
  });

  final List<MediaSummary> popularMovies;
  final List<MediaSummary> popularSeries;
  final List<MediaSummary> newReleases;
  final List<MediaSummary> topRated;
  final List<MediaSummary> recommendations;

  factory HomeSections.fromJson(Map<String, dynamic> json) {
    List<MediaSummary> parse(String key) =>
        (json[key] as List<dynamic>? ?? const [])
            .map((item) => MediaSummary.fromJson(_map(item)))
            .toList();
    return HomeSections(
      popularMovies: parse('popular_movies'),
      popularSeries: parse('popular_series'),
      newReleases: parse('new_releases'),
      topRated: parse('top_rated'),
      recommendations: parse('recommendations'),
    );
  }
}

class PageResult<T> {
  const PageResult({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.totalPages,
    required this.hasNext,
  });

  final List<T> items;
  final int page;
  final int pageSize;
  final int total;
  final int totalPages;
  final bool hasNext;

  factory PageResult.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) parser,
  ) {
    final pagination = _map(json['pagination']);
    return PageResult<T>(
      items: (json['items'] as List<dynamic>? ?? const [])
          .map((item) => parser(_map(item)))
          .toList(),
      page: _int(pagination['page'], 1),
      pageSize: _int(pagination['page_size'], 20),
      total: _int(pagination['total']),
      totalPages: _int(pagination['total_pages']),
      hasNext: pagination['has_next'] == true,
    );
  }
}

String prettyJson(Object? value) => const JsonEncoder.withIndent('  ').convert(value);
