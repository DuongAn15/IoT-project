import '../../core/constants/api_constants.dart';

class StationInfo {
  final String deviceId;
  final String name;
  final String? mac;
  final String timezone;

  const StationInfo({
    required this.deviceId,
    required this.name,
    this.mac,
    this.timezone = ApiConstants.defaultStationTimezone,
  });

  factory StationInfo.fromJson(Map<String, dynamic> json) {
    final id = (json['device_id'] as String? ?? '').trim();
    final rawName = (json['name'] as String? ?? '').trim();
    final rawTz = (json['timezone'] as String? ?? '').trim();
    return StationInfo(
      deviceId: id,
      name: rawName.isNotEmpty ? rawName : (ApiConstants.deviceStationMap[id] ?? id),
      mac: json['mac'] as String?,
      timezone: rawTz.isNotEmpty ? rawTz : ApiConstants.timezoneForStation(id),
    );
  }

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'name': name,
        if (mac != null) 'mac': mac,
        'timezone': timezone,
      };

  static List<StationInfo> fallbackCatalogue() {
    return ApiConstants.deviceStationMap.entries
        .map((e) => StationInfo(
              deviceId: e.key,
              name: e.value,
              timezone: ApiConstants.timezoneForStation(e.key),
            ))
        .toList();
  }
}
