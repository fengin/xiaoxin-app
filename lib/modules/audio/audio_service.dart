/// XiaoXin APP - 音频服务门面
/// 统一管理音频相关的所有服务
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'record_service.dart';
import 'audio_processor.dart';
import 'audio_player_service.dart';
import 'audio_state_manager.dart';
import 'audio_session_service.dart';
import '../voice/voice_engine.dart';
import '../settings/permission_service.dart';
import '../../utils/logger.dart';

/// 音频服务门面
/// 提供统一的接口来管理录音、播放、编解码等
class AudioService {
  AudioService._();

  static final AudioService instance = AudioService._();

  bool _isInitialized = false;
  bool _hasPermission = false;
  bool _isVoiceEngineReady = false;

  /// 是否已初始化
  bool get isInitialized => _isInitialized;
  
  /// 是否有麦克风权限
  bool get hasPermission => _hasPermission;
  
  /// VoiceEngine 是否就绪
  bool get isVoiceEngineReady => _isVoiceEngineReady;

  /// 是否正在录音
  bool get isRecording => RecordService.instance.isRecording;

  /// 是否正在播放
  bool get isPlaying => AudioStateManager.instance.isSystemAudioPlaying;

  /// 播放状态变化流
  Stream<bool> get onPlaybackStateChanged => AudioStateManager.instance.onStateChange;
  
  /// KWS 是否启用
  bool get isKwsEnabled => AudioProcessor.instance.isKwsEnabled;
  
  /// VAD 是否启用
  bool get isVadEnabled => AudioProcessor.instance.isVadEnabled;

/// 初始化所有音频服务
  /// 并行初始化独立服务，异步加载 VoiceEngine 模型
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      AppLogger.d('Initializing AudioService...');

      // 1. 并行初始化独立服务
      final results = await Future.wait<dynamic>([
        PermissionService.instance.requestMicrophonePermission(),
        AudioSessionService.instance.initialize(),
        AudioPlayerService.instance.initialize(),
      ]);
      
      final permissionGranted = results[0] as bool;
      _hasPermission = permissionGranted;
      
      if (!permissionGranted) {
        AppLogger.w('Microphone permission not granted');
        // 继续初始化，让界面可以显示权限提示
      }

      // 2. 初始化音频处理器（包含 Opus 编解码）
      final processorOk = await AudioProcessor.instance.initialize();
      if (!processorOk) {
        AppLogger.e('AudioProcessor initialization failed');
        return false;
      }

      // 3. 异步加载 VoiceEngine 模型（不阻塞）
      unawaited(VoiceEngine.instance.initialize().then((_) {
        _isVoiceEngineReady = true;
        AppLogger.i('VoiceEngine ready');
      }));

      _isInitialized = true;
      AppLogger.i('AudioService initialized (permission=$permissionGranted)');
      return permissionGranted;
    } catch (e, stackTrace) {
      AppLogger.e('Failed to initialize AudioService', e, stackTrace);
      return false;
    }
  }

  /// 开始录音和处理
  Future<bool> startRecording() async {
    return await AudioProcessor.instance.startProcessing();
  }

  /// 停止录音和处理
  Future<void> stopRecording() async {
    await AudioProcessor.instance.stopProcessing();
  }

  /// 暂停 VAD（播放 TTS 时）
  void pauseVad() {
    AudioProcessor.instance.pauseVad();
  }

  /// 恢复 VAD
  void resumeVad() {
    AudioProcessor.instance.resumeVad();
  }
  
  /// 恢复录音
  Future<void> resumeRecording() async {
    await RecordService.instance.resumeRecording();
  }

  /// 播放服务端返回的 Opus 音频
  void playOpusAudio(Uint8List opusData) {
    AudioPlayerService.instance.playOpusData(opusData);
  }

  /// 停止播放
  Future<void> stopPlayback() async {
    // iOS 特殊处理：flutter_pcm_sound 重建播放器时会设置 AudioSession category
    // 如果此时录音正在进行 (playAndRecord)，会导致冲突 (!pri error)
    // 解决方案：暂时暂停录音，释放 AudioSession 锁，待播放器重置后再恢复
    final bool needPauseRecord = Platform.isIOS && RecordService.instance.isRecording;
    
    if (needPauseRecord) {
      AppLogger.d('⏹️ Stopping recording for stopPlayback on iOS to release AudioUnit...');
      // 必须完全停止录音，pause 可能不足以释放 Audio Unit 锁
      await RecordService.instance.stopRecording();
    }
    
    try {
      await AudioPlayerService.instance.stopPlayback();
    } finally {
      if (needPauseRecord) {
        AppLogger.d('▶️ Restarting recording after stopPlayback on iOS...');
        // 重新开始录音
        await RecordService.instance.startRecording();
      }
    }
  }

  /// 设置播放采样率
  Future<void> setPlaybackSampleRate(int sampleRate) async {
    await AudioPlayerService.instance.setSampleRate(sampleRate);
  }

  /// 启用/禁用 KWS（热词检测）
  void enableKws(bool enable) {
    AudioProcessor.instance.enableKws(enable);
  }
  
  /// 启用/禁用 VAD（语音检测）
  Future<void> enableVad(bool enable) async {
    await AudioProcessor.instance.enableVad(enable);
  }

  /// 清空音频发送缓冲区
  void clearBuffers() {
    AudioProcessor.instance.clearBuffers();
  }

  /// 发送预缓存的音频数据
  void sendPreCachedAudio() {
    AudioProcessor.instance.sendPreCachedAudio();
  }

  /// 设置热词检测回调
  void setKeywordDetectedCallback(void Function(String)? callback) {
    VoiceEngine.instance.onKeywordDetected = callback;
  }

  /// 设置 VAD 状态变化回调
  void setVadStateChangedCallback(void Function(bool)? callback) {
    VoiceEngine.instance.onVadStateChanged = callback;
  }

  /// 释放资源
  Future<void> dispose() async {
    await AudioProcessor.instance.dispose();
    await AudioPlayerService.instance.dispose();
    VoiceEngine.instance.dispose();
    _isInitialized = false;
    AppLogger.i('AudioService disposed');
  }
}
