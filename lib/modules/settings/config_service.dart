/// XiaoXin APP - 配置管理
/// 支持三套环境配置 + OTA 返回配置（按环境隔离）+ 本地手动配置
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import '../../models/audio_config.dart';
import '../../models/environment_config.dart';
import '../../utils/constants.dart';
import '../../utils/logger.dart';

/// 应用配置
class AppConfig {
  /// 设备 ID
  final String deviceId;

  /// 客户端 ID
  final String clientId;

  /// 自定义设备名称
  final String? customDeviceName;

  /// 自动激活授权码
  final String authCode;

  /// 多环境配置
  final MultiEnvironmentConfig environments;

  /// 扩展参数
  final Map<String, dynamic>? extendParams;

  /// 音频配置
  final AudioConfig audioConfig;

  const AppConfig({
    required this.deviceId,
    required this.clientId,
    this.customDeviceName,
    this.authCode = 'xiaoxin.chat',
    required this.environments,
    this.extendParams,
    this.audioConfig = const AudioConfig(),
  });

  /// 获取有效的 WebSocket 地址（从当前环境配置中获取）
  String? get effectiveWsUrl => environments.currentConfig.effectiveWsUrl;

  /// 获取有效的 H5 地址（从当前环境配置中获取，有默认值）
  String? get effectiveH5Url {
    final envH5 = environments.currentConfig.effectiveH5Url;
    if (envH5 != null && envH5.isNotEmpty) {
      return envH5;
    }
    // 默认使用本地 Demo
    return AppConstants.defaultH5DemoUrl;
  }

  /// 获取当前 OTA 地址
  String get otaUrl => environments.currentConfig.otaUrl;

  /// 获取当前环境
  Environment get currentEnvironment => environments.current;

  /// 是否有有效的 WebSocket 配置
  bool get hasValidWsConfig {
    final url = effectiveWsUrl;
    return url != null && url.isNotEmpty;
  }

  AppConfig copyWith({
    String? deviceId,
    String? clientId,
    String? customDeviceName,
    String? authCode,
    MultiEnvironmentConfig? environments,
    Map<String, dynamic>? extendParams,
    AudioConfig? audioConfig,
    bool clearCustomDeviceName = false,
  }) {
    return AppConfig(
      deviceId: deviceId ?? this.deviceId,
      clientId: clientId ?? this.clientId,
      customDeviceName: clearCustomDeviceName ? null : (customDeviceName ?? this.customDeviceName),
      authCode: authCode ?? this.authCode,
      environments: environments ?? this.environments,
      extendParams: extendParams ?? this.extendParams,
      audioConfig: audioConfig ?? this.audioConfig,
    );
  }
}

/// 配置管理服务
class ConfigService {
  ConfigService._();

  static final ConfigService instance = ConfigService._();

  SharedPreferences? _prefs;
  AppConfig? _config;

  /// 初始化配置服务
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadConfig();
    AppLogger.i('ConfigService initialized');
  }

  /// 加载配置
  Future<void> _loadConfig() async {
    final prefs = _prefs!;

    // 获取或生成设备 ID（MAC 地址格式以兼容服务端验证）
    String deviceId = prefs.getString(StorageKeys.deviceId) ?? '';
    if (deviceId.isEmpty || !_isValidMacFormat(deviceId)) {
      // 使用硬件 ID 生成稳定的 MAC 地址
      deviceId = await _generateMacAddressFromHardware();
      await prefs.setString(StorageKeys.deviceId, deviceId);
      AppLogger.i('Generated device ID from hardware: $deviceId');
    }

    // 获取或生成客户端 ID（保持 UUID 格式）
    String clientId = prefs.getString(StorageKeys.clientId) ?? '';
    if (clientId.isEmpty) {
      clientId = const Uuid().v4();
      await prefs.setString(StorageKeys.clientId, clientId);
      AppLogger.i('Generated new client ID: $clientId');
    }

    // 获取自定义设备名称
    final String? customDeviceName = prefs.getString(StorageKeys.customDeviceName);

    // 获取自动激活授权码
    final String authCode = prefs.getString(StorageKeys.authCode) ?? 'xiaoxin.chat';

    // 加载环境配置
    MultiEnvironmentConfig environments;
    final envJson = prefs.getString(StorageKeys.environments);
    if (envJson != null) {
      try {
        environments = MultiEnvironmentConfig.fromJson(
          jsonDecode(envJson) as Map<String, dynamic>,
        );
      } catch (e) {
        AppLogger.w('Failed to parse environments config, using default');
        environments = MultiEnvironmentConfig.defaultConfig();
      }
    } else {
      environments = MultiEnvironmentConfig.defaultConfig();
    }

    // 加载音频配置
    AudioConfig audioConfig;
    final audioJson = prefs.getString(StorageKeys.audioConfig);
    if (audioJson != null) {
      try {
        audioConfig = AudioConfig.fromJson(
          jsonDecode(audioJson) as Map<String, dynamic>,
        );
        AppLogger.i('Audio config loaded: $audioConfig');
      } catch (e) {
        AppLogger.w('Failed to parse audio config, using default');
        audioConfig = AudioConfig.defaultConfig();
      }
    } else {
      // 首次加载，使用默认配置，但根据设备自适应
      audioConfig = _getAdaptiveDefaultAudioConfig();
    }

    // 加载扩展参数
    Map<String, dynamic>? extendParams;
    final extendJson = prefs.getString(StorageKeys.extendParams);
    if (extendJson != null) {
      try {
        extendParams = jsonDecode(extendJson) as Map<String, dynamic>;
        AppLogger.i('Extend params loaded: $extendParams');
      } catch (e) {
        AppLogger.w('Failed to parse extend params, ignoring');
      }
    }

    _config = AppConfig(
      deviceId: deviceId,
      clientId: clientId,
      customDeviceName: customDeviceName,
      authCode: authCode,
      environments: environments,
      extendParams: extendParams,
      audioConfig: audioConfig,
    );

    AppLogger.i('Config loaded: env=${environments.current.displayName}, micSampleRate=${audioConfig.micSampleRate}');
  }

  /// 获取自适应的默认音频配置
  AudioConfig _getAdaptiveDefaultAudioConfig() {
    try {
      // 获取主视图
      final view = PlatformDispatcher.instance.views.first;
      // 获取物理尺寸
      final physicalSize = view.physicalSize;
      // 获取设备像素比
      final devicePixelRatio = view.devicePixelRatio;
      
      // 计算逻辑尺寸
      final width = physicalSize.width / devicePixelRatio;
      final height = physicalSize.height / devicePixelRatio;
      
      // 计算短边
      final shortSide = width < height ? width : height;
      
      // 使用 480 作为阈值（同 FloatingEditOverlay）
      // 如果是小屏设备，默认使用 11025Hz
      if (shortSide <= 480) {
        AppLogger.i('Small screen detected, defaulting to 11025Hz sample rate');
        return const AudioConfig(micSampleRate: 11025);
      }
    } catch (e) {
      AppLogger.w('Failed to detect screen size for adaptive config', e);
    }
    
    return AudioConfig.defaultConfig();
  }

  /// 获取当前配置
  AppConfig get config {
    if (_config == null) {
      throw StateError('ConfigService not initialized');
    }
    return _config!;
  }

  // ========== 环境配置相关 ==========

  /// 更新当前环境
  Future<void> setCurrentEnvironment(Environment env) async {
    final newEnvs = config.environments.copyWith(current: env);
    await _saveEnvironments(newEnvs);
    _config = _config?.copyWith(environments: newEnvs);
    AppLogger.i('Current environment set to: ${env.displayName}');
  }

  /// 更新指定环境的配置
  Future<void> updateEnvironmentConfig(
    Environment env,
    EnvironmentConfig envConfig,
  ) async {
    final newEnvs = config.environments.updateEnvironment(env, envConfig);
    await _saveEnvironments(newEnvs);
    _config = _config?.copyWith(environments: newEnvs);
    AppLogger.i('Environment config updated: ${env.displayName}');
  }

  /// 保存环境配置
  Future<void> _saveEnvironments(MultiEnvironmentConfig envs) async {
    await _prefs?.setString(StorageKeys.environments, jsonEncode(envs.toJson()));
  }

  // ========== OTA 配置相关（由 OtaService 调用，按当前环境存储）==========

  /// 设置当前环境的 OTA 返回 WebSocket 地址
  Future<void> setOtaWsUrl(String url) async {
    final env = config.currentEnvironment;
    final currentConfig = config.environments.currentConfig;
    final newConfig = currentConfig.copyWith(otaWsUrl: url);
    await updateEnvironmentConfig(env, newConfig);
    AppLogger.i('OTA WS URL set for ${env.displayName}: $url');
  }

  /// 设置当前环境的 OTA 返回 H5 地址
  Future<void> setOtaH5Url(String url) async {
    final env = config.currentEnvironment;
    final currentConfig = config.environments.currentConfig;
    final newConfig = currentConfig.copyWith(otaH5Url: url);
    await updateEnvironmentConfig(env, newConfig);
    AppLogger.i('OTA H5 URL set for ${env.displayName}: $url');
  }

  /// 清除当前环境的 OTA 配置
  Future<void> clearOtaConfig() async {
    final env = config.currentEnvironment;
    final currentConfig = config.environments.currentConfig;
    final newConfig = currentConfig.copyWith(
      clearOtaWsUrl: true,
      clearOtaH5Url: true,
    );
    await updateEnvironmentConfig(env, newConfig);
    AppLogger.i('OTA config cleared for ${env.displayName}');
  }

  // ========== 基础设置相关 ==========

  /// 设置自定义设备名称
  Future<void> setCustomDeviceName(String? name) async {
    final cleanName = name?.trim();
    if (cleanName == null || cleanName.isEmpty) {
      await _prefs?.remove(StorageKeys.customDeviceName);
      _config = _config?.copyWith(clearCustomDeviceName: true);
    } else {
      await _prefs?.setString(StorageKeys.customDeviceName, cleanName);
      _config = _config?.copyWith(customDeviceName: cleanName);
    }
    AppLogger.i('Custom device name set to: $cleanName');
  }

  /// 设置自动激活授权码
  Future<void> setAuthCode(String code) async {
    final cleanCode = code.trim();
    await _prefs?.setString(StorageKeys.authCode, cleanCode);
    _config = _config?.copyWith(authCode: cleanCode);
    AppLogger.i('Auth code set to: $cleanCode');
  }

  // ========== 便捷属性 ==========

  /// 设备 ID
  String get deviceId => config.deviceId;

  /// 客户端 ID
  String get clientId => config.clientId;

  /// 自定义设备名称
  String? get customDeviceName => config.customDeviceName;

  /// 自动激活授权码
  String get authCode => config.authCode;

  /// 有效的 WebSocket 地址
  String? get effectiveWsUrl => config.effectiveWsUrl;

  /// 有效的 H5 地址
  String? get effectiveH5Url => config.effectiveH5Url;

  /// OTA 地址
  String get otaUrl => config.otaUrl;

  /// 当前环境
  Environment get currentEnvironment => config.currentEnvironment;

  /// H5 首页 URL（用于全屏 WebView 容器）
  String get h5HomeUrl => config.effectiveH5Url ?? '';

  // ========== 音频配置相关 ==========

  /// 获取音频配置
  AudioConfig get audioConfig => config.audioConfig;

  /// 获取麦克风采样率
  int get micSampleRate => config.audioConfig.micSampleRate;

  /// 更新音频配置
  Future<void> updateAudioConfig(AudioConfig audioConfig) async {
    await _prefs?.setString(
      StorageKeys.audioConfig,
      jsonEncode(audioConfig.toJson()),
    );
    _config = _config?.copyWith(audioConfig: audioConfig);
    AppLogger.i('Audio config updated: $audioConfig');
  }

  /// 设置麦克风采样率
  Future<void> setMicSampleRate(int sampleRate) async {
    if (!AudioConfig.isValidSampleRate(sampleRate)) {
      AppLogger.w('Invalid sample rate: $sampleRate');
      return;
    }
    final newConfig = config.audioConfig.copyWith(micSampleRate: sampleRate);
    await updateAudioConfig(newConfig);
  }

  // ========== 兼容旧接口 ==========

  /// 服务器地址（兼容旧代码）
  String get serverUrl => config.effectiveWsUrl ?? '';

  /// 设置服务器地址（更新当前环境的 wsUrl）
  Future<void> setServerUrl(String url) async {
    final env = config.currentEnvironment;
    final envConfig = config.environments.getConfig(env).copyWith(wsUrl: url);
    await updateEnvironmentConfig(env, envConfig);
  }

  /// 设置设备 ID (手动修改)
  Future<void> setDeviceId(String newDeviceId) async {
    if (!_isValidMacFormat(newDeviceId)) {
      throw const FormatException('Invalid MAC address format');
    }
    await _prefs?.setString(StorageKeys.deviceId, newDeviceId);
    // 更新内存配置 - 简化版本，不再需要传递 OTA 配置
    _config = AppConfig(
      deviceId: newDeviceId,
      clientId: _config!.clientId,
      environments: _config!.environments,
      extendParams: _config!.extendParams,
    );
    AppLogger.i('Device ID updated: $newDeviceId');
  }

  /// 更新扩展参数（支持合并更新，同时持久化）
  Future<void> setExtendParams(Map<String, dynamic>? params) async {
    if (params == null) return;
    
    // 如果当前为 null，直接创建新 map
    // 否则创建副本并合并
    final currentParams = _config?.extendParams;
    final Map<String, dynamic> newParams;
    
    if (currentParams == null) {
      newParams = Map.from(params);
    } else {
      newParams = Map.from(currentParams)..addAll(params);
    }
    
    _config = _config?.copyWith(extendParams: newParams);
    await _saveExtendParams(newParams);
    AppLogger.i('Extend params updated (merged): $newParams');
  }

  /// 完全替换扩展参数（用于设置页面直接编辑）
  Future<void> replaceExtendParams(Map<String, dynamic>? params) async {
    _config = _config?.copyWith(extendParams: params);
    await _saveExtendParams(params);
    AppLogger.i('Extend params replaced: $params');
  }

  /// 保存扩展参数到持久化存储
  Future<void> _saveExtendParams(Map<String, dynamic>? params) async {
    if (params == null || params.isEmpty) {
      await _prefs?.remove(StorageKeys.extendParams);
    } else {
      await _prefs?.setString(StorageKeys.extendParams, jsonEncode(params));
    }
  }

  /// 清除扩展参数
  Future<void> clearExtendParams() async {
    _config = _config?.copyWith(extendParams: null);
    await _prefs?.remove(StorageKeys.extendParams);
    AppLogger.i('Extend params cleared');
  }

  /// 清除所有配置
  Future<void> clear() async {
    await _prefs?.clear();
    await _loadConfig();
    AppLogger.i('Config cleared');
  }

  // ========== 密码管理 ==========

  /// 获取管理密码
  Future<String> getConfigPassword() async {
    try {
      final password = _prefs?.getString(StorageKeys.configPassword);
      return password ?? AppConstants.defaultConfigPassword;
    } catch (e) {
      AppLogger.e('Failed to get config password', e);
      return AppConstants.defaultConfigPassword;
    }
  }

  /// 保存管理密码
  Future<bool> saveConfigPassword(String password) async {
    try {
      await _prefs?.setString(StorageKeys.configPassword, password);
      AppLogger.i('Config password updated');
      return true;
    } catch (e) {
      AppLogger.e('Failed to save config password', e);
      return false;
    }
  }

  /// 验证管理密码
  Future<bool> verifyConfigPassword(String password) async {
    final savedPassword = await getConfigPassword();
    return password == savedPassword;
  }

  // ========== MAC 地址辅助方法 ==========

  /// 基于硬件 ID 生成稳定的 MAC 地址
  /// Android: 基于 androidId（应用卸载重装后保持不变）
  /// iOS: 优先尝试从 Keychain 获取，如果获取不到则生成随机 ID 并存入 Keychain
  Future<String> _generateMacAddressFromHardware() async {
    try {
      if (Platform.isAndroid) {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        // Android ID 在应用签名不变的情况下通常保持不变
        return _hardwareIdToMac(androidInfo.id);
      } else if (Platform.isIOS) {
        // iOS 使用 Keychain 存储唯一的 ID
        const storage = FlutterSecureStorage();
        String? uniqueId = await storage.read(key: 'device_unique_id');
        
        if (uniqueId == null || uniqueId.isEmpty) {
          // 如果 Keychain 中没有，尝试读取 identifierForVendor 或者生成一个新的
          final deviceInfo = DeviceInfoPlugin();
          final iosInfo = await deviceInfo.iosInfo;
          uniqueId = iosInfo.identifierForVendor;
          
          if (uniqueId == null || uniqueId.isEmpty) {
             uniqueId = const Uuid().v4();
          }
          
          // 存入 Keychain，以便卸载重装后找回
          await storage.write(key: 'device_unique_id', value: uniqueId);
          AppLogger.i('Generated new iOS device ID and saved to Keychain: $uniqueId');
        } else {
          AppLogger.i('Restored iOS device ID from Keychain: $uniqueId');
        }
        
        return _hardwareIdToMac(uniqueId);
      }
      
      return _generateMacAddress();
    } catch (e, stackTrace) {
      AppLogger.e('Failed to get hardware ID, using random MAC', e, stackTrace);
      return _generateMacAddress();
    }
  }
  
  /// 将硬件 ID 字符串转换为 MAC 地址格式
  /// 使用 MD5 哈希确保固定长度和格式
  String _hardwareIdToMac(String hardwareId) {
    // 简单哈希：取字符串的 hashCode 并格式化
    // 为了更稳定的哈希，使用字符串的 codeUnits 计算
    var hash = 0;
    for (var i = 0; i < hardwareId.length; i++) {
      hash = ((hash << 5) - hash + hardwareId.codeUnitAt(i)) & 0xFFFFFFFFFFFF;
    }
    
    // 转换为 6 字节的 MAC 地址
    final bytes = <String>[];
    for (var i = 0; i < 6; i++) {
      final byte = (hash >> (i * 8)) & 0xFF;
      bytes.add(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
    }
    
    // 确保第一个字节为偶数（单播地址）
    var firstByte = int.parse(bytes[0], radix: 16);
    firstByte = firstByte & 0xFE;
    bytes[0] = firstByte.toRadixString(16).toUpperCase().padLeft(2, '0');
    
    return bytes.join(':');
  }

  /// 生成随机 MAC 地址（备用方案）
  /// 格式: AA:BB:CC:DD:EE:FF，确保第一个字节为偶数（单播地址）
  String _generateMacAddress() {
    final uuid = const Uuid().v4().replaceAll('-', '');
    
    // 使用 UUID 的前 12 个十六进制字符作为 MAC 地址
    final bytes = <String>[];
    for (var i = 0; i < 12; i += 2) {
      bytes.add(uuid.substring(i, i + 2).toUpperCase());
    }
    
    // 确保第一个字节为偶数（单播地址）
    var firstByte = int.parse(bytes[0], radix: 16);
    firstByte = firstByte & 0xFE; // 清除最低位
    bytes[0] = firstByte.toRadixString(16).toUpperCase().padLeft(2, '0');
    
    return bytes.join(':');
  }

  /// 验证 MAC 地址格式
  bool _isValidMacFormat(String mac) {
    final pattern = RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$');
    return pattern.hasMatch(mac);
  }
}
