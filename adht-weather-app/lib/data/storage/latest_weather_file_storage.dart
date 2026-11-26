import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/constants/api_constants.dart';
import '../models/weather_current_model.dart';

/// Quản lý việc lưu và đọc bản ghi thời tiết mới nhất (Latest) từ file cục bộ theo từng trạm
class LatestWeatherFileStorage {
  final String fileName;
  final String? customDirectoryPath;

  LatestWeatherFileStorage({
    this.fileName = ApiConstants.latestWeatherFileName,
    this.customDirectoryPath,
  });

  String _scopedFileName(String deviceId) {
    final sanitized = deviceId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    if (sanitized.isEmpty) return fileName;
    final dotIdx = fileName.lastIndexOf('.');
    if (dotIdx <= 0) return '${fileName}_$sanitized';
    return '${fileName.substring(0, dotIdx)}_$sanitized${fileName.substring(dotIdx)}';
  }

  Future<File> _getFile({String? deviceId}) async {
    String dirPath;
    if (customDirectoryPath != null) {
      dirPath = customDirectoryPath!;
    } else {
      try {
        final dir = await getApplicationDocumentsDirectory();
        dirPath = dir.path;
      } catch (_) {
        dirPath = Directory.systemTemp.path;
      }
    }
    final targetName =
        (deviceId != null && deviceId.trim().isNotEmpty) ? _scopedFileName(deviceId) : fileName;
    return File(p.join(dirPath, targetName));
  }

  /// Lưu bản ghi mới nhất vào file dạng JSON theo `stationId`
  Future<void> saveLatest(WeatherCurrentModel model) async {
    try {
      final file = await _getFile(deviceId: model.stationId);
      final jsonStr = jsonEncode(model.toMap());
      await file.writeAsString(jsonStr, flush: true);
    } catch (e) {
      dev.log('Lỗi ghi file latest weather: $e');
    }
  }

  /// Đọc bản ghi mới nhất từ file của đúng trạm (dùng khi mất mạng / offline)
  Future<WeatherCurrentModel?> readLatest({
    String deviceId = ApiConstants.defaultStationId,
  }) async {
    try {
      final file = await _getFile(deviceId: deviceId);
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final map = jsonDecode(content) as Map<String, dynamic>;
          final model = WeatherCurrentModel.fromMap(map);
          if (model.stationId != deviceId) {
            return null;
          }
          return model.copyWith(isOnline: false);
        }
      }
    } catch (e) {
      dev.log('Lỗi đọc file latest weather: $e');
    }
    return null;
  }

  /// Xóa file lưu trữ (dùng khi reset app hoặc test)
  Future<void> clear({String? deviceId}) async {
    try {
      final file = await _getFile(deviceId: deviceId);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
