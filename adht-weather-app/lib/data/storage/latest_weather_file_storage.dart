import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/constants/api_constants.dart';
import '../models/weather_current_model.dart';

/// Quản lý việc lưu và đọc bản ghi thời tiết mới nhất (Latest) từ file cục bộ trên app thay vì lưu database
class LatestWeatherFileStorage {
  final String fileName;
  final String? customDirectoryPath;

  LatestWeatherFileStorage({
    this.fileName = ApiConstants.latestWeatherFileName,
    this.customDirectoryPath,
  });

  Future<File> _getFile() async {
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
    return File(p.join(dirPath, fileName));
  }

  /// Lưu bản ghi mới nhất vào file dạng JSON
  Future<void> saveLatest(WeatherCurrentModel model) async {
    try {
      final file = await _getFile();
      final jsonStr = jsonEncode(model.toMap());
      await file.writeAsString(jsonStr, flush: true);
    } catch (e) {
      dev.log('Lỗi ghi file latest weather: $e');
    }
  }

  /// Đọc bản ghi mới nhất từ file (dùng khi mất mạng / offline)
  Future<WeatherCurrentModel?> readLatest() async {
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final map = jsonDecode(content) as Map<String, dynamic>;
          final model = WeatherCurrentModel.fromMap(map);
          return model.copyWith(isOnline: false);
        }
      }
    } catch (e) {
      dev.log('Lỗi đọc file latest weather: $e');
    }
    return null;
  }

  /// Xóa file lưu trữ (dùng khi reset app hoặc test)
  Future<void> clear() async {
    try {
      final file = await _getFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
