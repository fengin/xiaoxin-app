/// XiaoXin APP - OTA 服务
/// 调用 OTA 接口进行设备授权和获取配置
/// 请求体格式参考 xiaozhi-esp32 的 GetSystemInfoJson()
library;

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import '../../models/ota_response.dart';
import '../settings/config_service.dart';
import '../../utils/logger.dart';
import '../../utils/constants.dart';

/// OTA 服务
class OtaService {
  OtaService._();

  static final OtaService instance = OtaService._();

  /// 最近一次 OTA 响应
  OtaResponse? _lastResponse;

  /// 设备信息缓存（避免重复查询）
  Map<String, dynamic>? _deviceInfoCache;

  /// 获取最近一次 OTA 响应
  OtaResponse? get lastResponse => _lastResponse;

  /// 是否需要激活
  bool get needsActivation => _lastResponse?.needsActivation ?? false;

  /// 激活码
  String? get activationCode => _lastResponse?.activation?.code;

  /// 激活提示信息
  String? get activationMessage => _lastResponse?.activation?.message;

  /// 是否已激活
  bool get isActivated => _lastResponse?.isActivated ?? false;

  /// 调用 OTA 接口检查版本并获取配置
  Future<OtaResponse?> checkVersion() async {
    try {
      final config = ConfigService.instance.config;
      final envConfig = config.environments.currentConfig;
      final otaUrl = envConfig.otaUrl;

      if (otaUrl.isEmpty) {
        AppLogger.w('OTA URL is empty');
        return null;
      }

      AppLogger.i('Checking OTA: $otaUrl');

      // 构建请求头
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Device-Id': config.deviceId,
        'Client-Id': config.clientId,
        'User-Agent': _buildUserAgent(),
        'Activation-Version': '1',
      };

      // 构建请求体（设备信息，与 xiaozhi-esp32 格式保持一致）
      final body = jsonEncode(await _buildSystemInfo(config));

      // 发送 POST 请求
      final response = await http
          .post(
            Uri.parse(otaUrl),
            headers: headers,
            body: body,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        AppLogger.e('OTA request failed: ${response.statusCode}');
        return null;
      }

      // 解析响应
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      _lastResponse = OtaResponse.fromJson(json);

      AppLogger.i('OTA response: needsActivation=${_lastResponse!.needsActivation}, '
          'isActivated=${_lastResponse!.isActivated}');

      // 如果已激活，保存 OTA 返回的配置
      if (_lastResponse!.isActivated) {
        await _saveOtaConfig(_lastResponse!);
      }

      return _lastResponse;
    } catch (e, stackTrace) {
      AppLogger.e('OTA check failed', e, stackTrace);
      return null;
    }
  }

  /// 构建系统信息（与 xiaozhi-esp32 的 GetSystemInfoJson 格式对齐）
  ///
  /// 服务端 DeviceController.java 解析以下字段：
  /// - `mac_address` / `mac`  → 备用 Device-Id
  /// - `chip_model_name`      → 芯片/硬件型号
  /// - `application.version`  → 应用版本号
  /// - `board.type`           → 设备类型
  /// - `board.ssid`           → WiFi SSID（需位置权限，暂不上报）
  Future<Map<String, dynamic>> _buildSystemInfo(AppConfig config) async {
    // 获取设备信息（带缓存）
    final deviceInfo = await _getDeviceInfo();

    // 对授权码进行 SHA-256 加密（防止明文传输）
    String? hashedAuthCode;
    if (config.authCode.isNotEmpty) {
      hashedAuthCode = sha256.convert(utf8.encode(config.authCode)).toString();
    }

    return {
      // 顶层字段
      'mac_address': config.deviceId,
      'chip_model_name': deviceInfo['chipModel'],
      'auth_code': hashedAuthCode, // 加密后的授权码

      // 应用信息（嵌套结构，服务端解析 application.version）
      'application': {
        'name': AppConstants.appName,
        'version': AppConstants.appVersion,
      },

      // 开发板/设备信息（嵌套结构，服务端解析 board.type 和 board.ssid）
      'board': {
        'type': deviceInfo['boardType'],
        // 优先使用用户自定义的设备名，未设置则使用硬件型号名称
        'name': config.customDeviceName ?? deviceInfo['boardName'],
        // 'ssid': WiFi SSID 需要位置权限，暂不上报
      },
    };
  }

  /// 获取设备硬件信息（带缓存，避免重复查询）
  Future<Map<String, dynamic>> _getDeviceInfo() async {
    if (_deviceInfoCache != null) return _deviceInfoCache!;

    final deviceInfoPlugin = DeviceInfoPlugin();

    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfoPlugin.androidInfo;
        _deviceInfoCache = {
          // 芯片型号：如 "Qualcomm SM8250" 或 "MT6765"
          'chipModel': androidInfo.hardware,
          // 设备类型
          'boardType': 'android',
          // 设备名称：如 "Pixel 6" 或 "Redmi Note 12"
          'boardName': androidInfo.model,
        };
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfoPlugin.iosInfo;
        _deviceInfoCache = {
          // 芯片型号：如 "iPhone14,2"（机型标识）
          'chipModel': iosInfo.utsname.machine,
          // 设备类型
          'boardType': 'ios',
          // 设备名称：如 "iPhone 13 Pro"
          'boardName': iosInfo.model,
        };
      } else {
        _deviceInfoCache = {
          'chipModel': 'unknown',
          'boardType': Platform.operatingSystem,
          'boardName': 'unknown',
        };
      }
    } catch (e) {
      AppLogger.w('Failed to get device info', e);
      _deviceInfoCache = {
        'chipModel': 'unknown',
        'boardType': Platform.isAndroid ? 'android' : 'ios',
        'boardName': 'unknown',
      };
    }

    AppLogger.d('Device info: $_deviceInfoCache');
    return _deviceInfoCache!;
  }

  /// 保存 OTA 返回的配置
  Future<void> _saveOtaConfig(OtaResponse response) async {
    try {
      // 保存 OTA 返回的 WebSocket 配置
      if (response.websocket?.url != null) {
        await ConfigService.instance.setOtaWsUrl(response.websocket!.url!);
      }
      if (response.h5Url != null) {
        await ConfigService.instance.setOtaH5Url(response.h5Url!);
      }

      AppLogger.i('OTA config saved');
    } catch (e) {
      AppLogger.e('Failed to save OTA config', e);
    }
  }

  /// 构建 User-Agent
  String _buildUserAgent() {
    final platform = Platform.isAndroid ? 'Android' : 'iOS';
    return 'XiaoXin/${AppConstants.appVersion} ($platform)';
  }

  /// 清除 OTA 缓存
  void clearCache() {
    _lastResponse = null;
  }
}
