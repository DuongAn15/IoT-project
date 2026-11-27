import '../../core/constants/api_constants.dart';

class StationInfo {
  final String deviceId;
  final String name;
  final String? mac;
  final String? location;

  const StationInfo({
    required this.deviceId,
    required this.name,
    this.mac,
    this.location,
  });

  factory StationInfo.fromJson(Map<String, dynamic> json) {
    final id = (json['device_id'] as String? ?? '').trim();
    final rawName = (json['name'] as String? ?? '').trim();
    final rawLocation = (json['location'] as String? ?? '').trim();
    return StationInfo(
      deviceId: id,
      name: rawName.isNotEmpty
          ? rawName
          : (ApiConstants.deviceStationMap[id] ?? id),
      mac: json['mac'] as String?,
      location: rawLocation.isNotEmpty
          ? rawLocation
          : ApiConstants.stationLocationMap[id],
    );
  }

  Map<String, dynamic> toJson() => {
    'device_id': deviceId,
    'name': name,
    if (mac != null) 'mac': mac,
    if (location != null) 'location': location,
  };

  static List<StationInfo> fallbackCatalogue() {
    return ApiConstants.deviceStationMap.entries
        .map(
          (e) => StationInfo(
            deviceId: e.key,
            name: e.value,
            location: ApiConstants.stationLocationMap[e.key],
          ),
        )
        .toList();
  }
}
