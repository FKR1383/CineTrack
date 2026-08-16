import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:sqflite/sqflite.dart';

import '../config/app_config.dart';
import '../errors/api_exception.dart';
import '../storage/local_database.dart';

class TmdbClient {
  TmdbClient(this.localDatabase)
      : _dio = Dio(
          BaseOptions(
            baseUrl: AppConfig.tmdbBaseUrl,
            connectTimeout: const Duration(seconds: AppConfig.requestTimeoutSeconds),
            receiveTimeout: const Duration(seconds: AppConfig.requestTimeoutSeconds),
            sendTimeout: const Duration(seconds: AppConfig.requestTimeoutSeconds),
            headers: {
              'Authorization': 'Bearer ${AppConfig.tmdbReadAccessToken}',
              'Accept': 'application/json',
            },
          ),
        );

  final LocalDatabase localDatabase;
  final Dio _dio;
  final Map<String, Future<dynamic>> _inflight = <String, Future<dynamic>>{};

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Duration? cacheFor,
    bool forceRefresh = false,
  }) {
    final query = <String, dynamic>{
      'language': AppConfig.tmdbLanguage,
      ...?queryParameters,
    };
    final key = _cacheKey(path, query);
    final existing = _inflight[key];
    if (existing != null) return existing;
    final future = _getInternal(
      path,
      queryParameters: query,
      cacheKey: key,
      cacheFor: cacheFor,
      forceRefresh: forceRefresh,
    );
    _inflight[key] = future;
    return future.whenComplete(() => _inflight.remove(key));
  }

  Future<dynamic> _getInternal(
    String path, {
    required Map<String, dynamic> queryParameters,
    required String cacheKey,
    Duration? cacheFor,
    required bool forceRefresh,
  }) async {
    Map<String, dynamic>? cached;
    if (cacheFor != null) {
      cached = await _readCache(cacheKey);
      if (!forceRefresh && cached != null) {
        final fetchedAt = DateTime.tryParse(cached['fetched_at']?.toString() ?? '');
        if (fetchedAt != null && DateTime.now().difference(fetchedAt.toLocal()) <= cacheFor) {
          return jsonDecode(cached['payload_json'].toString());
        }
      }
    }

    try {
      final response = await _dio.get<dynamic>(path, queryParameters: queryParameters);
      final data = response.data;
      if (cacheFor != null) await _writeCache(cacheKey, data);
      return data;
    } on DioException catch (error) {
      if (cached != null) {
        // Stale cache keeps the simple model useful during temporary provider/network failures.
        return jsonDecode(cached['payload_json'].toString());
      }
      throw ApiException.fromDio(error);
    }
  }

  Future<Map<String, dynamic>?> _readCache(String key) async {
    final db = await localDatabase.database;
    final rows = await db.query('api_cache', where: 'cache_key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> _writeCache(String key, dynamic payload) async {
    final db = await localDatabase.database;
    await db.insert(
      'api_cache',
      {
        'cache_key': key,
        'payload_json': jsonEncode(payload),
        'fetched_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  String _cacheKey(String path, Map<String, dynamic> query) {
    final keys = query.keys.toList()..sort();
    final pairs = keys.map((key) => '$key=${query[key]}').join('&');
    return '$path?$pairs';
  }

  static String posterUrl(String? posterPath, {String size = 'w500'}) {
    if (posterPath == null || posterPath.isEmpty) return '';
    return '${AppConfig.tmdbImageBaseUrl}/$size$posterPath';
  }
}
