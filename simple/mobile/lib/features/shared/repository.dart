import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/tmdb_client.dart';
import '../../core/config/app_config.dart';
import '../../core/errors/api_exception.dart';
import '../../core/security/password_hasher.dart';
import '../../core/storage/local_database.dart';
import 'models.dart';

class CineTrackRepository {
  CineTrackRepository(this.localDatabase, this.tmdb);

  final LocalDatabase localDatabase;
  final TmdbClient tmdb;
  final Uuid _uuid = const Uuid();
  String? _currentUserId;

  void setCurrentUser(String? userId) => _currentUserId = userId;
  String get _userId => _currentUserId ?? (throw const ApiException(message: 'برای انجام این عملیات وارد حساب شوید.'));

  static String absoluteUrl(String? value) => value ?? '';

  Future<UserModel> login({
    required String email,
    required String password,
    required bool rememberMe,
  }) async {
    final db = await localDatabase.database;
    final rows = await db.query(
      'users',
      where: 'email = ? COLLATE NOCASE',
      whereArgs: [email.trim()],
      limit: 1,
    );
    if (rows.isEmpty) throw const ApiException(message: 'ایمیل یا رمز عبور نادرست است.');
    final row = rows.first;
    if (!PasswordHasher.verify(password, row['password_salt'].toString(), row['password_hash'].toString())) {
      throw const ApiException(message: 'ایمیل یا رمز عبور نادرست است.');
    }
    final user = _userFromRow(row);
    setCurrentUser(user.id);
    return user;
  }

  Future<UserModel> register({
    required String firstName,
    required String lastName,
    required String username,
    required String email,
    required String password,
    String? bio,
    String? profileImagePath,
  }) async {
    final normalizedUsername = username.trim();
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedUsername.length < 3) throw const ApiException(message: 'نام کاربری باید حداقل ۳ کاراکتر باشد.');
    if (!RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(normalizedUsername)) {
      throw const ApiException(message: 'نام کاربری فقط می‌تواند شامل حروف انگلیسی، عدد، نقطه، خط تیره و زیرخط باشد.');
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalizedEmail)) {
      throw const ApiException(message: 'ایمیل معتبر وارد کنید.');
    }
    final digest = PasswordHasher.hash(password);
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    final avatar = profileImagePath == null ? null : await _persistAvatar(id, profileImagePath);
    final db = await localDatabase.database;
    try {
      await db.insert('users', {
        'id': id,
        'first_name': firstName.trim(),
        'last_name': lastName.trim(),
        'username': normalizedUsername,
        'email': normalizedEmail,
        'password_hash': digest.hash,
        'password_salt': digest.salt,
        'avatar_path': avatar,
        'bio': bio?.trim(),
        'created_at': now,
        'updated_at': now,
      });
    } on DatabaseException catch (error) {
      final message = error.toString().toLowerCase();
      if (message.contains('username')) throw const ApiException(message: 'این نام کاربری قبلاً ثبت شده است.');
      if (message.contains('email')) throw const ApiException(message: 'این ایمیل قبلاً ثبت شده است.');
      throw const ApiException(message: 'ثبت حساب کاربری انجام نشد.');
    }
    setCurrentUser(id);
    return profile();
  }

  Future<void> logout() async => setCurrentUser(null);

  Future<String?> forgotPassword(String email) async {
    final db = await localDatabase.database;
    final rows = await db.query('users', where: 'email = ? COLLATE NOCASE', whereArgs: [email.trim()], limit: 1);
    if (rows.isEmpty) return null;
    final token = '${_uuid.v4()}${_uuid.v4()}'.replaceAll('-', '');
    await db.delete('password_reset_tokens', where: 'user_id = ?', whereArgs: [rows.first['id']]);
    await db.insert('password_reset_tokens', {
      'token': token,
      'user_id': rows.first['id'],
      'expires_at': DateTime.now().add(const Duration(minutes: 15)).toUtc().toIso8601String(),
    });
    return token;
  }

  Future<void> resetPassword(String token, String newPassword) async {
    final db = await localDatabase.database;
    final rows = await db.query('password_reset_tokens', where: 'token = ?', whereArgs: [token.trim()], limit: 1);
    if (rows.isEmpty) throw const ApiException(message: 'توکن بازیابی معتبر نیست.');
    final expires = DateTime.tryParse(rows.first['expires_at'].toString());
    if (expires == null || expires.isBefore(DateTime.now().toUtc())) {
      await db.delete('password_reset_tokens', where: 'token = ?', whereArgs: [token.trim()]);
      throw const ApiException(message: 'توکن بازیابی منقضی شده است.');
    }
    final digest = PasswordHasher.hash(newPassword);
    await db.update(
      'users',
      {
        'password_hash': digest.hash,
        'password_salt': digest.salt,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [rows.first['user_id']],
    );
    await db.delete('password_reset_tokens', where: 'user_id = ?', whereArgs: [rows.first['user_id']]);
  }

  Future<UserModel> profile([String? userId]) async {
    final id = userId ?? _userId;
    final db = await localDatabase.database;
    final rows = await db.query('users', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) throw const ApiException(message: 'حساب کاربری پیدا نشد.');
    return _userFromRow(rows.first);
  }

  Future<UserModel> updateProfile(Map<String, dynamic> changes) async {
    final db = await localDatabase.database;
    final values = <String, dynamic>{};
    for (final entry in changes.entries) {
      switch (entry.key) {
        case 'first_name':
        case 'last_name':
        case 'username':
        case 'email':
        case 'bio':
          values[entry.key] = entry.value?.toString().trim();
      }
    }
    if (values['email'] != null && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(values['email'].toString())) {
      throw const ApiException(message: 'ایمیل معتبر وارد کنید.');
    }
    values['updated_at'] = DateTime.now().toUtc().toIso8601String();
    try {
      await db.update('users', values, where: 'id = ?', whereArgs: [_userId]);
    } on DatabaseException catch (_) {
      throw const ApiException(message: 'ایمیل یا نام کاربری واردشده قبلاً ثبت شده است.');
    }
    return profile();
  }

  Future<UserModel> uploadAvatar(String path) async {
    final avatar = await _persistAvatar(_userId, path);
    final db = await localDatabase.database;
    final old = await profile();
    if (old.avatarUrl != null && old.avatarUrl != avatar) {
      try { await File(old.avatarUrl!).delete(); } catch (_) {}
    }
    await db.update('users', {
      'avatar_path': avatar,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, where: 'id = ?', whereArgs: [_userId]);
    return profile();
  }

  Future<UserModel> deleteAvatar() async {
    final user = await profile();
    if (user.avatarUrl != null) {
      try { await File(user.avatarUrl!).delete(); } catch (_) {}
    }
    final db = await localDatabase.database;
    await db.update('users', {
      'avatar_path': null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, where: 'id = ?', whereArgs: [_userId]);
    return profile();
  }

  Future<HomeSections> home() async {
    // Fetch independent home sections concurrently so the first screen does not
    // serialize network latency. Movie and TV variants are merged where the
    // assignment asks for generic "works" rather than one media type.
    final results = await Future.wait<dynamic>([
      tmdb.get('/movie/popular', queryParameters: {'page': 1, 'region': AppConfig.tmdbRegion}, cacheFor: const Duration(minutes: 30)),
      tmdb.get('/tv/popular', queryParameters: {'page': 1}, cacheFor: const Duration(minutes: 30)),
      tmdb.get('/movie/now_playing', queryParameters: {'page': 1, 'region': AppConfig.tmdbRegion}, cacheFor: const Duration(minutes: 30)),
      tmdb.get('/tv/on_the_air', queryParameters: {'page': 1}, cacheFor: const Duration(minutes: 30)),
      tmdb.get('/movie/top_rated', queryParameters: {'page': 1, 'region': AppConfig.tmdbRegion}, cacheFor: const Duration(minutes: 30)),
      tmdb.get('/tv/top_rated', queryParameters: {'page': 1}, cacheFor: const Duration(minutes: 30)),
      tmdb.get('/trending/all/week', queryParameters: const {}, cacheFor: const Duration(minutes: 30)),
    ]);
    final popularMovies = await _summariesFromTmdbList(results[0], forcedType: 'movie');
    final popularSeries = await _summariesFromTmdbList(results[1], forcedType: 'series');
    final newMovies = await _summariesFromTmdbList(results[2], forcedType: 'movie');
    final newSeries = await _summariesFromTmdbList(results[3], forcedType: 'series');
    final topMovies = await _summariesFromTmdbList(results[4], forcedType: 'movie');
    final topSeries = await _summariesFromTmdbList(results[5], forcedType: 'series');
    final recommendations = await _summariesFromTmdbList(results[6]);
    final newReleases = <MediaSummary>[...newMovies, ...newSeries]
      ..sort((a, b) => (b.releaseYear ?? 0).compareTo(a.releaseYear ?? 0));
    final topRated = <MediaSummary>[...topMovies, ...topSeries]
      ..sort((a, b) => (b.providerRating ?? 0).compareTo(a.providerRating ?? 0));
    return HomeSections(
      popularMovies: popularMovies.take(12).toList(),
      popularSeries: popularSeries.take(12).toList(),
      newReleases: newReleases.take(12).toList(),
      topRated: topRated.take(12).toList(),
      recommendations: recommendations.take(12).toList(),
    );
  }

  Future<PageResult<MediaSummary>> search({
    String? query,
    String? mediaType,
    String? actor,
    String? director,
    String? genre,
    int? year,
    int page = 1,
  }) async {
    final q = query?.trim() ?? '';
    final actorName = actor?.trim() ?? '';
    final directorName = director?.trim() ?? '';
    if (actorName.isNotEmpty || directorName.isNotEmpty) {
      return _searchByPeople(
        query: q,
        actor: actorName,
        director: directorName,
        mediaType: mediaType,
        genre: genre,
        year: year,
        page: page,
      );
    }

    final genreMaps = await _genreMaps();
    final genreIdMovie = _genreIdForName(genreMaps.$1, genre);
    final genreIdTv = _genreIdForName(genreMaps.$2, genre);
    final futures = <Future<List<MediaSummary>>>[];
    final types = mediaType == 'movie'
        ? const ['movie']
        : mediaType == 'series'
            ? const ['series']
            : const ['movie', 'series'];
    for (final type in types) {
      if (q.isNotEmpty) {
        final tmdbType = type == 'series' ? 'tv' : 'movie';
        futures.add(tmdb
            .get('/search/$tmdbType', queryParameters: {
              'query': q,
              'page': page,
              'include_adult': false,
              if (type == 'movie' && year != null) 'year': year,
              if (type == 'series' && year != null) 'first_air_date_year': year,
            }, cacheFor: const Duration(minutes: 10))
            .then((data) => _summariesFromTmdbList(data, forcedType: type)));
      } else {
        final tmdbType = type == 'series' ? 'tv' : 'movie';
        final genreId = type == 'series' ? genreIdTv : genreIdMovie;
        futures.add(tmdb
            .get('/discover/$tmdbType', queryParameters: {
              'page': page,
              'include_adult': false,
              'sort_by': 'popularity.desc',
              if (genreId != null) 'with_genres': genreId,
              if (type == 'movie' && year != null) 'primary_release_year': year,
              if (type == 'series' && year != null) 'first_air_date_year': year,
            }, cacheFor: const Duration(minutes: 10))
            .then((data) => _summariesFromTmdbList(data, forcedType: type)));
      }
    }
    final groups = await Future.wait(futures);
    var items = groups.expand((x) => x).toList();
    if (genre?.trim().isNotEmpty == true && q.isNotEmpty) {
      items = items.where((item) => item.genres.any((g) => g.toLowerCase() == genre!.trim().toLowerCase())).toList();
    }
    items.sort((a, b) => (b.providerRating ?? 0).compareTo(a.providerRating ?? 0));
    final effectivePageSize = AppConfig.pageSize * types.length;
    final resultItems = items.take(effectivePageSize).toList();
    final hasNext = resultItems.length >= effectivePageSize;
    final total = resultItems.length + ((page - 1) * effectivePageSize) + (hasNext ? 1 : 0);
    return PageResult(
      items: resultItems,
      page: page,
      pageSize: effectivePageSize,
      total: total,
      totalPages: page + (hasNext ? 1 : 0),
      hasNext: hasNext,
    );
  }

  Future<PageResult<MediaSummary>> _searchByPeople({
    required String query,
    required String actor,
    required String director,
    String? mediaType,
    String? genre,
    int? year,
    required int page,
  }) async {
    Future<Map<String, dynamic>?> findPerson(String name) async {
      if (name.isEmpty) return null;
      final raw = _map(await tmdb.get('/search/person', queryParameters: {'query': name, 'page': 1}, cacheFor: const Duration(minutes: 30)));
      final results = _list(raw['results']);
      return results.isEmpty ? null : _map(results.first);
    }

    final people = await Future.wait([findPerson(actor), findPerson(director)]);
    if (actor.isNotEmpty && people[0] == null || director.isNotEmpty && people[1] == null) {
      return PageResult(items: const [], page: page, pageSize: AppConfig.pageSize, total: 0, totalPages: 0, hasNext: false);
    }

    Future<Map<String, Map<String, dynamic>>> credits(Map<String, dynamic>? person, {required bool directorOnly}) async {
      if (person == null) return <String, Map<String, dynamic>>{};
      final raw = _map(await tmdb.get('/person/${person['id']}/combined_credits', cacheFor: const Duration(hours: 6)));
      final source = directorOnly
          ? _list(raw['crew']).where((x) => _map(x)['job']?.toString() == 'Director')
          : _list(raw['cast']);
      final out = <String, Map<String, dynamic>>{};
      for (final item in source) {
        final map = _map(item);
        final mt = map['media_type']?.toString();
        if (mt != 'movie' && mt != 'tv') continue;
        out['$mt:${map['id']}'] = map;
      }
      return out;
    }

    final creditMaps = await Future.wait([
      credits(people[0], directorOnly: false),
      credits(people[1], directorOnly: true),
    ]);
    Set<String> keys;
    if (actor.isNotEmpty && director.isNotEmpty) {
      keys = creditMaps[0].keys.toSet().intersection(creditMaps[1].keys.toSet());
    } else {
      keys = actor.isNotEmpty ? creditMaps[0].keys.toSet() : creditMaps[1].keys.toSet();
    }
    final genreMaps = await _genreMaps();
    final summaries = <MediaSummary>[];
    for (final key in keys) {
      final raw = creditMaps[0][key] ?? creditMaps[1][key];
      if (raw == null) continue;
      final type = raw['media_type'] == 'tv' ? 'series' : 'movie';
      if (mediaType != null && mediaType.isNotEmpty && mediaType != type) continue;
      final summary = await _summaryFromTmdb(raw, forcedType: type, genreMaps: genreMaps);
      if (query.isNotEmpty && !summary.title.toLowerCase().contains(query.toLowerCase()) && !(summary.originalTitle ?? '').toLowerCase().contains(query.toLowerCase())) continue;
      if (year != null && summary.releaseYear != year) continue;
      if (genre?.trim().isNotEmpty == true && !summary.genres.any((g) => g.toLowerCase() == genre!.trim().toLowerCase())) continue;
      summaries.add(summary);
    }
    summaries.sort((a, b) => (b.providerRating ?? 0).compareTo(a.providerRating ?? 0));
    final start = (page - 1) * AppConfig.pageSize;
    final end = (start + AppConfig.pageSize).clamp(0, summaries.length).toInt();
    final items = start >= summaries.length ? <MediaSummary>[] : summaries.sublist(start, end);
    return PageResult(
      items: items,
      page: page,
      pageSize: AppConfig.pageSize,
      total: summaries.length,
      totalPages: (summaries.length / AppConfig.pageSize).ceil(),
      hasNext: end < summaries.length,
    );
  }

  Future<MediaDetail> mediaDetail(String mediaId) async {
    final parsed = _parseMediaId(mediaId);
    final path = parsed.$1 == 'series' ? '/tv/${parsed.$2}' : '/movie/${parsed.$2}';
    final append = parsed.$1 == 'series' ? 'aggregate_credits,external_ids' : 'credits,external_ids';
    final raw = _map(await tmdb.get(path, queryParameters: {'append_to_response': append}, cacheFor: const Duration(hours: AppConfig.detailsCacheHours)));
    final detail = await _detailFromTmdb(raw, parsed.$1);
    await _cacheDetail(detail, parsed.$2);
    return detail;
  }

  Future<List<SeasonModel>> seasons(String mediaId) async {
    final parsed = _parseMediaId(mediaId);
    if (parsed.$1 != 'series') return const [];
    final seriesRaw = _map(await tmdb.get('/tv/${parsed.$2}', cacheFor: const Duration(hours: 12)));
    final seasons = _list(seriesRaw['seasons']).where((item) => _int(_map(item)['season_number']) > 0).toList();
    final results = await Future.wait(seasons.map((season) async {
      final seasonNumber = _int(_map(season)['season_number']);
      final raw = _map(await tmdb.get('/tv/${parsed.$2}/season/$seasonNumber', cacheFor: const Duration(hours: 12)));
      final episodes = <EpisodeModel>[];
      for (final item in _list(raw['episodes'])) {
        final map = _map(item);
        final episodeNumber = _int(map['episode_number']);
        final episodeId = 'tmdb-episode-${parsed.$2}-$seasonNumber-$episodeNumber';
        episodes.add(EpisodeModel(
          episodeId: episodeId,
          seasonNumber: seasonNumber,
          episodeNumber: episodeNumber,
          title: map['name']?.toString() ?? 'قسمت $episodeNumber',
          releaseDate: _date(map['air_date']),
          runtimeMinutes: _nullableInt(map['runtime']),
          plot: map['overview']?.toString(),
          watched: await _episodeWatched(episodeId),
        ));
      }
      return SeasonModel(
        seasonNumber: seasonNumber,
        title: raw['name']?.toString(),
        episodeCount: episodes.length,
        episodes: episodes,
      );
    }));
    results.sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
    return results;
  }

  Future<PageResult<CommentModel>> comments(String mediaId, {int page = 1}) async {
    final db = await localDatabase.database;
    final offset = (page - 1) * AppConfig.pageSize;
    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM comments WHERE media_id = ?', [mediaId])) ?? 0;
    final rows = await db.rawQuery('''
      SELECT c.*, u.username, u.avatar_path
      FROM comments c JOIN users u ON u.id = c.user_id
      WHERE c.media_id = ?
      ORDER BY c.created_at DESC
      LIMIT ? OFFSET ?
    ''', [mediaId, AppConfig.pageSize, offset]);
    final items = rows.map((row) => CommentModel(
      id: row['id'].toString(),
      text: row['text'].toString(),
      username: row['username'].toString(),
      userAvatarUrl: row['avatar_path']?.toString(),
      createdAt: _dateTime(row['created_at']) ?? DateTime.now(),
      updatedAt: _dateTime(row['updated_at']) ?? DateTime.now(),
      isSpoiler: _bool(row['is_spoiler']),
      isHidden: false,
      ownComment: _currentUserId != null && row['user_id'].toString() == _currentUserId,
    )).toList();
    return PageResult(
      items: items,
      page: page,
      pageSize: AppConfig.pageSize,
      total: count,
      totalPages: (count / AppConfig.pageSize).ceil(),
      hasNext: offset + items.length < count,
    );
  }

  Future<CommentModel> addComment(String mediaId, {required String text, required bool isSpoiler}) async {
    if (text.trim().isEmpty) throw const ApiException(message: 'متن نظر نباید خالی باشد.');
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    final db = await localDatabase.database;
    await db.insert('comments', {
      'id': id,
      'user_id': _userId,
      'media_id': mediaId,
      'text': text.trim(),
      'is_spoiler': isSpoiler ? 1 : 0,
      'created_at': now,
      'updated_at': now,
    });
    await _addActivity('comment', mediaId, detail: 'ثبت نظر');
    final user = await profile();
    return CommentModel(
      id: id,
      text: text.trim(),
      username: user.username,
      userAvatarUrl: user.avatarUrl,
      createdAt: DateTime.parse(now).toLocal(),
      updatedAt: DateTime.parse(now).toLocal(),
      isSpoiler: isSpoiler,
      isHidden: false,
      ownComment: true,
    );
  }

  Future<CommentModel> editComment(String commentId, {required String text, required bool isSpoiler}) async {
    final db = await localDatabase.database;
    final rows = await db.query('comments', where: 'id = ? AND user_id = ?', whereArgs: [commentId, _userId], limit: 1);
    if (rows.isEmpty) throw const ApiException(message: 'این نظر متعلق به شما نیست.');
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update('comments', {'text': text.trim(), 'is_spoiler': isSpoiler ? 1 : 0, 'updated_at': now}, where: 'id = ?', whereArgs: [commentId]);
    final user = await profile();
    return CommentModel(
      id: commentId,
      text: text.trim(),
      username: user.username,
      userAvatarUrl: user.avatarUrl,
      createdAt: _dateTime(rows.first['created_at']) ?? DateTime.now(),
      updatedAt: DateTime.parse(now).toLocal(),
      isSpoiler: isSpoiler,
      isHidden: false,
      ownComment: true,
    );
  }

  Future<void> deleteComment(String commentId) async {
    final db = await localDatabase.database;
    await db.delete('comments', where: 'id = ? AND user_id = ?', whereArgs: [commentId, _userId]);
  }

  Future<void> reportComment(String commentId, String reason) async {
    final db = await localDatabase.database;
    await db.insert('reports', {
      'id': _uuid.v4(),
      'user_id': _userId,
      'comment_id': commentId,
      'reason': reason.trim(),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<UserMediaState> setWatchStatus(String mediaId, String status) async {
    if (!const {'plan_to_watch', 'watching', 'completed', 'paused', 'dropped'}.contains(status)) {
      throw const ApiException(message: 'وضعیت تماشا معتبر نیست.');
    }
    await _upsertUserMedia(mediaId, watchStatus: status);
    await _addActivity('watch_status', mediaId, detail: status);
    return _userState(mediaId);
  }

  Future<void> removeFromLibrary(String mediaId) async {
    final db = await localDatabase.database;
    final row = await _userMediaRow(mediaId);
    if (row == null) return;
    if (_bool(row['is_favorite'])) {
      await db.update('user_media', {'watch_status': null, 'updated_at': DateTime.now().toUtc().toIso8601String()}, where: 'user_id = ? AND media_id = ?', whereArgs: [_userId, mediaId]);
    } else {
      await db.delete('user_media', where: 'user_id = ? AND media_id = ?', whereArgs: [_userId, mediaId]);
    }
  }

  Future<void> setFavorite(String mediaId, bool enabled) async {
    await _upsertUserMedia(mediaId, favorite: enabled);
    await _addActivity('favorite', mediaId, detail: enabled ? 'افزوده شد' : 'حذف شد');
  }

  Future<RatingDistribution> rate(String mediaId, int score) async {
    if (score < 1 || score > 5) throw const ApiException(message: 'امتیاز باید بین ۱ تا ۵ باشد.');
    final db = await localDatabase.database;
    await db.insert('ratings', {
      'user_id': _userId,
      'media_id': mediaId,
      'score': score,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _addActivity('rating', mediaId, detail: '$score/5');
    return _ratingDistribution(mediaId);
  }

  Future<void> removeRating(String mediaId) async {
    final db = await localDatabase.database;
    await db.delete('ratings', where: 'user_id = ? AND media_id = ?', whereArgs: [_userId, mediaId]);
  }

  Future<ProgressModel> markEpisode(String episodeId, bool watched) async {
    final parts = episodeId.split('-');
    if (parts.length < 5) throw const ApiException(message: 'شناسه قسمت معتبر نیست.');
    final tvId = int.tryParse(parts[2]);
    final season = int.tryParse(parts[3]);
    final episode = int.tryParse(parts[4]);
    // Compatibility with canonical id tmdb-episode-TV-SEASON-EPISODE.
    final actualTvId = tvId ?? int.tryParse(parts[parts.length - 3]);
    final actualSeason = season ?? int.tryParse(parts[parts.length - 2]);
    final actualEpisode = episode ?? int.tryParse(parts.last);
    if (actualTvId == null || actualSeason == null || actualEpisode == null) throw const ApiException(message: 'شناسه قسمت معتبر نیست.');
    final mediaId = 'tmdb-series-$actualTvId';
    final db = await localDatabase.database;
    int? runtime;
    try {
      final raw = _map(await tmdb.get('/tv/$actualTvId/season/$actualSeason/episode/$actualEpisode', cacheFor: const Duration(hours: 12)));
      runtime = _nullableInt(raw['runtime']);
    } catch (_) {}
    if (watched) {
      await db.insert('user_episodes', {
        'user_id': _userId,
        'episode_id': episodeId,
        'media_id': mediaId,
        'season_number': actualSeason,
        'episode_number': actualEpisode,
        'runtime_minutes': runtime,
        'watched': 1,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      await db.delete('user_episodes', where: 'user_id = ? AND episode_id = ?', whereArgs: [_userId, episodeId]);
    }
    await _addActivity('episode', mediaId, detail: 'S$actualSeason E$actualEpisode ${watched ? 'دیده شد' : 'لغو شد'}');
    final progress = await _progress(mediaId);
    return progress;
  }

  Future<PageResult<LibraryEntry>> library({String? status, int page = 1}) async {
    final db = await localDatabase.database;
    final where = <String>['user_id = ?'];
    final args = <Object?>[_userId];
    if (status == 'favorite') {
      where.add('is_favorite = 1');
    } else if (status != null) {
      where.add('watch_status = ?');
      args.add(status);
    }
    final whereSql = where.join(' AND ');
    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM user_media WHERE $whereSql', args)) ?? 0;
    final rows = await db.query(
      'user_media',
      where: whereSql,
      whereArgs: args,
      orderBy: 'updated_at DESC',
      limit: AppConfig.pageSize,
      offset: (page - 1) * AppConfig.pageSize,
    );
    final items = <LibraryEntry>[];
    for (final row in rows) {
      final media = await _cachedSummary(row['media_id'].toString());
      if (media == null) continue;
      items.add(LibraryEntry(
        media: media,
        watchStatus: row['watch_status']?.toString(),
        isFavorite: _bool(row['is_favorite']),
        progress: media.isSeries ? await _progress(media.mediaId) : null,
        updatedAt: _dateTime(row['updated_at']) ?? DateTime.now(),
      ));
    }
    return PageResult(
      items: items,
      page: page,
      pageSize: AppConfig.pageSize,
      total: count,
      totalPages: (count / AppConfig.pageSize).ceil(),
      hasNext: page * AppConfig.pageSize < count,
    );
  }

  Future<List<CustomListModel>> customLists() async {
    final db = await localDatabase.database;
    final rows = await db.query('custom_lists', where: 'user_id = ?', whereArgs: [_userId], orderBy: 'updated_at DESC');
    final lists = <CustomListModel>[];
    for (final row in rows) {
      lists.add(await _customListFromRow(row, includeItems: false));
    }
    return lists;
  }

  Future<CustomListModel> customList(String id) async {
    final db = await localDatabase.database;
    final rows = await db.query('custom_lists', where: 'id = ? AND user_id = ?', whereArgs: [id, _userId], limit: 1);
    if (rows.isEmpty) throw const ApiException(message: 'فهرست پیدا نشد.');
    return _customListFromRow(rows.first, includeItems: true);
  }

  Future<CustomListModel> createList({required String name, String? description, bool isPublic = false}) async {
    if (name.trim().isEmpty) throw const ApiException(message: 'نام فهرست نباید خالی باشد.');
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    final db = await localDatabase.database;
    await db.insert('custom_lists', {
      'id': id,
      'user_id': _userId,
      'name': name.trim(),
      'description': description?.trim(),
      'is_public': isPublic ? 1 : 0,
      'created_at': now,
      'updated_at': now,
    });
    await _addActivity('custom_list', '', detail: 'ساخت ${name.trim()}');
    return customList(id);
  }

  Future<CustomListModel> updateList(String id, {String? name, String? description, bool? isPublic}) async {
    final db = await localDatabase.database;
    await db.update('custom_lists', {
      if (name != null) 'name': name.trim(),
      if (description != null) 'description': description.trim(),
      if (isPublic != null) 'is_public': isPublic ? 1 : 0,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, where: 'id = ? AND user_id = ?', whereArgs: [id, _userId]);
    return customList(id);
  }

  Future<void> deleteList(String id) async {
    final db = await localDatabase.database;
    await db.delete('custom_lists', where: 'id = ? AND user_id = ?', whereArgs: [id, _userId]);
  }

  Future<void> addListItem(String id, String mediaId) async {
    await customList(id);
    final db = await localDatabase.database;
    await db.insert('custom_list_items', {
      'list_id': id,
      'media_id': mediaId,
      'added_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.update('custom_lists', {'updated_at': DateTime.now().toUtc().toIso8601String()}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> removeListItem(String id, String mediaId) async {
    final db = await localDatabase.database;
    await db.delete('custom_list_items', where: 'list_id = ? AND media_id = ?', whereArgs: [id, mediaId]);
  }

  Future<UserStats> stats() async {
    final db = await localDatabase.database;
    final rows = await db.rawQuery('''
      SELECT um.media_id, um.watch_status, um.is_favorite, mc.media_type, mc.detail_json, mc.summary_json
      FROM user_media um LEFT JOIN media_cache mc ON mc.media_id = um.media_id
      WHERE um.user_id = ?
    ''', [_userId]);
    var watchedMovies = 0;
    var watchedSeries = 0;
    var movieMinutes = 0;
    var favorites = 0;
    final genres = <String, int>{};
    for (final row in rows) {
      if (_bool(row['is_favorite'])) favorites++;
      if (row['watch_status'] == 'completed') {
        if (row['media_type'] == 'movie') watchedMovies++;
        if (row['media_type'] == 'series') watchedSeries++;
        final detailRaw = row['detail_json']?.toString();
        if (row['media_type'] == 'movie' && detailRaw != null) {
          final detail = _map(jsonDecode(detailRaw));
          movieMinutes += _nullableInt(detail['runtime_minutes']) ?? 0;
        }
      }
      final summaryRaw = row['summary_json']?.toString();
      if (summaryRaw != null && (row['watch_status'] == 'completed' || _bool(row['is_favorite']))) {
        final summary = _map(jsonDecode(summaryRaw));
        for (final genre in _stringList(summary['genres'])) {
          genres[genre] = (genres[genre] ?? 0) + 1;
        }
      }
    }
    final epRows = await db.rawQuery('SELECT COUNT(*) count, COALESCE(SUM(runtime_minutes), 0) minutes FROM user_episodes WHERE user_id = ? AND watched = 1', [_userId]);
    final watchedEpisodes = _int(epRows.first['count']);
    final episodeMinutes = _int(epRows.first['minutes']);
    final ratingRows = await db.rawQuery('SELECT AVG(score) average FROM ratings WHERE user_id = ?', [_userId]);
    final avg = ratingRows.first['average'] == null ? null : (ratingRows.first['average'] as num).toDouble();
    final listCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM custom_lists WHERE user_id = ?', [_userId])) ?? 0;
    final favoriteGenre = genres.entries.isEmpty ? null : (genres.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
    final minutes = movieMinutes + episodeMinutes;
    return UserStats(
      watchedMovies: watchedMovies,
      watchedSeries: watchedSeries,
      watchedEpisodes: watchedEpisodes,
      approximateWatchMinutes: minutes,
      approximateWatchHours: minutes / 60,
      favoriteGenre: favoriteGenre,
      averageUserRating: avg,
      favoritesCount: favorites,
      customListsCount: listCount,
    );
  }

  Future<List<ActivityItem>> activity() async {
    final db = await localDatabase.database;
    final rows = await db.query('activity', where: 'user_id = ?', whereArgs: [_userId], orderBy: 'occurred_at DESC', limit: 100);
    return rows.map((row) => ActivityItem(
      kind: row['kind'].toString(),
      mediaId: row['media_id'].toString(),
      mediaTitle: row['media_title'].toString(),
      mediaType: row['media_type'].toString(),
      occurredAt: _dateTime(row['occurred_at']) ?? DateTime.now(),
      detail: row['detail']?.toString(),
    )).toList();
  }

  Future<void> _upsertUserMedia(String mediaId, {String? watchStatus, bool? favorite}) async {
    final db = await localDatabase.database;
    final existing = await _userMediaRow(mediaId);
    await db.insert('user_media', {
      'user_id': _userId,
      'media_id': mediaId,
      'watch_status': watchStatus ?? existing?['watch_status'],
      'is_favorite': favorite == null ? (_bool(existing?['is_favorite']) ? 1 : 0) : (favorite ? 1 : 0),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> _userMediaRow(String mediaId) async {
    final db = await localDatabase.database;
    final rows = await db.query('user_media', where: 'user_id = ? AND media_id = ?', whereArgs: [_userId, mediaId], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<UserMediaState> _userState(String mediaId) async {
    if (_currentUserId == null) {
      final progress = await _progress(mediaId, allowGuest: true);
      return UserMediaState(
        watchStatus: null,
        isFavorite: false,
        userRating: null,
        watchedEpisodes: progress.watchedEpisodes,
        remainingEpisodes: progress.remainingEpisodes,
        progressPercent: progress.progressPercent,
        progressColor: progress.progressColor,
        progressHex: progress.progressHex,
      );
    }
    final row = await _userMediaRow(mediaId);
    final db = await localDatabase.database;
    final ratingRows = await db.query('ratings', where: 'user_id = ? AND media_id = ?', whereArgs: [_userId, mediaId], limit: 1);
    final progress = await _progress(mediaId);
    return UserMediaState(
      watchStatus: row?['watch_status']?.toString(),
      isFavorite: _bool(row?['is_favorite']),
      userRating: ratingRows.isEmpty ? null : _int(ratingRows.first['score']),
      watchedEpisodes: progress.watchedEpisodes,
      remainingEpisodes: progress.remainingEpisodes,
      progressPercent: progress.progressPercent,
      progressColor: progress.progressColor,
      progressHex: progress.progressHex,
    );
  }

  Future<ProgressModel> _progress(String mediaId, {bool allowGuest = false}) async {
    final summary = await _cachedSummary(mediaId);
    final totalEpisodes = summary?.episodeCount ?? 0;
    var watched = 0;
    if (_currentUserId != null) {
      final db = await localDatabase.database;
      watched = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM user_episodes WHERE user_id = ? AND media_id = ? AND watched = 1', [_userId, mediaId])) ?? 0;
    }
    final remaining = (totalEpisodes - watched).clamp(0, totalEpisodes).toInt();
    final percent = totalEpisodes <= 0 ? 0.0 : watched * 100 / totalEpisodes;
    final userMedia = _currentUserId == null ? null : await _userMediaRow(mediaId);
    final status = userMedia?['watch_status']?.toString();
    final releaseStatus = summary?.releaseStatus;
    late final String color;
    late final String hex;
    if (status == 'paused' || status == 'dropped') {
      color = 'red'; hex = '#E53935';
    } else if (totalEpisodes == 0 || watched == 0) {
      color = 'black'; hex = '#212121';
    } else if (watched >= totalEpisodes && releaseStatus == 'ongoing') {
      color = 'green'; hex = '#43A047';
    } else if (watched >= totalEpisodes && releaseStatus != 'ongoing') {
      color = 'purple'; hex = '#8E24AA';
    } else {
      color = 'yellow'; hex = '#FDD835';
    }
    return ProgressModel(
      mediaId: mediaId,
      watchedEpisodes: watched,
      totalEpisodes: totalEpisodes,
      remainingEpisodes: remaining,
      progressPercent: percent,
      progressColor: color,
      progressHex: hex,
      releaseStatus: releaseStatus,
    );
  }

  Future<RatingDistribution> _ratingDistribution(String mediaId) async {
    final db = await localDatabase.database;
    final rows = await db.rawQuery('SELECT score, COUNT(*) count FROM ratings WHERE media_id = ? GROUP BY score', [mediaId]);
    final counts = <int, int>{for (var star = 1; star <= 5; star++) star: 0};
    var total = 0;
    for (final row in rows) {
      final score = _int(row['score']);
      final count = _int(row['count']);
      counts[score] = count;
      total += count;
    }
    final percentages = <int, double>{for (var star = 1; star <= 5; star++) star: total == 0 ? 0 : (counts[star]! * 100 / total)};
    return RatingDistribution(total: total, percentages: percentages, counts: counts);
  }

  Future<void> _addActivity(String kind, String mediaId, {String? detail}) async {
    if (_currentUserId == null) return;
    final summary = mediaId.isEmpty ? null : await _cachedSummary(mediaId);
    final db = await localDatabase.database;
    await db.insert('activity', {
      'user_id': _userId,
      'kind': kind,
      'media_id': mediaId,
      'media_title': summary?.title ?? '',
      'media_type': summary?.mediaType ?? '',
      'detail': detail,
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<CustomListModel> _customListFromRow(Map<String, dynamic> row, {required bool includeItems}) async {
    final db = await localDatabase.database;
    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM custom_list_items WHERE list_id = ?', [row['id']])) ?? 0;
    final items = <MediaSummary>[];
    if (includeItems) {
      final itemRows = await db.query('custom_list_items', where: 'list_id = ?', whereArgs: [row['id']], orderBy: 'added_at DESC');
      for (final item in itemRows) {
        final summary = await _cachedSummary(item['media_id'].toString());
        if (summary != null) items.add(summary);
      }
    }
    return CustomListModel(
      id: row['id'].toString(),
      name: row['name'].toString(),
      description: row['description']?.toString(),
      isPublic: _bool(row['is_public']),
      itemCount: count,
      createdAt: _dateTime(row['created_at']) ?? DateTime.now(),
      updatedAt: _dateTime(row['updated_at']) ?? DateTime.now(),
      items: items,
    );
  }

  Future<bool> _episodeWatched(String episodeId) async {
    if (_currentUserId == null) return false;
    final db = await localDatabase.database;
    final rows = await db.query('user_episodes', where: 'user_id = ? AND episode_id = ? AND watched = 1', whereArgs: [_userId, episodeId], limit: 1);
    return rows.isNotEmpty;
  }

  Future<List<MediaSummary>> _summariesFromTmdbList(dynamic data, {String? forcedType}) async {
    final map = _map(data);
    final genreMaps = await _genreMaps();
    final out = <MediaSummary>[];
    for (final raw in _list(map['results'])) {
      final item = _map(raw);
      final type = forcedType ?? (item['media_type'] == 'tv' ? 'series' : item['media_type'] == 'movie' ? 'movie' : null);
      if (type == null) continue;
      out.add(await _summaryFromTmdb(item, forcedType: type, genreMaps: genreMaps));
    }
    return out;
  }

  Future<MediaSummary> _summaryFromTmdb(Map<String, dynamic> raw, {required String forcedType, (Map<int, String>, Map<int, String>)? genreMaps}) async {
    final id = _int(raw['id']);
    final isSeries = forcedType == 'series';
    final genresById = isSeries ? (genreMaps ?? await _genreMaps()).$2 : (genreMaps ?? await _genreMaps()).$1;
    final genres = raw['genres'] is List
        ? _list(raw['genres']).map((x) => _map(x)['name']?.toString() ?? '').where((x) => x.isNotEmpty).toList()
        : _list(raw['genre_ids']).map((x) => genresById[_int(x)]).whereType<String>().toList();
    final releaseDate = isSeries ? _date(raw['first_air_date']) : _date(raw['release_date']);
    final summary = MediaSummary(
      mediaId: 'tmdb-${isSeries ? 'series' : 'movie'}-$id',
      mediaType: forcedType,
      title: (isSeries ? raw['name'] : raw['title'])?.toString() ?? '',
      originalTitle: (isSeries ? raw['original_name'] : raw['original_title'])?.toString(),
      posterUrl: TmdbClient.posterUrl(raw['poster_path']?.toString()),
      plot: raw['overview']?.toString(),
      genres: genres,
      releaseYear: releaseDate?.year,
      endYear: null,
      providerRating: _nullableDouble(raw['vote_average']),
      appRating: null,
      ratingCount: 0,
      releaseStatus: null,
      seasonCount: null,
      episodeCount: null,
    );
    final dist = await _ratingDistribution(summary.mediaId);
    final withLocal = MediaSummary(
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
      appRating: _averageFromDistribution(dist),
      ratingCount: dist.total,
      releaseStatus: summary.releaseStatus,
      seasonCount: summary.seasonCount,
      episodeCount: summary.episodeCount,
    );
    await _cacheSummary(withLocal, id);
    return withLocal;
  }

  Future<MediaDetail> _detailFromTmdb(Map<String, dynamic> raw, String type) async {
    final isSeries = type == 'series';
    final base = await _summaryFromTmdb(raw, forcedType: type);
    final credits = _map(raw[isSeries ? 'aggregate_credits' : 'credits']);
    final cast = _list(credits['cast'])
        .take(20)
        .map((x) => _map(x)['name']?.toString() ?? '')
        .where((x) => x.isNotEmpty)
        .toList();

    final directorSet = <String>{};
    if (isSeries) {
      for (final creator in _list(raw['created_by'])) {
        final name = _map(creator)['name']?.toString();
        if (name?.isNotEmpty == true) directorSet.add(name!);
      }
      for (final item in _list(credits['crew'])) {
        final crew = _map(item);
        final jobs = _list(crew['jobs']);
        final directs = jobs.any((job) => _map(job)['job']?.toString() == 'Director');
        if (directs) {
          final name = crew['name']?.toString();
          if (name?.isNotEmpty == true) directorSet.add(name!);
        }
      }
    } else {
      for (final item in _list(credits['crew'])) {
        final crew = _map(item);
        if (crew['job']?.toString() == 'Director') {
          final name = crew['name']?.toString();
          if (name?.isNotEmpty == true) directorSet.add(name!);
        }
      }
    }

    final countries = _list(raw['production_countries'])
        .map((x) => _map(x)['name']?.toString() ?? '')
        .where((x) => x.isNotEmpty)
        .toList();
    final releaseDate = isSeries ? _date(raw['first_air_date']) : _date(raw['release_date']);
    final endDate = isSeries ? _date(raw['last_air_date']) : null;
    final statusRaw = raw['status']?.toString().toLowerCase() ?? '';
    final releaseStatus = isSeries
        ? (statusRaw.contains('ended') || statusRaw.contains('canceled') ? 'ended' : 'ongoing')
        : (releaseDate != null && releaseDate.isAfter(DateTime.now()) ? 'upcoming' : 'released');
    final runtime = isSeries
        ? (_list(raw['episode_run_time']).isEmpty ? null : _int(_list(raw['episode_run_time']).first))
        : _nullableInt(raw['runtime']);
    final seasonCount = isSeries ? _nullableInt(raw['number_of_seasons']) : null;
    final episodeCount = isSeries ? _nullableInt(raw['number_of_episodes']) : null;
    final parsed = _parseMediaId(base.mediaId);

    // Cache the enriched summary before calculating progress so the exact total
    // episode count and release status are available to the local progress engine.
    final enrichedSummary = MediaSummary(
      mediaId: base.mediaId,
      mediaType: base.mediaType,
      title: base.title,
      originalTitle: base.originalTitle,
      posterUrl: base.posterUrl,
      plot: base.plot,
      genres: base.genres,
      releaseYear: base.releaseYear,
      endYear: endDate?.year,
      providerRating: base.providerRating,
      appRating: base.appRating,
      ratingCount: base.ratingCount,
      releaseStatus: releaseStatus,
      seasonCount: seasonCount,
      episodeCount: episodeCount,
    );
    await _cacheSummary(enrichedSummary, parsed.$2);

    final distribution = await _ratingDistribution(base.mediaId);
    final state = await _userState(base.mediaId);
    return MediaDetail(
      mediaId: base.mediaId,
      mediaType: type,
      title: base.title,
      originalTitle: base.originalTitle,
      posterUrl: base.posterUrl,
      plot: base.plot,
      genres: base.genres,
      releaseYear: base.releaseYear,
      endYear: endDate?.year,
      providerRating: base.providerRating,
      appRating: _averageFromDistribution(distribution),
      ratingCount: distribution.total,
      releaseStatus: releaseStatus,
      seasonCount: seasonCount,
      episodeCount: episodeCount,
      releaseDate: releaseDate,
      runtimeMinutes: runtime,
      countries: countries,
      directors: directorSet.toList(),
      cast: cast,
      providerVoteCount: _nullableInt(raw['vote_count']),
      ratingDistribution: distribution,
      userState: state,
    );
  }

  Future<(Map<int, String>, Map<int, String>)> _genreMaps() async {
    final results = await Future.wait<dynamic>([
      tmdb.get('/genre/movie/list', cacheFor: const Duration(days: 7)),
      tmdb.get('/genre/tv/list', cacheFor: const Duration(days: 7)),
    ]);
    Map<int, String> parse(dynamic raw) => {
      for (final item in _list(_map(raw)['genres'])) _int(_map(item)['id']): _map(item)['name']?.toString() ?? '',
    };
    return (parse(results[0]), parse(results[1]));
  }

  int? _genreIdForName(Map<int, String> genres, String? name) {
    final q = name?.trim().toLowerCase();
    if (q == null || q.isEmpty) return null;
    for (final entry in genres.entries) {
      if (entry.value.toLowerCase() == q || entry.value.toLowerCase().contains(q)) return entry.key;
    }
    return null;
  }

  Future<void> _cacheSummary(MediaSummary summary, int tmdbId) async {
    final db = await localDatabase.database;
    final existing = await db.query('media_cache', where: 'media_id = ?', whereArgs: [summary.mediaId], limit: 1);
    await db.insert('media_cache', {
      'media_id': summary.mediaId,
      'media_type': summary.mediaType,
      'tmdb_id': tmdbId,
      'summary_json': jsonEncode(_summaryJson(summary)),
      'detail_json': existing.isEmpty ? null : existing.first['detail_json'],
      'fetched_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _cacheDetail(MediaDetail detail, int tmdbId) async {
    final db = await localDatabase.database;
    await db.insert('media_cache', {
      'media_id': detail.mediaId,
      'media_type': detail.mediaType,
      'tmdb_id': tmdbId,
      'summary_json': jsonEncode(_summaryJson(detail)),
      'detail_json': jsonEncode(_detailJson(detail)),
      'fetched_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<MediaSummary?> _cachedSummary(String mediaId) async {
    final db = await localDatabase.database;
    final rows = await db.query('media_cache', where: 'media_id = ?', whereArgs: [mediaId], limit: 1);
    if (rows.isEmpty) return null;
    return MediaSummary.fromJson(_map(jsonDecode(rows.first['summary_json'].toString())));
  }

  Map<String, dynamic> _summaryJson(MediaSummary value) => {
    'media_id': value.mediaId,
    'media_type': value.mediaType,
    'title': value.title,
    'original_title': value.originalTitle,
    'poster_url': value.posterUrl,
    'plot': value.plot,
    'genres': value.genres,
    'release_year': value.releaseYear,
    'end_year': value.endYear,
    'provider_rating': value.providerRating,
    'app_rating': value.appRating,
    'rating_count': value.ratingCount,
    'release_status': value.releaseStatus,
    'season_count': value.seasonCount,
    'episode_count': value.episodeCount,
  };

  Map<String, dynamic> _detailJson(MediaDetail value) => {
    ..._summaryJson(value),
    'release_date': value.releaseDate?.toIso8601String(),
    'runtime_minutes': value.runtimeMinutes,
    'countries': value.countries,
    'directors': value.directors,
    'cast': value.cast,
    'provider_vote_count': value.providerVoteCount,
  };

  Future<String> _persistAvatar(String userId, String sourcePath) async {
    final dir = await getApplicationDocumentsDirectory();
    final avatarDir = Directory(p.join(dir.path, 'avatars'));
    await avatarDir.create(recursive: true);
    final ext = p.extension(sourcePath).isEmpty ? '.jpg' : p.extension(sourcePath);
    final destination = p.join(avatarDir.path, '$userId$ext');
    await File(sourcePath).copy(destination);
    return destination;
  }

  UserModel _userFromRow(Map<String, dynamic> row) => UserModel(
    id: row['id'].toString(),
    firstName: row['first_name'].toString(),
    lastName: row['last_name'].toString(),
    username: row['username'].toString(),
    email: row['email'].toString(),
    avatarUrl: row['avatar_path']?.toString(),
    bio: row['bio']?.toString(),
    role: 'user',
    isActive: true,
  );

  (String, int) _parseMediaId(String mediaId) {
    final parts = mediaId.split('-');
    if (parts.length != 3 || parts[0] != 'tmdb' || !const {'movie', 'series'}.contains(parts[1])) {
      throw const ApiException(message: 'شناسه فیلم یا سریال معتبر نیست.');
    }
    final id = int.tryParse(parts[2]);
    if (id == null) throw const ApiException(message: 'شناسه فیلم یا سریال معتبر نیست.');
    return (parts[1], id);
  }

  static Map<String, dynamic> _map(dynamic value) => value is Map<String, dynamic> ? value : value is Map ? value.map((k, v) => MapEntry(k.toString(), v)) : <String, dynamic>{};
  static List<dynamic> _list(dynamic value) => value is List ? value : const [];
  static int _int(dynamic value, [int fallback = 0]) => value is int ? value : int.tryParse(value?.toString() ?? '') ?? fallback;
  static int? _nullableInt(dynamic value) => value == null ? null : (value is int ? value : int.tryParse(value.toString()));
  static double? _nullableDouble(dynamic value) => value == null ? null : (value is num ? value.toDouble() : double.tryParse(value.toString()));
  static bool _bool(dynamic value) => value == true || value == 1 || value?.toString() == '1';
  static DateTime? _date(dynamic value) => value == null || value.toString().isEmpty ? null : DateTime.tryParse(value.toString());
  static DateTime? _dateTime(dynamic value) => value == null ? null : DateTime.tryParse(value.toString())?.toLocal();
  static List<String> _stringList(dynamic value) => value is List ? value.map((x) => x.toString()).toList() : const [];
  static double? _averageFromDistribution(RatingDistribution d) {
    if (d.total == 0) return null;
    var total = 0;
    for (var star = 1; star <= 5; star++) total += star * (d.counts[star] ?? 0);
    return total / d.total;
  }
}
