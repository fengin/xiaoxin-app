import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../utils/logger.dart';

/// 后台服务管理器（单例）
/// 负责管理 Android 前台服务，保持语音交互在后台运行
@pragma('vm:entry-point')
class BackgroundServiceManager {
  static final BackgroundServiceManager instance = BackgroundServiceManager._();
  BackgroundServiceManager._();

  final FlutterBackgroundService _service = FlutterBackgroundService();

  bool _isInitialized = false;

  /// 初始化后台服务
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      AppLogger.i('Initializing background service...');

      // 仅在 Android 上配置通知通道
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'xiaoxin_voice_service', // id
        '小新语音服务', // title
        description: '保持语音服务在后台运行', // description
        importance: Importance.low, // importance must be at low or higher level
      );

      final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
          FlutterLocalNotificationsPlugin();

      if (Platform.isAndroid) {
        await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(channel);
      }

      await _service.configure(
        androidConfiguration: AndroidConfiguration(
          // 这是后台服务的入口点
          onStart: onStart,

          // 自动启动服务
          autoStart: false,

          // 是否为前台服务
          isForegroundMode: true,

          // 通知渠道 ID (必须与上面创建的一致)
          notificationChannelId: 'xiaoxin_voice_service',

          // 初始通知标题
          initialNotificationTitle: '小新语音服务',

          // 初始通知内容
          initialNotificationContent: '语音服务运行中',

          // 前台服务类型（Android 14+）
          foregroundServiceTypes: [AndroidForegroundType.microphone],
        ),
        iosConfiguration: IosConfiguration(
          // iOS 不需要后台服务，仅前台运行
          autoStart: false,
          onForeground: onStart,
          onBackground: onIosBackground,
        ),
      );

      _isInitialized = true;
      AppLogger.i('Background service initialized successfully');
      return true;
    } catch (e) {
      AppLogger.e('Failed to initialize background service', e);
      return false;
    }
  }

  /// 启动后台服务
  Future<bool> start() async {
    if (!_isInitialized) {
      AppLogger.e('Background service not initialized');
      return false;
    }

    if (await _service.isRunning()) {
      AppLogger.w('Background service already running');
      return true;
    }

    try {
      AppLogger.i('Starting background service...');
      final success = await _service.startService();
      if (success) {
        AppLogger.i('Background service started command sent');
      } else {
        AppLogger.e('Failed to start background service');
      }
      return success;
    } catch (e) {
      AppLogger.e('Error starting background service', e);
      return false;
    }
  }

  /// 停止后台服务
  Future<void> stop() async {
    if (!await _service.isRunning()) return;

    try {
      AppLogger.i('Stopping background service...');
      _service.invoke('stopService');
      AppLogger.i('Background service stop command sent');
    } catch (e) {
      AppLogger.e('Error stopping background service', e);
    }
  }

  // ==================== 静态服务方法 ====================

  /// 后台服务入口点
  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    // 仅在 Android 平台执行
    DartPluginRegistrant.ensureInitialized();

    // 必须再次初始化 FlutterLocalNotificationsPlugin，因为这是在一个新的 isolate
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();
    
    // 初始化通知插件，使用 ic_launcher 作为默认图标
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);

    if (service is AndroidServiceInstance) {
      service.on('setAsForeground').listen((event) {
        service.setAsForegroundService();
      });

      service.on('setAsBackground').listen((event) {
        service.setAsBackgroundService();
      });
    }

    service.on('stopService').listen((event) {
      service.stopSelf();
    });
    
    // 显示初始通知，确保 startForeground 被正确调用
    if (service is AndroidServiceInstance) {
        if (await service.isForegroundService()) {
            flutterLocalNotificationsPlugin.show(
                888,
                '小新语音服务',
                '语音服务运行中',
                const NotificationDetails(
                    android: AndroidNotificationDetails(
                        'xiaoxin_voice_service',
                        '小新语音服务',
                        icon: 'ic_launcher',
                        ongoing: true,
                    ),
                ),
            );
        }
    }

    AppLogger.i('Background service instance started');
  }

  /// iOS 后台处理（iOS 不支持真正的后台服务）
  @pragma('vm:entry-point')
  static bool onIosBackground(ServiceInstance service) {
    return true;
  }
}
