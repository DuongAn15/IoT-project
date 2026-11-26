import 'dart:developer' as dev;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/station_info.dart';
import '../data/storage/station_catalogue_storage.dart';
import 'device_settings_provider.dart';

final stationCatalogueStorageProvider = Provider<StationCatalogueStorage>((ref) {
  return StationCatalogueStorage();
});

final stationCatalogueProvider = FutureProvider<List<StationInfo>>((ref) async {
  final apiService = ref.watch(deviceApiServiceProvider);
  final storage = ref.watch(stationCatalogueStorageProvider);

  try {
    final remote = await apiService.fetchDevices();
    if (remote.isNotEmpty) {
      await storage.saveCatalogue(remote);
      return remote;
    }
  } catch (e) {
    dev.log('Lỗi tải station catalogue từ backend, dùng cache cục bộ: $e');
  }

  final cached = await storage.readCatalogue();
  if (cached.isNotEmpty) {
    return cached;
  }

  return StationInfo.fallbackCatalogue();
});
