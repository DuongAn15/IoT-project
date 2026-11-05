/// Envelope chuẩn cho các response thành công từ Backend Gateway
class ApiResponse<T> {
  final int statusCode;
  final T data;
  final String timestamp;

  const ApiResponse({
    required this.statusCode,
    required this.data,
    required this.timestamp,
  });

  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic dataJson) fromDataJson,
  ) {
    return ApiResponse<T>(
      statusCode: json['statusCode'] as int? ?? 200,
      data: fromDataJson(json['data']),
      timestamp: json['timestamp'] as String? ?? '',
    );
  }
}
