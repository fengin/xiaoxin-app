/// XiaoXin APP - 语音引擎
/// 整合 KWS（热词唤醒）和 VAD（语音活动检测）功能
library;

import 'dart:typed_data';
import '../../utils/logger.dart';
import '../settings/config_service.dart';
import '../protocol/protocol_service.dart';
import 'sherpa_onnx_manager.dart';

/// 热词检测回调
typedef OnKeywordDetectedCallback = void Function(String keyword);

/// VAD 状态变化回调
typedef OnVadStateChangedCallback = void Function(bool isSpeaking);

/// 语音引擎
class VoiceEngine {
  VoiceEngine._();

  static final VoiceEngine instance = VoiceEngine._();

  bool _isInitialized = false;
  bool _kwsEnabled = false;
  bool _vadEnabled = false;
  bool _isSpeaking = false;

  // 回调
  OnKeywordDetectedCallback? onKeywordDetected;
  OnVadStateChangedCallback? onVadStateChanged;

  /// 是否已初始化
  bool get isInitialized => _isInitialized;

  /// KWS 是否启用
  bool get isKwsEnabled => _kwsEnabled;

  /// VAD 是否启用
  bool get isVadEnabled => _vadEnabled;

  /// 当前是否检测到语音
  bool get isSpeaking => _isSpeaking;

  /// 初始化语音引擎
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      final success = await SherpaOnnxManager.instance.initialize();
      if (!success) {
        AppLogger.e('Failed to initialize SherpaOnnxManager');
        return false;
      }

      _isInitialized = true;
      AppLogger.i('VoiceEngine initialized');
      return true;
    } catch (e, stackTrace) {
      AppLogger.e('Failed to initialize VoiceEngine', e, stackTrace);
      return false;
    }
  }

  /// 启用 KWS（热词检测）
  void enableKws(bool enable) {
    _kwsEnabled = enable;
    AppLogger.i('KWS ${enable ? "enabled" : "disabled"}, callback=${onKeywordDetected != null}, sherpaInitialized=${SherpaOnnxManager.instance.isInitialized}');
  }

  /// 启用 VAD（语音活动检测）
  void enableVad(bool enable) {
    _vadEnabled = enable;
    if (!enable) {
      _isSpeaking = false;
    }
    AppLogger.i('VAD ${enable ? "enabled" : "disabled"}');
  }

  /// 处理音频数据（支持不同采样率的 KWS 和 VAD）
  /// [samplesForKws] KWS 使用的数据（麦克风原始采样率）
  /// [samplesForVad] VAD 使用的数据（16000Hz）
  /// 返回值：如果检测到热词或语音状态变化，返回 true
  static int _processAudioCounter = 0;
  bool processAudio(Float32List samplesForKws, {Float32List? samplesForVad}) {
    if (!_isInitialized) {
      return false;
    }

    // 如果没有提供 VAD 数据，使用 KWS 数据（兼容旧调用方式，如采样率相同时）
    final vadSamples = samplesForVad ?? samplesForKws;

    // 每500次打印一次，确认音频到达 VoiceEngine
    _processAudioCounter++;
    if (_processAudioCounter % 500 == 1) {
      AppLogger.d('VoiceEngine.processAudio: #$_processAudioCounter, kwsEnabled=$_kwsEnabled, vadEnabled=$_vadEnabled, kwsSamples=${samplesForKws.length}, vadSamples=${vadSamples.length}');
    }

    bool hasEvent = false;

    // 处理 KWS（使用原始采样率数据）
    if (_kwsEnabled) {
      hasEvent = _processKws(samplesForKws) || hasEvent;
    }

    // 处理 VAD（使用 16k 数据）
    if (_vadEnabled) {
      hasEvent = _processVad(vadSamples) || hasEvent;
    }

    return hasEvent;
  }

  /// 处理 KWS
  static int _kwsDecodeCounter = 0;
  bool _processKws(Float32List samples) {
    final kws = SherpaOnnxManager.instance.kws;
    final stream = SherpaOnnxManager.instance.kwsStream;

    if (kws == null || stream == null) {
      AppLogger.w('KWS: kws=$kws, stream=$stream - not initialized!');
      return false;
    }

    try {
      // 使用麦克风采样率（与 KWS 模型初始化时的采样率一致）
      final micSampleRate = ConfigService.instance.micSampleRate;
      stream.acceptWaveform(
        samples: samples,
        sampleRate: micSampleRate,
      );

      // 检测关键词，使用 if 而非 while
      if (kws.isReady(stream)) {
        kws.decode(stream);
        _kwsDecodeCounter++;
        
        // 每100次decode打印一次日志
        if (_kwsDecodeCounter % 100 == 1) {
          AppLogger.d('KWS decode: #$_kwsDecodeCounter');
        }
        
        final result = kws.getResult(stream);
        if (result.keyword.isNotEmpty) {
          AppLogger.i('🎤 Keyword detected: ${result.keyword}');
          AppLogger.d('[Performance] [${ProtocolService.instance.sessionId ?? 'offline'}] [VAD_Wake] keyword=${result.keyword} time=${DateTime.now().millisecondsSinceEpoch}');
          onKeywordDetected?.call(result.keyword);

          // 使用 reset 而非重新创建 stream（与 Android 原版一致）
          kws.reset(stream);
          return true;
        }
      }
    } catch (e, stackTrace) {
      AppLogger.e('Error processing KWS', e, stackTrace);
    }

    return false;
  }

  /// 处理 VAD
  /// 使用 vad.isDetected() 获取连续的语音状态
  bool _processVad(Float32List samples) {
    final vad = SherpaOnnxManager.instance.vad;
    if (vad == null) return false;

    try {
      vad.acceptWaveform(samples);

      final wasSpeaking = _isSpeaking;

      // 使用 isDetected() 获取当前语音状态
      // 这是一个连续的状态，表示当前是否检测到语音
      _isSpeaking = vad.isDetected();

      // 处理检测到的语音片段（清空队列避免积压）
      while (!vad.isEmpty()) {
        vad.pop();
      }

      // 状态变化时触发回调
      if (wasSpeaking != _isSpeaking) {
        if (_isSpeaking) {
          AppLogger.i('VAD: Speech started (isDetected=true)');
          AppLogger.d('[Performance] [${ProtocolService.instance.sessionId ?? 'offline'}] [VAD_Speech_Start] time=${DateTime.now().millisecondsSinceEpoch}');
        } else {
          AppLogger.i('VAD: Speech ended (isDetected=false)');
        }
        onVadStateChanged?.call(_isSpeaking);
        return true;
      }
    } catch (e, stackTrace) {
      AppLogger.e('Error processing VAD', e, stackTrace);
    }

    return false;
  }

  /// 重置 VAD 状态
  void resetVad() {
    final vad = SherpaOnnxManager.instance.vad;
    if (vad != null) {
      try {
        vad.clear();
        _isSpeaking = false;
        AppLogger.d('VAD reset');
      } catch (e) {
        AppLogger.e('Error resetting VAD', e);
      }
    }
  }

  /// 释放资源
  void dispose() {
    _isInitialized = false;
    _kwsEnabled = false;
    _vadEnabled = false;
    _isSpeaking = false;
    onKeywordDetected = null;
    onVadStateChanged = null;
    SherpaOnnxManager.instance.dispose();
    AppLogger.i('VoiceEngine disposed');
  }
}
