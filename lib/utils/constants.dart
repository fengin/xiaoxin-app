/// XiaoXin APP - 常量定义
library;

import 'package:package_info_plus/package_info_plus.dart';

/// 应用常量
class AppConstants {
  AppConstants._();

  /// 应用名称
  static const String appName = 'XiaoXin';

  /// 应用版本（运行时从 pubspec.yaml 动态获取，fallback 为默认值）
  static String appVersion = '1.0.0';

  /// 包名（运行时动态获取）
  static String packageName = 'chat.xiaoxin.app';

  /// 初始化动态常量（在 main.dart 启动时调用）
  static Future<void> initAsync() async {
    try {
      final info = await PackageInfo.fromPlatform();
      appVersion = info.version;
      packageName = info.packageName;
    } catch (_) {
      // 获取失败保持默认值
    }
  }


  /// 默认服务器地址（兼容旧代码）
  static const String defaultServerUrl = 'ws://your-server-ip:8091/ws/xiaoxin/v1/';

  /// 默认 OTA 地址（测试环境）
  static const String defaultTestOtaUrl = 'http://your-server-ip:8091/api/device/ota';

  /// 默认 H5 Demo 地址
  static const String defaultH5DemoUrl = 'assets/web/demo.html';

  /// 默认管理密码
  static const String defaultConfigPassword = '123456';

  /// 协议版本
  static const int protocolVersion = 1;

  /// 音频参数
  static const int audioSampleRate = 16000;
  static const int audioChannels = 1;
  static const int audioFrameDurationMs = 60;
  static const String audioFormat = 'opus';

  /// 服务端返回音频采样率
  static const int serverAudioSampleRate = 16000;

  /// VAD 参数
  /// 场景调优建议：
  /// | 场景         | minSilenceDuration | minSpeechDuration |
  /// |--------------|-------------------|-------------------|
  /// | 安静环境      | 0.5 ~ 0.6         | 0.3               |
  /// | 嘈杂环境      | 0.8 ~ 1.0         | 0.5               |
  /// | 快节奏对话    | 0.4 ~ 0.5         | 0.3               |
  /// | 老人/语速慢   | 1.0 ~ 1.5         | 0.3               |
  
  // VAD 阈值：决定多"响"的声音才算语音，调高抗噪强但漏检多，调低灵敏但误检多
  // 低值 (0.3~0.5)：更灵敏，小声说话也能检测到，但容易误检噪音
  // 高值 (0.7~0.9)：更严格，只有明显语音才检测，但可能漏检轻声
  static const double vadThreshold = 0.8;

  // 最小静音时长（秒）：用户停顿多久判定为说完
  // 调大容忍更长停顿，调小响应更快但易打断
  // 取值范围：0.3 ~ 2.0，推荐 0.5 ~ 1.0
  static const double minSilenceDuration = 0.6;

  // 最小语音时长（秒）：连续说话多久才算有效语音开始
  // 调大过滤杂音，调小更灵敏但易误触发
  // 取值范围：0.1 ~ 0.8，推荐 0.2 ~ 0.5
  static const double minSpeechDuration = 0.3;

  // VAD 窗口大小：调大抗噪强但延迟高，调小延迟低但抗噪弱
  // 取值范围：256 ~ 1024，推荐 512
  // 小窗口 (256)：响应快，延迟低，但容易受瞬时噪音影响
  // 大窗口 (1024)：抗噪强，延迟高，适合嘈杂环境
  static const int vadWindowSize = 512;

  // VAD 预缓存时长（毫秒）：补偿 VAD 检测延迟，避免语音开头丢失
  // 一般 VAD 检测延迟约 150-250ms，设置适当余量即可
  // 过大会导致回音被录入，过小会导致语音被截头，这里500ms主要考虑热词唤醒场景热词有4个字
  // 取值范围：200 ~ 800，推荐 300 ~ 500
  static const int vadPreCacheDurationMs = 800;



  /// KWS 参数
  // 热词检测分数阈值（Boosting Score）：Sherpa-ONNX 内部的加分系数
  // - 值越高：越灵敏，越容易触发（但也越容易误报）
  // - 值越低：越严格，需要更匹配的声音才能触发
  // 取值范围：1.0 ~ 2.0
  // - 1.0 (推荐)：严格模式，误报少
  // - 1.5：平衡模式
  // - 2.0：高灵敏模式（容易误触）
  // 播放期间打断建议保持高灵敏度 (1.8 ~ 2.0)
  static const double keywordsScore = 1.0;
  
  // 热词检测触发阈值（Trigger Threshold）：概率阈值
  // - 值越高：越严格（概率要求越接近 1.0）
  // - 值越低：越灵敏（更容忍低概率）
  // 取值范围：0.3 ~ 0.8
  // - 0.3 ~ 0.4：灵敏
  // - 0.5 ~ 0.6：推荐
  // - 0.7 ~ 0.8：严格
  static const double keywordsThreshold = 0.5;

  /// 超时设置
  static const int connectionTimeoutSeconds = 10;
  static const int vadTimeoutSeconds = 30;
}

/// SharedPreferences 存储键
class StorageKeys {
  StorageKeys._();

  // 设备标识
  static const String deviceId = 'device_id';
  static const String clientId = 'client_id';
  static const String customDeviceName = 'custom_device_name';
  static const String authCode = 'auth_code';

  // 环境配置（包含各环境的 OTA 返回配置）
  static const String environments = 'environments';

  // OTA Token
  static const String otaToken = 'ota_token';

  // 管理密码
  static const String configPassword = 'config_password';

  // 音频配置
  static const String audioConfig = 'audio_config';

  // 兼容旧键
  static const String serverUrl = 'server_url';
  static const String authToken = 'auth_token';
  static const String extendParams = 'extend_params';
}



