import 'package:dio/dio.dart';

class ApiException implements Exception {
  const ApiException({
    required this.message,
    this.code,
    this.statusCode,
    this.detail,
    this.fields,
    this.requestId,
  });

  final String message;
  final String? code;
  final int? statusCode;
  final String? detail;
  final Map<String, dynamic>? fields;
  final String? requestId;

  factory ApiException.fromDio(DioException error) {
    final response = error.response;
    if (response?.data is Map<String, dynamic>) {
      final root = response!.data as Map<String, dynamic>;
      final data = root['error'];
      if (data is Map<String, dynamic>) {
        return ApiException(
          message: data['message']?.toString() ?? 'خطایی در ارتباط با سرور رخ داد.',
          code: data['code']?.toString(),
          statusCode: data['status_code'] as int? ?? response.statusCode,
          detail: data['detail']?.toString(),
          fields: data['fields'] is Map<String, dynamic>
              ? data['fields'] as Map<String, dynamic>
              : null,
          requestId: data['request_id']?.toString(),
        );
      }
    }
    final message = switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => 'زمان اتصال به سرور به پایان رسید.',
      DioExceptionType.connectionError =>
        'اتصال اینترنت برقرار نیست یا سرور در دسترس نیست.',
      DioExceptionType.badCertificate => 'گواهی امنیتی سرور معتبر نیست.',
      DioExceptionType.cancel => 'درخواست لغو شد.',
      _ => 'دریافت اطلاعات با خطا مواجه شد.',
    };
    return ApiException(
      message: message,
      statusCode: response?.statusCode,
      detail: error.message,
    );
  }

  @override
  String toString() => message;
}
