import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:uuid/uuid.dart';

import '../auth/token_store.dart';
import '../config/app_config.dart';
import '../errors/api_exception.dart';

class ApiClient {
  ApiClient(this.tokenStore)
      : _dio = Dio(_options()),
        _refreshDio = Dio(_options()) {
    _configureCertificatePinning(_dio);
    _configureCertificatePinning(_refreshDio);
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await tokenStore.readAccessToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final options = error.requestOptions;
          final canRefresh = error.response?.statusCode == 401 &&
              options.extra['retried'] != true &&
              !options.path.contains('/auth/login') &&
              !options.path.contains('/auth/refresh');
          if (!canRefresh) {
            handler.next(error);
            return;
          }
          try {
            await _refreshTokens();
            final accessToken = await tokenStore.readAccessToken();
            options.extra['retried'] = true;
            options.headers['Authorization'] = 'Bearer $accessToken';
            handler.resolve(await _dio.fetch<dynamic>(options));
          } catch (_) {
            await tokenStore.clear();
            handler.next(error);
          }
        },
      ),
    );
  }

  final Dio _dio;
  final Dio _refreshDio;
  final TokenStore tokenStore;
  final Map<String, Future<dynamic>> _pendingGets = {};
  final Map<String, Uint8List> _byteCache = <String, Uint8List>{};
  final Map<String, Future<Uint8List>> _pendingBytes = <String, Future<Uint8List>>{};
  Future<void>? _refreshFuture;
  static const _uuid = Uuid();

  static BaseOptions _options() => BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: const Duration(seconds: AppConfig.requestTimeoutSeconds),
        receiveTimeout: const Duration(seconds: AppConfig.requestTimeoutSeconds),
        sendTimeout: const Duration(seconds: AppConfig.requestTimeoutSeconds),
        responseType: ResponseType.json,
        contentType: Headers.jsonContentType,
        headers: const {'Accept': 'application/json'},
      );

  static void _configureCertificatePinning(Dio dio) {
    final pin = _normalizePin(AppConfig.certificateSha256);
    if (pin.isEmpty) return;
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        // No system roots: only the explicitly pinned certificate is accepted.
        final client = HttpClient(context: SecurityContext(withTrustedRoots: false));
        client.badCertificateCallback = (certificate, _, __) {
          final fingerprint = sha256.convert(certificate.der).toString().toLowerCase();
          return fingerprint == pin;
        };
        return client;
      },
    );
  }

  static String _normalizePin(String value) =>
      value.replaceAll(':', '').replaceAll(' ', '').toLowerCase();

  Future<void> _refreshTokens() {
    final existing = _refreshFuture;
    if (existing != null) return existing;

    final future = _performTokenRefresh();
    _refreshFuture = future;
    void clearRefresh() {
      if (identical(_refreshFuture, future)) _refreshFuture = null;
    }
    future.then<void>((_) => clearRefresh(), onError: (_, __) => clearRefresh());
    return future;
  }

  Future<void> _performTokenRefresh() async {
    try {
      final refresh = await tokenStore.readRefreshToken();
      if (refresh == null || refresh.isEmpty) {
        throw const ApiException(message: 'نشست معتبری وجود ندارد.');
      }
      final response = await _refreshDio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': refresh, 'device_info': 'Flutter Android'},
      );
      final data = response.data;
      if (data == null || data['access_token'] == null || data['refresh_token'] == null) {
        throw const ApiException(message: 'پاسخ تمدید نشست معتبر نیست.');
      }
      await tokenStore.write(
        accessToken: data['access_token'].toString(),
        refreshToken: data['refresh_token'].toString(),
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool deduplicate = true,
  }) {
    final key = '$path?${jsonEncode(queryParameters ?? const {})}';
    if (deduplicate && _pendingGets.containsKey(key)) return _pendingGets[key]!;
    final future = _perform(() => _dio.get<dynamic>(path, queryParameters: queryParameters));
    if (deduplicate) {
      _pendingGets[key] = future;
      future.then<void>(
        (_) => _pendingGets.remove(key),
        onError: (_, __) => _pendingGets.remove(key),
      );
    }
    return future;
  }

  Future<Uint8List> getSameOriginBytes(String url) {
    final target = Uri.tryParse(url);
    final apiOrigin = Uri.parse(AppConfig.apiBaseUrl);
    if (target == null ||
        target.scheme != apiOrigin.scheme ||
        target.host != apiOrigin.host ||
        target.port != apiOrigin.port) {
      throw const ApiException(message: 'نشانی تصویر از میزبان مجاز نیست.');
    }
    final cached = _byteCache[url];
    if (cached != null) return Future<Uint8List>.value(cached);
    final pending = _pendingBytes[url];
    if (pending != null) return pending;

    final future = _performBytes(url);
    _pendingBytes[url] = future;
    future.then<void>(
      (bytes) {
        if (_byteCache.length >= 64) {
          _byteCache.remove(_byteCache.keys.first);
        }
        _byteCache[url] = bytes;
        _pendingBytes.remove(url);
      },
      onError: (_) {
        _pendingBytes.remove(url);
      },
    );
    return future;
  }

  Future<Uint8List> _performBytes(String url) async {
    try {
      final response = await _dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        throw const ApiException(message: 'تصویر دریافتی خالی است.');
      }
      return bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<dynamic> post(
    String path, {
    Object? data,
    bool idempotent = false,
    Options? options,
  }) {
    return _perform(
      () => _dio.post<dynamic>(
        path,
        data: data,
        options: _withIdempotency(options, idempotent),
      ),
    );
  }

  Future<dynamic> put(
    String path, {
    Object? data,
    bool idempotent = false,
    Options? options,
  }) {
    return _perform(
      () => _dio.put<dynamic>(
        path,
        data: data,
        options: _withIdempotency(options, idempotent),
      ),
    );
  }

  Future<dynamic> patch(String path, {Object? data, Options? options}) =>
      _perform(() => _dio.patch<dynamic>(path, data: data, options: options));

  Future<dynamic> delete(String path, {Object? data, Options? options}) =>
      _perform(() => _dio.delete<dynamic>(path, data: data, options: options));

  Options _withIdempotency(Options? options, bool enabled) {
    if (!enabled) return options ?? Options();
    final merged = Map<String, dynamic>.from(options?.headers ?? const {});
    merged['Idempotency-Key'] = _uuid.v4();
    return (options ?? Options()).copyWith(headers: merged);
  }

  Future<dynamic> _perform(Future<Response<dynamic>> Function() request) async {
    try {
      final response = await request();
      return response.data;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
