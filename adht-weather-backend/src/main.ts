import { NestFactory } from '@nestjs/core';
import { ValidationPipe, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { AppModule } from './app.module';
import { AllExceptionsFilter } from './common/filters/http-exception.filter';
import { TransformInterceptor } from './common/interceptors/transform.interceptor';

async function bootstrap() {
  const logger = new Logger('ADHT-Backend-Bootstrap');
  const app = await NestFactory.create(AppModule);
  app.enableShutdownHooks();

  const configService = app.get(ConfigService);
  const port = configService.get<number>('port') || 8000;
  const apiPrefix = configService.get<string>('apiPrefix') || 'api';

  // 1. CORS cho phép Flutter App & Web Dashboard gọi API
  app.enableCors({
    origin: '*',
    methods: 'GET,HEAD,PUT,PATCH,POST,DELETE,OPTIONS',
    credentials: true,
  });

  // 2. Global Prefix: /api
  app.setGlobalPrefix(apiPrefix);

  // 3. Validation Pipe tự động kiểm tra kiểu dữ liệu DTO
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      transform: true,
      forbidNonWhitelisted: false,
    }),
  );

  // 4. Global Filters & Interceptors
  app.useGlobalFilters(new AllExceptionsFilter());
  app.useGlobalInterceptors(new TransformInterceptor());

  // 5. Khởi tạo tài liệu tương tác Swagger UI (/docs)
  const swaggerConfig = new DocumentBuilder()
    .setTitle('ADHT Smart Weather Station API')
    .setDescription(
      'Hệ thống Backend Gateway & Xử lý Chuỗi Thời Gian cho Trạm quan trắc thời tiết thông minh ADHT',
    )
    .setVersion('1.0.0')
    .addTag('Telemetry', 'Tiếp nhận dữ liệu cảm biến')
    .addTag('Weather', 'Truy vấn số liệu mới nhất, lịch sử làm mịn & dự báo')
    .addTag('Devices', 'Điều khiển còi/LED & cài đặt ngưỡng trạm')
    .addTag('Notifications', 'Đăng ký nhận thông báo đẩy qua Firebase FCM')
    .build();

  const document = SwaggerModule.createDocument(app, swaggerConfig);
  SwaggerModule.setup('docs', app, document);

  // 6. Lắng nghe trên cổng PORT
  await app.listen(port, '0.0.0.0');
  logger.log(`🚀 [ADHT Backend Gateway] đang chạy trên: http://localhost:${port}/${apiPrefix}`);
  logger.log(`📚 [Swagger Documentation] truy cập tại: http://localhost:${port}/docs`);
}

bootstrap();
