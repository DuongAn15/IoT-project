import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/station_info.dart';

/// Lưu và đọc danh sách trạm (catalogue) cục bộ để fallback khi mất mạng.
class StationCatalogueStorage {
  final String fileName;
  final String? customDirectoryPath;

  StationCatalogueStorage({
    this.fileName = 'station_catalogue.json',
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

  Future<void> saveCatalogue(List<StationInfo> stations) async {
    try {
      final file = await _getFile();
      final payload = jsonEncode(stations.map((s) => s.toJson()).toList());
      await file.writeAsString(payload, flush: true);
    } catch (e) {
      dev.log('Lỗi ghi station_catalogue.json: $e');
    }
  }

  Future<List<StationInfo>> readCatalogue() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];
      final raw = jsonDecode(content) as List<dynamic>;
      return raw
          .whereType<Map<String, dynamic>>()
          .map(StationInfo.fromJson)
          .where((s) => s.deviceId.isNotEmpty)
          .toList();
    } catch (e) {
      dev.log('Lỗi đọc station_catalogue.json: $e');
      return [];
    }
  }
}
