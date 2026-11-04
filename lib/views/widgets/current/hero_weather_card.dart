import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/utils/weather_unit_helper.dart';
import '../../../data/models/weather_current_model.dart';

/// Thẻ Anh Hùng Thời Tiết Hợp Nhất (Unified Hero Weather Card)
/// Tích hợp Cutscene hoạt ảnh thời tiết nền động:
/// - Khi có mưa (rainfall > 0): Cutscene bầu trời u ám với các vệt mưa rơi nghiêng sống động.
/// - Khi không mưa (rainfall == 0): Cutscene bầu trời trong xanh với vầng mặt trời tỏa nắng ấm và đốm sáng lơ lửng.
class HeroWeatherCard extends StatefulWidget {
  final WeatherCurrentModel current;
  final double? minTemp;
  final double? maxTemp;

  const HeroWeatherCard({
    super.key,
    required this.current,
    this.minTemp,
    this.maxTemp,
  });

  @override
  State<HeroWeatherCard> createState() => _HeroWeatherCardState();
}

class _HeroWeatherCardState extends State<HeroWeatherCard>
    with TickerProviderStateMixin {
  AnimationController? _rainController;
  AnimationController? _sunController;
  late final List<RainParticle> _rainParticles;
  late final List<SunFleck> _sunFlecks;

  void _ensureControllers() {
    _rainController ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();

    _sunController ??= AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
  }

  @override
  void initState() {
    super.initState();
    _ensureControllers();

    // Khởi tạo các hạt mưa với seed cố định để đảm bảo hiệu năng và tính ổn định
    final rand = math.Random(42);
    _rainParticles = List.generate(42, (i) {
      return RainParticle(
        x: rand.nextDouble(),
        speed: 1.2 + rand.nextDouble() * 1.6,
        length: 12.0 + rand.nextDouble() * 14.0,
        opacity: 0.25 + rand.nextDouble() * 0.45,
        initialOffset: rand.nextDouble(),
      );
    });

    // Khởi tạo các đốm nắng lung linh
    _sunFlecks = List.generate(7, (i) {
      return SunFleck(
        x: 0.15 + rand.nextDouble() * 0.75,
        y: 0.15 + rand.nextDouble() * 0.7,
        radius: 1.5 + rand.nextDouble() * 2.5,
        speed: 0.6 + rand.nextDouble() * 0.8,
        phase: rand.nextDouble() * math.pi * 2,
      );
    });
  }

  @override
  void dispose() {
    _rainController?.dispose();
    _sunController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _ensureControllers();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isRaining = widget.current.rainfall > 0;

    final rainCtrl = _rainController!;
    final sunCtrl = _sunController!;

    // Gradient nền bầu trời thích ứng theo thời tiết
    final backgroundGradient = isRaining
        ? (isDark
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF0D1B2A)],
              )
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1E3A5F), Color(0xFF28527A), Color(0xFF14283F)],
              ))
        : (isDark
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0C4A6E), Color(0xFF075985), Color(0xFF1E3A8A)],
              )
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0284C7), Color(0xFF0EA5E9), Color(0xFFF59E0B)],
              ));

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppDimensions.radiusXl),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : (isRaining ? const Color(0xFF1E3A5F) : AppColors.primaryLight))
                .withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppDimensions.radiusXl),
        child: Stack(
          children: [
            // 1. Lớp nền Gradient bầu trời
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: backgroundGradient,
                ),
              ),
            ),

            // 2. Lớp Hoạt ảnh Cutscene (Mưa rơi hoặc Mặt trời nắng ấm)
            Positioned.fill(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: isRaining ? rainCtrl : sunCtrl,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: isRaining
                          ? RainCutscenePainter(
                              progress: rainCtrl.value,
                              particles: _rainParticles,
                            )
                          : SunnyCutscenePainter(
                              progress: sunCtrl.value,
                              flecks: _sunFlecks,
                            ),
                    );
                  },
                ),
              ),
            ),

            // 3. Lớp phủ mờ bảo vệ tương phản nội dung chữ
            Positioned.fill(
              child: ColoredBox(
                color: isRaining
                    ? Colors.black.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.05),
              ),
            ),

            // 4. Lớp Nội dung thông tin thời tiết
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimensions.spaceMd,
                vertical: AppDimensions.spaceLg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Nhiệt độ lớn ở trung tâm card & Thấp / Cao ngay dưới cùng dòng
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
                    child: Column(
                      children: [
                        // Số nhiệt độ lớn ở chính giữa
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              widget.current.temperature.toStringAsFixed(1),
                              style: theme.textTheme.displayLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 68,
                                letterSpacing: -1.5,
                                shadows: const [
                                  Shadow(
                                    color: Colors.black26,
                                    offset: Offset(0, 2),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '°C',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontWeight: FontWeight.w600,
                                fontSize: 28,
                                shadows: const [
                                  Shadow(
                                    color: Colors.black26,
                                    offset: Offset(0, 2),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        // Thấp và Cao nằm ngay dưới nhiệt độ, cùng một dòng cách nhau một khoảng
                        if (widget.minTemp != null && widget.maxTemp != null)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Thấp: ${widget.minTemp!.toStringAsFixed(1)}°',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontWeight: FontWeight.w500,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(width: AppDimensions.spaceXl),
                              Text(
                                'Cao: ${widget.maxTemp!.toStringAsFixed(1)}°',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontWeight: FontWeight.w500,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spaceLg),

                  // Khối 3 chỉ số cảm biến (Độ ẩm, Lượng mưa, Tốc độ gió) trong khung kính mờ
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Độ ẩm
                        _buildMetricColumn(
                          context: context,
                          icon: WeatherMetricType.humidity.icon,
                          label: 'Độ ẩm',
                          value: '${widget.current.humidity.toStringAsFixed(0)}%',
                          subText: WeatherUnitHelper.getHumidityAssessment(widget.current.humidity),
                        ),
                        Container(
                          width: 1,
                          height: 44,
                          color: Colors.white.withValues(alpha: 0.18),
                        ),

                        // Lượng mưa
                        _buildMetricColumn(
                          context: context,
                          icon: WeatherMetricType.rainfall.icon,
                          label: 'Lượng mưa',
                          value: '${widget.current.rainfall.toStringAsFixed(1)} mm',
                          subText: WeatherUnitHelper.getRainfallAssessment(widget.current.rainfall),
                        ),
                        Container(
                          width: 1,
                          height: 44,
                          color: Colors.white.withValues(alpha: 0.18),
                        ),

                        // Tốc độ gió
                        _buildMetricColumn(
                          context: context,
                          icon: WeatherMetricType.windSpeed.icon,
                          label: 'Tốc độ gió',
                          value: '${widget.current.windSpeed.toStringAsFixed(1)} km/h',
                          subText: WeatherUnitHelper.getWindAssessment(widget.current.windSpeed),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricColumn({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    required String subText,
  }) {
    final theme = Theme.of(context);

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 13,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              subText,
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Mô tả một hạt mưa rơi
class RainParticle {
  final double x;
  final double speed;
  final double length;
  final double opacity;
  final double initialOffset;

  const RainParticle({
    required this.x,
    required this.speed,
    required this.length,
    required this.opacity,
    required this.initialOffset,
  });
}

/// CustomPainter vẽ vệt mưa rơi nghiêng sống động
class RainCutscenePainter extends CustomPainter {
  final double progress;
  final List<RainParticle> particles;

  RainCutscenePainter({
    required this.progress,
    required this.particles,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final paint = Paint()
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;

    for (final p in particles) {
      final yOffset = ((progress * p.speed + p.initialOffset) % 1.0) * (size.height + p.length * 2) - p.length;
      final xOffset = p.x * size.width - (yOffset * 0.15); // Hơi nghiêng nhẹ theo chiều gió

      paint.color = Colors.white.withValues(alpha: p.opacity);
      canvas.drawLine(
        Offset(xOffset, yOffset),
        Offset(xOffset - p.length * 0.15, yOffset + p.length),
        paint,
      );
    }

    // Đám mây mờ mềm mại trên đỉnh card tạo không gian u ám mưa giông (Dùng RadialGradient thay vì MaskFilter.blur để bảo đảm an toàn trên mọi GPU)
    final cloudPaint1 = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF64748B).withValues(alpha: 0.22),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: Offset(size.width * 0.25, 0), radius: 65));
    canvas.drawCircle(Offset(size.width * 0.25, 0), 65, cloudPaint1);

    final cloudPaint2 = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF64748B).withValues(alpha: 0.20),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: Offset(size.width * 0.72, 0), radius: 75));
    canvas.drawCircle(Offset(size.width * 0.72, 0), 75, cloudPaint2);
  }

  @override
  bool shouldRepaint(covariant RainCutscenePainter oldDelegate) => true;
}

/// Mô tả một đốm nắng lung linh
class SunFleck {
  final double x;
  final double y;
  final double radius;
  final double speed;
  final double phase;

  const SunFleck({
    required this.x,
    required this.y,
    required this.radius,
    required this.speed,
    required this.phase,
  });
}

/// CustomPainter vẽ mặt trời tỏa hào quang nắng ấm và các đốm sáng lơ lửng
class SunnyCutscenePainter extends CustomPainter {
  final double progress;
  final List<SunFleck> flecks;

  SunnyCutscenePainter({
    required this.progress,
    required this.flecks,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final sunCenter = Offset(size.width * 0.85, size.height * 0.22);

    // 1. Quầng hào quang rộng (Outer Warm Glow tỏa ánh sáng nhịp thở nhẹ)
    final pulse = math.sin(progress * 2 * math.pi);
    final outerRadius = math.max(10.0, 88.0 + 8.0 * pulse);
    final outerPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFF59E0B).withValues(alpha: 0.32),
          const Color(0xFFFBBF24).withValues(alpha: 0.14),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: sunCenter, radius: outerRadius));
    canvas.drawCircle(sunCenter, outerRadius, outerPaint);

    // 2. Các tia nắng mảnh xoay tròn chầm chậm quanh tâm (Sun Rays)
    final rayPaint = Paint()
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.22);
    final angleBase = progress * 2 * math.pi;
    for (int i = 0; i < 8; i++) {
      final angle = angleBase + (i * math.pi / 4);
      final rayStart = sunCenter + Offset(math.cos(angle) * 30, math.sin(angle) * 30);
      final rayEnd = sunCenter + Offset(math.cos(angle) * 46, math.sin(angle) * 46);
      canvas.drawLine(rayStart, rayEnd, rayPaint);
    }

    // 3. Quả cầu mặt trời ấm áp ở trung tâm (Inner Sun Core)
    final sunPaint = Paint()
      ..shader = RadialGradient(
        colors: const [
          Colors.white,
          Color(0xFFFEF08A),
          Color(0xFFF59E0B),
        ],
        stops: const [0.0, 0.4, 1.0],
      ).createShader(Rect.fromCircle(center: sunCenter, radius: 25));
    canvas.drawCircle(sunCenter, 23, sunPaint);

    // 4. Các đốm bụi nắng vàng li ti lơ lửng (Floating Sun Flecks)
    final fleckPaint = Paint()..style = PaintingStyle.fill;
    for (final f in flecks) {
      final curY = (f.y + math.sin(progress * 2 * math.pi * f.speed + f.phase) * 0.08) * size.height;
      final curX = (f.x + math.cos(progress * 2 * math.pi * f.speed + f.phase) * 0.04) * size.width;
      final opacity = (0.2 + 0.15 * math.sin(progress * 2 * math.pi * f.speed + f.phase)).clamp(0.05, 0.45);
      fleckPaint.color = Colors.white.withValues(alpha: opacity);
      canvas.drawCircle(Offset(curX, curY), f.radius, fleckPaint);
    }
  }

  @override
  bool shouldRepaint(covariant SunnyCutscenePainter oldDelegate) => true;
}
