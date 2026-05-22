/// XiaoXin APP - 音频配置模型
/// 可配置的音频参数，用于适配不同设备的麦克风特性
library;

import '../utils/constants.dart';

/// 音频配置
class AudioConfig {
  /// 麦克风采样率 (默认 16000)
  final int micSampleRate;

  /// VAD 阈值 (0.3~0.9)
  final double vadThreshold;

  /// 最小静音时长 (秒, 0.3~2.0)
  final double minSilenceDuration;

  /// 最小语音时长 (秒, 0.1~0.8)
  final double minSpeechDuration;

  /// VAD 窗口大小 (256/512/1024)
  final int vadWindowSize;

  /// VAD 预缓存时长 (毫秒, 200~800)
  final int vadPreCacheDurationMs;

  /// KWS 分数阈值 (1.0~2.0, 越高越灵敏)
  final double keywordsScore;

  /// KWS 触发阈值 (0.3~0.8, 越高越严格)
  final double keywordsThreshold;

  /// Opus 编码目标采样率 (固定 16000，服务端要求)
  static const int opusSampleRate = 16000;

  /// 支持的采样率列表
  static const List<int> supportedSampleRates = [
    8000,
    11025,
    16000,
    22050,
    44100,
    48000,
  ];

  /// 支持的 VAD 窗口大小
  static const List<int> supportedVadWindowSizes = [256, 512, 1024];

  const AudioConfig({
    this.micSampleRate = 16000,
    this.vadThreshold = AppConstants.vadThreshold,
    this.minSilenceDuration = AppConstants.minSilenceDuration,
    this.minSpeechDuration = AppConstants.minSpeechDuration,
    this.vadWindowSize = AppConstants.vadWindowSize,
    this.vadPreCacheDurationMs = AppConstants.vadPreCacheDurationMs,
    this.keywordsScore = AppConstants.keywordsScore,
    this.keywordsThreshold = AppConstants.keywordsThreshold,
  });

  /// 是否需要重采样
  bool get needsResampling => micSampleRate != opusSampleRate;

  /// 重采样比率
  double get resampleRatio => micSampleRate / opusSampleRate;

  AudioConfig copyWith({
    int? micSampleRate,
    double? vadThreshold,
    double? minSilenceDuration,
    double? minSpeechDuration,
    int? vadWindowSize,
    int? vadPreCacheDurationMs,
    double? keywordsScore,
    double? keywordsThreshold,
  }) {
    return AudioConfig(
      micSampleRate: micSampleRate ?? this.micSampleRate,
      vadThreshold: vadThreshold ?? this.vadThreshold,
      minSilenceDuration: minSilenceDuration ?? this.minSilenceDuration,
      minSpeechDuration: minSpeechDuration ?? this.minSpeechDuration,
      vadWindowSize: vadWindowSize ?? this.vadWindowSize,
      vadPreCacheDurationMs: vadPreCacheDurationMs ?? this.vadPreCacheDurationMs,
      keywordsScore: keywordsScore ?? this.keywordsScore,
      keywordsThreshold: keywordsThreshold ?? this.keywordsThreshold,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'micSampleRate': micSampleRate,
      'vadThreshold': vadThreshold,
      'minSilenceDuration': minSilenceDuration,
      'minSpeechDuration': minSpeechDuration,
      'vadWindowSize': vadWindowSize,
      'vadPreCacheDurationMs': vadPreCacheDurationMs,
      'keywordsScore': keywordsScore,
      'keywordsThreshold': keywordsThreshold,
    };
  }

  factory AudioConfig.fromJson(Map<String, dynamic> json) {
    return AudioConfig(
      micSampleRate: json['micSampleRate'] as int? ?? 16000,
      vadThreshold: (json['vadThreshold'] as num?)?.toDouble() ?? AppConstants.vadThreshold,
      minSilenceDuration: (json['minSilenceDuration'] as num?)?.toDouble() ?? AppConstants.minSilenceDuration,
      minSpeechDuration: (json['minSpeechDuration'] as num?)?.toDouble() ?? AppConstants.minSpeechDuration,
      vadWindowSize: json['vadWindowSize'] as int? ?? AppConstants.vadWindowSize,
      vadPreCacheDurationMs: json['vadPreCacheDurationMs'] as int? ?? AppConstants.vadPreCacheDurationMs,
      keywordsScore: (json['keywordsScore'] as num?)?.toDouble() ?? AppConstants.keywordsScore,
      keywordsThreshold: (json['keywordsThreshold'] as num?)?.toDouble() ?? AppConstants.keywordsThreshold,
    );
  }

  /// 默认配置
  factory AudioConfig.defaultConfig() {
    return const AudioConfig();
  }

  /// 验证采样率是否有效
  static bool isValidSampleRate(int rate) {
    return supportedSampleRates.contains(rate);
  }

  @override
  String toString() {
    return 'AudioConfig(mic: ${micSampleRate}Hz, vadTh: $vadThreshold, silence: ${minSilenceDuration}s, '
        'speech: ${minSpeechDuration}s, kwsScore: $keywordsScore, kwsTh: $keywordsThreshold)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AudioConfig &&
        other.micSampleRate == micSampleRate &&
        other.vadThreshold == vadThreshold &&
        other.minSilenceDuration == minSilenceDuration &&
        other.minSpeechDuration == minSpeechDuration &&
        other.vadWindowSize == vadWindowSize &&
        other.vadPreCacheDurationMs == vadPreCacheDurationMs &&
        other.keywordsScore == keywordsScore &&
        other.keywordsThreshold == keywordsThreshold;
  }

  @override
  int get hashCode => Object.hash(
        micSampleRate,
        vadThreshold,
        minSilenceDuration,
        minSpeechDuration,
        vadWindowSize,
        vadPreCacheDurationMs,
        keywordsScore,
        keywordsThreshold,
      );
}
