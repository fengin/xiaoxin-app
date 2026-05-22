/// XiaoXin APP - 音频处理器
/// 整合录音、VAD、Opus编码和WebSocket上传
library;

import 'dart:async';
import 'dart:typed_data';
import '../protocol/protocol_service.dart';
import '../settings/config_service.dart';
import '../voice/voice_engine.dart';
import 'record_service.dart';
import 'opus_service.dart';
import 'audio_resampler.dart';
import 'circular_audio_buffer.dart';
import '../../models/audio_config.dart';
import '../../utils/logger.dart';
import '../../utils/constants.dart';

/// 音频处理器
/// 负责：录音 → PCM 处理 → VAD/KWS → Opus 编码 → WebSocket 发送
class AudioProcessor {
  AudioProcessor._();

  static final AudioProcessor instance = AudioProcessor._();

  bool _isProcessing = false;
  bool _isInitialized = false;
  
  // 独立的 KWS/VAD 控制开关
  bool _kwsEnabled = false;
  bool _vadEnabled = false;
  
  /// VAD 状态变化回调（用于通知 H5）
  void Function(bool enabled)? onVadEnabledChanged;

  // PCM 缓冲区（用于累积足够的数据进行 Opus 编码）
  final List<int> _pcmBuffer = [];
  
  // VAD 预缓存缓冲区（500ms）
  late final CircularAudioBuffer _preCache;
  
  // 记录上一次 VAD 状态（用于检测语音开始）
  bool _wasSpeaking = false;
  
  // 【诊断】预缓存写入计数器，追踪预缓存来源
  int _preCacheWriteCount = 0;
  
  // 预缓存时长使用统一常量管理
  static int get _preCacheDurationMs => AppConstants.vadPreCacheDurationMs;

  // Opus 目标采样率下的每帧采样数（60ms 帧）
  static int get _opusSamplesPerFrame =>
      (AudioConfig.opusSampleRate * AppConstants.audioFrameDurationMs) ~/ 1000;

  // Opus 目标采样率下的每帧字节数
  static int get _opusBytesPerFrame => _opusSamplesPerFrame * 2;
  
  // PCM缓冲区最大容量（1MB，约等10秒音频@16kHz/16bit）
  static const int _maxPcmBufferSize = 1024 * 1024;

  /// 是否正在处理
  bool get isProcessing => _isProcessing;

  /// 是否已初始化
  bool get isInitialized => _isInitialized;
  
  /// KWS 是否启用
  bool get isKwsEnabled => _kwsEnabled;
  
  /// VAD 是否启用
  bool get isVadEnabled => _vadEnabled;

  /// 启用/禁用 KWS
  /// 注意：启用 KWS 时会确保音频处理继续（_isProcessing = true）
  void enableKws(bool enable) {
    _kwsEnabled = enable;
    VoiceEngine.instance.enableKws(enable);
    
    // 启用 KWS 时确保音频处理在运行
    if (enable && !_isProcessing) {
      _isProcessing = true;
      AppLogger.d('Audio processing resumed for KWS');
    }
    
    AppLogger.d('KWS ${enable ? "enabled" : "disabled"}');
  }
  
  /// 启用/禁用 VAD
  /// 注意：启用 VAD 时会自动恢复录音（防止因音频焦点丢失导致录音暂停）
  Future<void> enableVad(bool enable) async {
    final wasEnabled = _vadEnabled;
    _vadEnabled = enable;
    VoiceEngine.instance.enableVad(enable);
    
    // 通知 VAD 状态变化
    if (wasEnabled != enable) {
      onVadEnabledChanged?.call(enable);
    }
    
    // 启用 VAD 时，只有之前未启用才重置状态
    // 如果 VAD 已经在工作（如 listening 状态下热词检测），不重置 _wasSpeaking
    // 避免打断正在进行的语音检测，导致误判为"新语音开始"
    if (enable && !wasEnabled) {
      _wasSpeaking = false;  // 从禁用变为启用时重置状态
      await RecordService.instance.resumeRecording();
      AppLogger.d('VAD enabled (was disabled), _wasSpeaking reset to false');
    } else if (enable && wasEnabled) {
      // VAD 已经在工作，不重置状态
      AppLogger.d('VAD already enabled, keeping _wasSpeaking=$_wasSpeaking');
    } else {
      AppLogger.d('VAD disabled');
    }
  }

  /// 清空音频发送缓冲区（会话结束时调用）
  void clearBuffers() {
    _pcmBuffer.clear();
    _preCache.clear();
    AppLogger.d('Audio buffers cleared');
  }

  /// 只清空发送缓冲区，保留预缓存
  /// 用于 TTS 播放完成后，保留预缓存以补偿语音开头
  void clearSendBuffer() {
    _pcmBuffer.clear();
    AppLogger.d('Send buffer cleared (pre-cache preserved)');
  }

  /// 初始化音频处理器
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      AppLogger.d('Initializing AudioProcessor...');

      // 初始化预缓存缓冲区（使用 16k 采样率，因为入口处已统一重采样）
      _preCache = CircularAudioBuffer(
        durationMs: _preCacheDurationMs,
        sampleRate: AudioConfig.opusSampleRate,
      );
      AppLogger.d('Pre-cache buffer initialized: ${_preCacheDurationMs}ms @ ${AudioConfig.opusSampleRate}Hz');

      // 初始化 Opus 编解码器
      final opusOk = await OpusService.instance.initialize();
      if (!opusOk) {
        AppLogger.e('Failed to initialize Opus');
        return false;
      }

      // 设置录音回调
      RecordService.instance.onAudioData = _onRecordData;

      _isInitialized = true;
      AppLogger.i('AudioProcessor initialized');
      return true;
    } catch (e, stackTrace) {
      AppLogger.e('Failed to initialize AudioProcessor', e, stackTrace);
      return false;
    }
  }

  /// 开始音频处理（录音）
  /// 注意：这只启动录音，KWS/VAD 需要单独启用
  Future<bool> startProcessing() async {
    if (_isProcessing) {
      AppLogger.w('Audio processing already started');
      return true;
    }

    if (!_isInitialized) {
      final ok = await initialize();
      if (!ok) return false;
    }

    try {
      _pcmBuffer.clear();
      _preCache.clear();
      _wasSpeaking = false;

      // 开始录音
      final recordOk = await RecordService.instance.startRecording();
      if (!recordOk) {
        AppLogger.e('Failed to start recording');
        return false;
      }

      _isProcessing = true;
      AppLogger.i('Audio processing started (recording active)');
      return true;
    } catch (e, stackTrace) {
      AppLogger.e('Failed to start audio processing', e, stackTrace);
      return false;
    }
  }

  /// 停止音频处理（停止录音）
  Future<void> stopProcessing() async {
    if (!_isProcessing) return;

    try {
      // 停止录音
      await RecordService.instance.stopRecording();

      // 禁用 KWS/VAD
      _kwsEnabled = false;
      _vadEnabled = false;
      VoiceEngine.instance.enableKws(false);
      VoiceEngine.instance.enableVad(false);

      // 清空缓冲区
      _pcmBuffer.clear();

      _isProcessing = false;
      AppLogger.i('Audio processing stopped');
    } catch (e, stackTrace) {
      AppLogger.e('Failed to stop audio processing', e, stackTrace);
    }
  }

  /// 暂停 VAD 处理（播放 TTS 时调用）
  /// 注意：只暂停 VAD，KWS 保持活跃以支持语音打断
  void pauseVad() {
    enableVad(false);
    AppLogger.d('VAD paused (KWS still active)');
  }

  /// 恢复 VAD 处理
  void resumeVad() {
    enableVad(true);
    AppLogger.d('VAD resumed');
  }

  /// 处理录音数据
  /// 核心数据流：
  /// - KWS: 使用原始麦克风采样率数据
  /// - VAD/预缓存/发送: 使用 16k 数据（如需重采样则在此处统一处理）
  void _onRecordData(Uint8List pcmData) {
    if (!_isProcessing) {
      return;
    }

    // ========== 1. 数据准备 ==========
    // 获取音频配置
    final audioConfig = ConfigService.instance.audioConfig;
    final needsResampling = audioConfig.needsResampling;
    
    // 原始数据用于 KWS（麦克风采样率）
    final Uint8List dataForKws = pcmData;
    
    // 16k 数据用于 VAD、预缓存、发送（如需重采样则转换）
    final Uint8List dataFor16k;
    if (needsResampling) {
      dataFor16k = AudioResampler.instance.resample(
        inputData: pcmData,
        inputSampleRate: audioConfig.micSampleRate,
        outputSampleRate: AudioConfig.opusSampleRate,
      );
    } else {
      dataFor16k = pcmData;
    }

    // ========== 2. 预缓存写入（使用 16k 数据） ==========
    // 只有在 VAD 启用（监听状态）或正在说话（Recording状态）才写入预缓存
    final shouldWritePreCache = _vadEnabled || _wasSpeaking;
    if (shouldWritePreCache) {
      _preCache.write(dataFor16k);
      _preCacheWriteCount++;
      if (_preCacheWriteCount % 100 == 1) {
        final durationMs = _preCache.getAvailableDurationMs(AudioConfig.opusSampleRate);
        AppLogger.d('📝 预缓存写入 #$_preCacheWriteCount: vadEnabled=$_vadEnabled, wasSpeaking=$_wasSpeaking, 缓存时长=${durationMs}ms');
      }
    }

    // ========== 3. 处理 KWS/VAD ==========
    _processVadKws(dataForKws, dataFor16k);

    // ========== 4. VAD 状态检测与发送逻辑 ==========
    final isSpeaking = VoiceEngine.instance.isSpeaking;
    
    // 从静音变为说话：语音开始
    if (isSpeaking && !_wasSpeaking) {
      ProtocolService.instance.sendStartListening(mode: 'auto');
      
      // 语音开始 - 先发送预缓存数据（已经是 16k）
      final preCachedData = _preCache.readAll();
      if (preCachedData.isNotEmpty) {
        final durationMs = _preCache.getAvailableDurationMs(AudioConfig.opusSampleRate);
        AppLogger.i('Speech started - sending ${preCachedData.length} bytes (${durationMs}ms) pre-cached audio');
        _pcmBuffer.insertAll(0, preCachedData);
      }
    }
    
    // 从说话变为静音：语音结束
    if (!isSpeaking && _wasSpeaking) {
      AppLogger.i('Speech ended - flushing remaining ${_pcmBuffer.length} bytes');
      _flushBuffer();
      ProtocolService.instance.sendStopListening();
    }
    
    _wasSpeaking = isSpeaking;

    // ========== 5. 发送音频（使用 16k 数据） ==========
    if (isSpeaking) {
      // 缓冲区溢出保护：防止异常情况下内存无限增长
      if (_pcmBuffer.length + dataFor16k.length > _maxPcmBufferSize) {
        AppLogger.w('PCM buffer overflow (${_pcmBuffer.length} bytes), clearing to prevent memory leak');
        _pcmBuffer.clear();
      }
      
      // 添加 16k 数据到缓冲区
      _pcmBuffer.addAll(dataFor16k);

      // 当缓冲区有足够数据时进行 Opus 编码并发送
      int framesSent = 0;
      while (_pcmBuffer.length >= _opusBytesPerFrame) {
        _encodeAndSend();
        framesSent++;
      }
      
      if (framesSent > 0) {
        _totalFramesSent += framesSent;
        if (_totalFramesSent % 10 == 0) {
          AppLogger.d('已发送 $_totalFramesSent 帧音频');
        }
      }
    }
  }
  
  int _totalFramesSent = 0;  // 调试计数器
  
  /// 刷新发送缓冲区（发送剩余数据，不足一帧则补零）
  void _flushBuffer() {
    if (_pcmBuffer.isEmpty) return;
    
    // 补零凑够一帧（使用 16k 帧大小）
    while (_pcmBuffer.length < _opusBytesPerFrame) {
      _pcmBuffer.add(0);
    }
    
    // 发送最后一帧
    _encodeAndSend();
    
    // 清空剩余（如果还有的话）
    _pcmBuffer.clear();
  }
  


  /// 处理 VAD/KWS
  /// [dataForKws] KWS 使用的数据（麦克风原始采样率）
  /// [dataFor16k] VAD 使用的数据（16000Hz）
  static int _kwsLogCounter = 0;
  void _processVadKws(Uint8List dataForKws, Uint8List dataFor16k) {
    try {
      // 转换 KWS 数据：PCM 16-bit 到 Float32
      final kwsFloatData = _pcmToFloat32(dataForKws);
      
      // 转换 VAD 数据：PCM 16-bit 到 Float32（如果与 KWS 数据相同则复用）
      final vadFloatData = identical(dataForKws, dataFor16k) 
          ? kwsFloatData 
          : _pcmToFloat32(dataFor16k);

      // 每100次打印一次状态
      _kwsLogCounter++;
      if (_kwsLogCounter % 100 == 1) {
        AppLogger.d('KWS/VAD状态: kwsEnabled=$_kwsEnabled, vadEnabled=$_vadEnabled, '
            'kwsSamples=${kwsFloatData.length}, vadSamples=${vadFloatData.length}');
      }

      // 处理 KWS（原始采样率）和 VAD（16k）
      VoiceEngine.instance.processAudio(kwsFloatData, samplesForVad: vadFloatData);
    } catch (e) {
      AppLogger.e('Error processing VAD/KWS', e);
    }
  }
  
  /// PCM 16-bit 转 Float32
  Float32List _pcmToFloat32(Uint8List pcmData) {
    final length = pcmData.length - (pcmData.length % 2);
    final floatData = Float32List(length ~/ 2);
    
    for (int i = 0, j = 0; i < length; i += 2, j++) {
      final int16 = pcmData[i] | (pcmData[i + 1] << 8);
      final signed = int16 > 32767 ? int16 - 65536 : int16;
      floatData[j] = signed / 32768.0;
    }
    return floatData;
  }

  /// 编码并发送一帧音频
  /// 注意：缓冲区中的数据已经是 16k 采样率，无需重采样
  void _encodeAndSend() {
    if (_pcmBuffer.length < _opusBytesPerFrame) return;

    try {
      // 取出一帧数据（已经是 16k 采样率）
      final frameData = Uint8List.fromList(_pcmBuffer.sublist(0, _opusBytesPerFrame));
      _pcmBuffer.removeRange(0, _opusBytesPerFrame);

      // Opus 编码（直接编码 16k 数据）
      final encoded = OpusService.instance.encode(frameData);
      if (encoded == null) {
        AppLogger.w('Opus encoding returned null');
        return;
      }

      // 发送到服务端
      if (ProtocolService.instance.isConnected) {
        ProtocolService.instance.sendAudio(encoded);
      }
    } catch (e, stackTrace) {
      AppLogger.e('Error encoding/sending audio', e, stackTrace);
    }
  }

  /// 发送预缓存的音频数据（用于热词唤醒时发送历史音频）
  void sendPreCachedAudio() {
    final preCachedData = _preCache.readAll();
    final durationMs = _preCache.getAvailableDurationMs(AudioConfig.opusSampleRate);
    
    // 【诊断日志】记录发送预缓存时的详细信息
    AppLogger.w('🔊 发送预缓存: ${preCachedData.length} bytes, ${durationMs}ms, '
        'vadEnabled=$_vadEnabled, wasSpeaking=$_wasSpeaking, writeCount=$_preCacheWriteCount');
    
    if (preCachedData.isNotEmpty) {
      _pcmBuffer.insertAll(0, preCachedData);
    }
    
    // 重置写入计数，便于追踪下一轮
    _preCacheWriteCount = 0;
  }

  /// 释放资源
  Future<void> dispose() async {
    await stopProcessing();
    RecordService.instance.onAudioData = null;
    await RecordService.instance.dispose();
    OpusService.instance.dispose();
    _isInitialized = false;
    AppLogger.i('AudioProcessor disposed');
  }
}
