import 'package:dio/dio.dart';

/// Lớp ngoại lệ cơ sở cho tầng mạng HTTP
abstract class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Lỗi kết nối, timeout hoặc không có internet
class NetworkException extends ApiException {
  const NetworkException(super.message, {super.statusCode});
}

/// Lỗi nghiệp vụ hoặc dữ liệu gửi lên không hợp lệ (400 Bad Request)
class ValidationException extends ApiException {
  final List<String> errors;

  const ValidationException(
    super.message, {
    super.statusCode = 400,
    this.errors = const [],
  });
}

/// Lỗi phía máy chủ (5xx)
class ServerException extends ApiException {
  const ServerException(super.message, {super.statusCode = 500});
}

/// Tiện ích parse lỗi từ DioException
ApiException handleDioError(DioException error) {
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return const NetworkException('Hết thời gian chờ phản hồi từ máy chủ trạm.');
    case DioExceptionType.connectionError:
      return const NetworkException(
        'Không thể kết nối đến máy chủ Backend Gateway. Vui lòng kiểm tra địa chỉ IP và kết nối mạng.',
      );
    case DioExceptionType.badResponse:
      final statusCode = error.response?.statusCode;
      final responseData = error.response?.data;

      String message = 'Đã có lỗi xảy ra ($statusCode)';
      List<String> details = [];

      if (responseData is Map<String, dynamic>) {
        final err = responseData['error'];
        if (err is Map<String, dynamic>) {
          final msg = err['message'];
          if (msg is List) {
            details = msg.map((e) => e.toString()).toList();
            message = details.join('\n');
          } else if (msg is String) {
            message = msg;
          }
        } else if (err is String) {
          message = err;
        }
      }

      if (statusCode == 400) {
        return ValidationException(message, statusCode: statusCode, errors: details);
      }
      return ServerException(message, statusCode: statusCode);
    case DioExceptionType.cancel:
      return const NetworkException('Yêu cầu đã bị hủy.');
    default:
      return NetworkException(error.message ?? 'Lỗi kết nối không xác định.');
  }
}
