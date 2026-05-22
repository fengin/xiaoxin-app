/// XiaoXin APP - 日志工具类
library;

import 'package:logger/logger.dart';

/// 应用日志单例
class AppLogger {
  static final Logger _logger = Logger(
    level: Level.info, // 只显示 Info 及以上级别
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 5,
      lineLength: 80,
      colors: true,
      printEmojis: true,
      dateTimeFormat: (time) => 
          '${time.hour.toString().padLeft(2, '0')}:'
          '${time.minute.toString().padLeft(2, '0')}:'
          '${time.second.toString().padLeft(2, '0')}',
    ),
  );

  AppLogger._();

  /// Debug 级别日志
  static void d(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.d(message, error: error, stackTrace: stackTrace);
  }

  /// Info 级别日志
  static void i(String message, [dynamic error, StackTrace? stackTrace]) {
   _logger.i(message, error: error, stackTrace: stackTrace);
  }

  /// Warning 级别日志
  static void w(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.w(message, error: error, stackTrace: stackTrace);
  }

  /// Error 级别日志
  static void e(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.e(message, error: error, stackTrace: stackTrace);
  }

  /// Fatal 级别日志
  static void f(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.f(message, error: error, stackTrace: stackTrace);
  }
}
