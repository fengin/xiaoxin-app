/// XiaoXin APP - 权限管理
library;

import 'package:permission_handler/permission_handler.dart';
import '../../utils/logger.dart';

/// 权限管理服务
class PermissionService {
  PermissionService._();

  static final PermissionService instance = PermissionService._();

  /// 检查并请求麦克风权限
  Future<bool> requestMicrophonePermission() async {
    var status = await Permission.microphone.status;

    if (status.isGranted) {
      AppLogger.i('Microphone permission already granted');
      return true;
    }

    if (status.isDenied) {
      status = await Permission.microphone.request();
      if (status.isGranted) {
        AppLogger.i('Microphone permission granted');
        return true;
      }
    }

    if (status.isPermanentlyDenied) {
      AppLogger.w('Microphone permission permanently denied');
      // 可以提示用户去设置页面开启
      await openAppSettings();
      return false;
    }

    AppLogger.e('Microphone permission denied');
    return false;
  }

  /// 检查并请求通知权限
  Future<bool> requestNotificationPermission() async {
    var status = await Permission.notification.status;

    if (status.isGranted) {
      AppLogger.i('Notification permission already granted');
      return true;
    }

    if (status.isDenied) {
      status = await Permission.notification.request();
      if (status.isGranted) {
        AppLogger.i('Notification permission granted');
        return true;
      }
    }

    AppLogger.w('Notification permission not granted');
    return false;
  }

  /// 检查所有必要权限
  Future<bool> checkAllPermissions() async {
    final micPermission = await Permission.microphone.status;
    return micPermission.isGranted;
  }

  /// 请求所有必要权限
  Future<bool> requestAllPermissions() async {
    final micGranted = await requestMicrophonePermission();
    await requestNotificationPermission(); // 通知权限不强制要求

    return micGranted;
  }
}
