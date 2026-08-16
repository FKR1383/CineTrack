import 'package:dio/dio.dart';

import '../../core/api/api_client.dart';
import '../../core/config/app_config.dart';
import 'models.dart';

class CineTrackRepository {
  const CineTrackRepository(this.api);

  final ApiClient api;

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map<String, dynamic> ? value : <String, dynamic>{};

  static String absoluteUrl(String? value) {
    if (value == null || value.isEmpty) return '';
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    final base = Uri.parse(AppConfig.apiBaseUrl);
    final root = '${base.scheme}://${base.authority}';
    return '$root${value.startsWith('/') ? value : '/$value'}';
  }

  Future<AuthResult> login({
    required String email,
    required String password,
    required bool rememberMe,
  }) async {
    final data = await api.post(
      '/auth/login',
      data: {
        'email': email.trim(),
        'password': password,
        'remember_me': rememberMe,
        'device_info': 'CineTrack Flutter Android',
      },
    );
    return AuthResult.fromJson(_map(data));
  }

  Future<AuthResult> register({
    required String firstName,
    required String lastName,
    required String username,
    required String email,
    required String password,
    String? bio,
    String? profileImagePath,
  }) async {
    final form = FormData.fromMap({
      'first_name': firstName.trim(),
      'last_name': lastName.trim(),
      'username': username.trim(),
      'email': email.trim(),
      'password': password,
      if (bio?.trim().isNotEmpty == true) 'bio': bio!.trim(),
      if (profileImagePath != null)
        'profile_image': await MultipartFile.fromFile(profileImagePath),
    });
    final data = await api.post(
      '/auth/register',
      data: form,
      options: Options(contentType: 'multipart/form-data'),
    );
    return AuthResult.fromJson(_map(data));
  }

  Future<void> logout(String refreshToken) async {
    await api.post('/auth/logout', data: {'refresh_token': refreshToken});
  }

  Future<String?> forgotPassword(String email) async {
    final data = _map(await api.post('/auth/password/forgot', data: {'email': email.trim()}));
    return data['debug_reset_token']?.toString();
  }

  Future<void> resetPassword(String token, String newPassword) async {
    await api.post(
      '/auth/password/reset',
      data: {'token': token.trim(), 'new_password': newPassword},
    );
  }

  Future<UserModel> profile() async =>
      UserModel.fromJson(_map(await api.get('/users/me', deduplicate: false)));

  Future<UserModel> updateProfile(Map<String, dynamic> changes) async =>
      UserModel.fromJson(_map(await api.patch('/users/me', data: changes)));

  Future<UserModel> uploadAvatar(String path) async {
    final form = FormData.fromMap({
      'profile_image': await MultipartFile.fromFile(path),
    });
    return UserModel.fromJson(
      _map(
        await api.post(
          '/users/me/avatar',
          data: form,
          options: Options(contentType: 'multipart/form-data'),
        ),
      ),
    );
  }


  Future<UserModel> deleteAvatar() async =>
      UserModel.fromJson(_map(await api.delete('/users/me/avatar')));

  Future<HomeSections> home() async =>
      HomeSections.fromJson(_map(await api.get('/media/home')));

  Future<PageResult<MediaSummary>> search({
    String? query,
    String? mediaType,
    String? actor,
    String? director,
    String? genre,
    int? year,
    int page = 1,
  }) async {
    final data = await api.get(
      '/media/search',
      queryParameters: {
        if (query?.trim().isNotEmpty == true) 'q': query!.trim(),
        if (mediaType?.isNotEmpty == true) 'media_type': mediaType,
        if (actor?.trim().isNotEmpty == true) 'actor': actor!.trim(),
        if (director?.trim().isNotEmpty == true) 'director': director!.trim(),
        if (genre?.trim().isNotEmpty == true) 'genre': genre!.trim(),
        if (year != null) 'year': year,
        'page': page,
        'page_size': AppConfig.pageSize,
      },
      deduplicate: false,
    );
    return PageResult.fromJson(_map(data), MediaSummary.fromJson);
  }

  Future<MediaDetail> mediaDetail(String mediaId) async =>
      MediaDetail.fromJson(_map(await api.get('/media/$mediaId', deduplicate: false)));

  Future<List<SeasonModel>> seasons(String mediaId) async {
    final data = await api.get('/media/$mediaId/seasons', deduplicate: false);
    return (data as List<dynamic>? ?? const [])
        .map((item) => SeasonModel.fromJson(_map(item)))
        .toList();
  }

  Future<PageResult<CommentModel>> comments(String mediaId, {int page = 1}) async {
    final data = await api.get(
      '/media/$mediaId/comments',
      queryParameters: {'page': page, 'page_size': AppConfig.pageSize},
      deduplicate: false,
    );
    return PageResult.fromJson(_map(data), CommentModel.fromJson);
  }

  Future<CommentModel> addComment(
    String mediaId, {
    required String text,
    required bool isSpoiler,
  }) async {
    final data = await api.post(
      '/media/$mediaId/comments',
      data: {'text': text.trim(), 'is_spoiler': isSpoiler},
      idempotent: true,
    );
    return CommentModel.fromJson(_map(data));
  }

  Future<CommentModel> editComment(
    String commentId, {
    required String text,
    required bool isSpoiler,
  }) async =>
      CommentModel.fromJson(
        _map(
          await api.patch(
            '/comments/$commentId',
            data: {'text': text.trim(), 'is_spoiler': isSpoiler},
          ),
        ),
      );

  Future<void> deleteComment(String commentId) => api.delete('/comments/$commentId');

  Future<void> reportComment(String commentId, String reason) => api.post(
        '/comments/$commentId/reports',
        data: {'reason': reason.trim()},
      );

  Future<UserMediaState> setWatchStatus(String mediaId, String status) async =>
      UserMediaState.fromJson(
        _map(
          await api.put(
            '/me/library/$mediaId',
            data: {'status': status},
            idempotent: true,
          ),
        ),
      );

  Future<void> removeFromLibrary(String mediaId) => api.delete('/me/library/$mediaId');

  Future<void> setFavorite(String mediaId, bool enabled) => enabled
      ? api.put('/me/favorites/$mediaId')
      : api.delete('/me/favorites/$mediaId');

  Future<RatingDistribution> rate(String mediaId, int score) async =>
      RatingDistribution.fromJson(
        _map(
          await api.put(
            '/me/ratings/$mediaId',
            data: {'score': score},
            idempotent: true,
          ),
        ),
      );

  Future<void> removeRating(String mediaId) => api.delete('/me/ratings/$mediaId');

  Future<ProgressModel> markEpisode(String episodeId, bool watched) async =>
      ProgressModel.fromJson(
        _map(
          await api.put(
            '/me/episodes/$episodeId',
            data: {'watched': watched},
            idempotent: true,
          ),
        ),
      );

  Future<PageResult<LibraryEntry>> library({String? status, int page = 1}) async {
    final data = await api.get(
      '/me/library',
      queryParameters: {
        if (status != null) 'watch_status': status,
        'page': page,
        'page_size': AppConfig.pageSize,
      },
      deduplicate: false,
    );
    return PageResult.fromJson(_map(data), LibraryEntry.fromJson);
  }

  Future<List<CustomListModel>> customLists() async {
    final data = await api.get('/me/lists', deduplicate: false);
    return (data as List<dynamic>? ?? const [])
        .map((item) => CustomListModel.fromJson(_map(item)))
        .toList();
  }

  Future<CustomListModel> customList(String id) async =>
      CustomListModel.fromJson(_map(await api.get('/me/lists/$id', deduplicate: false)));

  Future<CustomListModel> createList({
    required String name,
    String? description,
    bool isPublic = false,
  }) async =>
      CustomListModel.fromJson(
        _map(
          await api.post(
            '/me/lists',
            data: {
              'name': name.trim(),
              'description': description?.trim(),
              'is_public': isPublic,
            },
          ),
        ),
      );

  Future<CustomListModel> updateList(
    String id, {
    String? name,
    String? description,
    bool? isPublic,
  }) async =>
      CustomListModel.fromJson(
        _map(
          await api.patch(
            '/me/lists/$id',
            data: {
              if (name != null) 'name': name.trim(),
              if (description != null) 'description': description.trim(),
              if (isPublic != null) 'is_public': isPublic,
            },
          ),
        ),
      );

  Future<void> deleteList(String id) => api.delete('/me/lists/$id');
  Future<void> addListItem(String id, String mediaId) =>
      api.post('/me/lists/$id/items', data: {'media_id': mediaId});
  Future<void> removeListItem(String id, String mediaId) =>
      api.delete('/me/lists/$id/items/$mediaId');

  Future<UserStats> stats() async =>
      UserStats.fromJson(_map(await api.get('/users/me/stats', deduplicate: false)));

  Future<List<ActivityItem>> activity() async {
    final data = _map(await api.get('/users/me/activity', deduplicate: false));
    return (data['items'] as List<dynamic>? ?? const [])
        .map((item) => ActivityItem.fromJson(_map(item)))
        .toList();
  }

  Future<Map<String, dynamic>> adminStats() async =>
      _map(await api.get('/admin/stats', deduplicate: false));

  Future<PageResult<UserModel>> adminUsers({String? query, int page = 1}) async {
    final data = await api.get(
      '/admin/users',
      queryParameters: {
        if (query?.trim().isNotEmpty == true) 'q': query!.trim(),
        'page': page,
        'page_size': AppConfig.pageSize,
      },
      deduplicate: false,
    );
    return PageResult.fromJson(_map(data), UserModel.fromJson);
  }

  Future<UserModel> adminUpdateUser(String id, {String? role, bool? active}) async =>
      UserModel.fromJson(
        _map(
          await api.patch(
            '/admin/users/$id',
            data: {
              if (role != null) 'role': role,
              if (active != null) 'is_active': active,
            },
          ),
        ),
      );

  Future<List<Map<String, dynamic>>> adminReports() async {
    final data = await api.get('/admin/reports', deduplicate: false);
    return (data as List<dynamic>? ?? const []).map(_map).toList();
  }

  Future<void> resolveReport(String id, String status, {String? note}) => api.patch(
        '/admin/reports/$id',
        data: {'status': status, 'resolution_note': note},
      );

  Future<void> adminDeleteComment(String id) => api.delete('/admin/comments/$id');

  Future<List<MediaSummary>> adminMedia() async {
    final data = await api.get('/admin/media', deduplicate: false);
    return (data as List<dynamic>? ?? const [])
        .map((item) => MediaSummary.fromJson(_map(item)))
        .toList();
  }

  Future<MediaSummary> adminUpdateMedia(String mediaId, Map<String, dynamic> changes) async =>
      MediaSummary.fromJson(
        _map(await api.patch('/admin/media/$mediaId', data: changes)),
      );

  Future<void> adminRefreshMedia(String mediaId) => api.post('/admin/media/$mediaId/refresh');
  Future<void> adminDeleteMedia(String mediaId) => api.delete('/admin/media/$mediaId');
}
