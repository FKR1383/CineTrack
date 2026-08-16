import 'package:dio/dio.dart';

class ApiException implements Exception {
  const ApiException({required this.message, this.code, this.statusCode, this.detail});

  final String message;
  final String? code;
  final int? statusCode;
  final String? detail;

  factory ApiException.fromDio(DioException error) {
    final response = error.response;
    String? providerMessage;
    if (response?.data is Map<String, dynamic>) {
      providerMessage = (response!.data as Map<String, dynamic>)['status_message']?.toString();
    }
    final message = switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => 'زمان دریافت اطلاعات از TMDB به پایان رسید.',
      DioExceptionType.connectionError => 'اتصال اینترنت برقرار نیست یا TMDB در دسترس نیست.',
      DioExceptionType.badCertificate => 'گواهی امنیتی سرویس اطلاعات معتبر نیست.',
      DioExceptionType.cancel => 'درخواست لغو شد.',
      DioExceptionType.badResponse when response?.statusCode == 404 => 'فیلم یا سریال موردنظر پیدا نشد.',
      DioExceptionType.badResponse when response?.statusCode == 401 => 'کلید دسترسی TMDB معتبر نیست.',
      DioExceptionType.badResponse when response?.statusCode == 429 => 'تعداد درخواست‌ها زیاد است؛ کمی بعد دوباره تلاش کنید.',
      _ => providerMessage?.isNotEmpty == true ? providerMessage! : 'دریافت اطلاعات با خطا مواجه شد.',
    };
    return ApiException(
      message: message,
      code: response?.statusCode?.toString(),
      statusCode: response?.statusCode,
      detail: error.message,
    );
  }

  @override
  String toString() => message;
}
