import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/api_constants.dart';

/// Quản lý cấu hình Dio Client cho toàn bộ ứng dụng
class DioClient {
  final Dio dio;

  DioClient({Dio? customDio, String? baseUrl})
      : dio = customDio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl ?? ApiConstants.defaultBaseUrl,
                connectTimeout: ApiConstants.connectTimeout,
                receiveTimeout: ApiConstants.receiveTimeout,
                headers: {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                },
              ),
            ) {
    if (kDebugMode) {
      dio.interceptors.add(
        LogInterceptor(
          requestBody: true,
          responseBody: true,
          requestHeader: false,
          responseHeader: false,
        ),
      );
    }
  }

  void updateBaseUrl(String newBaseUrl) {
    dio.options.baseUrl = newBaseUrl;
  }
}
