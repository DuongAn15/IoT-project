/// Hệ thống khoảng cách theo chuẩn 8-Point Grid
/// Đảm bảo tính nhất quán trên mọi kích thước màn hình.
abstract class AppDimensions {
  // Spacing
  static const double space2xs = 2.0;
  static const double spaceXs = 4.0;
  static const double spaceSm = 8.0;
  static const double spaceMd = 16.0;
  static const double spaceLg = 24.0;
  static const double spaceXl = 32.0;
  static const double space2xl = 40.0;
  static const double space3xl = 48.0;

  // Border Radii
  static const double radiusXs = 4.0;
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 24.0;
  static const double radiusFull = 999.0;

  // Icon Sizes
  static const double iconSm = 16.0;
  static const double iconMd = 20.0;
  static const double iconLg = 28.0;
  static const double iconXl = 36.0;

  // Elevation / Shadow
  static const double elevationLow = 2.0;
  static const double elevationMedium = 4.0;
  static const double elevationHigh = 8.0;

  // Chart Dimensions
  static const double chartHeightDefault = 220.0;
  static const double chartHeightCompact = 160.0;
  static const double chartHeightDetailed = 280.0;
}
