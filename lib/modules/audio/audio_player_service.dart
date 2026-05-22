/// XiaoXin APP - 音频播放服务
/// 使用 flutter_pcm_sound 直接播放 PCM 数据流
library;

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'opus_service.dart';
import '../../utils/logger.dart';
import '../protocol/protocol_service.dart';

/// 播放完成回调
typedef OnPlaybackCompleteCallback = void Function();

/// 音频播放服务
/// 直接将 Opus 解码后的 PCM 数据推送到音频输出，类似 ESP32 的 DAC 播放
class AudioPlayerService {
  AudioPlayerService._();
  static final AudioPlayerService instance = AudioPlayerService._();

  int _sampleRate = 16000;
  bool _isInitialized = false;
  bool _isReady = false;  // 是否准备好接收数据（防止 stopPlayback 期间的竞态）
  
  // 播放完成检测相关
  bool _waitingForPlaybackComplete = false;
  OnPlaybackCompleteCallback? _onPlaybackComplete;
  Timer? _fallbackTimer;  // 兜底定时器
  int _feedCount = 0;  // 记录 feed 次数，用于判断是否有音频

  /// 是否已初始化
  bool get isInitialized => _isInitialized;

  /// 当前已 feed 的帧数（用于判断缓冲区是否有残留数据）
  int get feedCount => _feedCount;

  /// 初始化播放器
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 禁用插件的详细日志
      FlutterPcmSound.setLogLevel(LogLevel.none);
      
      // 设置 PCM 播放参数：16位，单声道
      await FlutterPcmSound.setup(sampleRate: _sampleRate, channelCount: 1);
      
      // 设置低缓冲阈值以实现低延迟
      await FlutterPcmSound.setFeedThreshold(8000); // 约 0.5 秒缓冲
      
      // 设置 feed 回调，用于检测播放完成
      FlutterPcmSound.setFeedCallback(_onFeedCallback);
      
      _isInitialized = true;
      _isReady = true;
      AppLogger.i('AudioPlayerService initialized (sampleRate: $_sampleRate)');
    } catch (e, stackTrace) {
      AppLogger.e('Failed to initialize AudioPlayerService', e, stackTrace);
    }
  }
  
  /// Feed 回调处理
  /// 当缓冲区低于阈值时触发，如果正在等待播放完成且没有新数据，则触发完成回调
  void _onFeedCallback(int remainingSamples) {
    if (_waitingForPlaybackComplete && remainingSamples == 0) {
      _triggerPlaybackComplete();
    }
  }
  
  /// 触发播放完成
  void _triggerPlaybackComplete() {
    if (!_waitingForPlaybackComplete) return;
    
    _waitingForPlaybackComplete = false;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    
    // 【诊断日志】记录播放完成时间和 feed 次数
    AppLogger.w('⏱️ feedCallback 检测播放完成: feedCount=$_feedCount (${_feedCount * 60}ms 音频)');
    
    _feedCount = 0;  // 重置 feed 计数，为下一次 TTS 准备
    _onPlaybackComplete?.call();
    _onPlaybackComplete = null;
  }

  /// 设置采样率
  Future<void> setSampleRate(int sampleRate) async {
    if (_sampleRate == sampleRate) return;
    
    _sampleRate = sampleRate;
    AppLogger.i('AudioPlayerService sample rate set to: $sampleRate');
    
    // 同步更新 Opus 解码器采样率
    OpusService.instance.setDecoderSampleRate(sampleRate);
    
    if (_isInitialized) {
      // 重新设置播放参数
      _isReady = false;
      await FlutterPcmSound.setup(sampleRate: sampleRate, channelCount: 1);
      _isReady = true;
    }
  }

  /// 播放 Opus 数据
  /// 解码 Opus → PCM → 直接推送到音频输出
  Future<void> playOpusData(Uint8List opusData) async {
    if (!_isInitialized || !_isReady) {
      // 如果没初始化或正在重置，忽略这帧数据
      return;
    }

    // 解码 Opus 到 PCM
    final pcmData = OpusService.instance.decode(opusData);
    if (pcmData == null) {
      AppLogger.w('Failed to decode Opus data');
      return;
    }

    // 性能日志：首包播放时间
    // 性能日志：首包播放时间
    if (_feedCount == 0) {
      AppLogger.d('[Performance] [${ProtocolService.instance.sessionId ?? 'unknown_session'}] [Client_Play_First] time=${DateTime.now().millisecondsSinceEpoch}');
    }

    // 将 PCM 数据直接推送到音频输出
    try {
      // 将 Uint8List (PCM 16-bit) 转换为 Int16List
      final int16List = pcmData.buffer.asInt16List();
      await FlutterPcmSound.feed(PcmArrayInt16.fromList(int16List.toList()));
      _feedCount++;
    } catch (e, stackTrace) {
      AppLogger.e('Failed to feed PCM data', e, stackTrace);
      
      // 【防御性恢复】检测 "must call setup first" 错误，自动重新初始化播放器
      if (e.toString().contains('must call setup first') || 
          e.toString().contains('Setup')) {
        AppLogger.w('⚠️ 检测到播放器未初始化错误，尝试重新初始化...');
        _isReady = false;
        try {
          await FlutterPcmSound.setup(sampleRate: _sampleRate, channelCount: 1);
          await FlutterPcmSound.setFeedThreshold(8000);
          FlutterPcmSound.setFeedCallback(_onFeedCallback);
          _isReady = true;
          _feedCount = 0;
          AppLogger.i('✅ 播放器重新初始化成功');
        } catch (reinitError) {
          AppLogger.e('❌ 播放器重新初始化失败', reinitError);
        }
      }
    }
  }
  
  /// 标记 TTS 流结束，等待播放完成后触发回调
  /// 调用此方法后，当播放缓冲区播放完毕时会触发 onComplete 回调
  void markStreamEnd(OnPlaybackCompleteCallback onComplete) {
    _waitingForPlaybackComplete = true;
    _onPlaybackComplete = onComplete;
    
    // 【诊断日志】记录 tts stop 时间和已 feed 的音频量
    AppLogger.w('⏱️ 收到 tts stop，等待播放完成: feedCount=$_feedCount (${_feedCount * 60}ms 音频待播)');
    
    // 如果没有任何音频被 feed，直接触发完成回调
    if (_feedCount == 0) {
      AppLogger.i('No audio was fed, triggering complete immediately');
      // 使用短延迟确保状态一致
      Future.delayed(const Duration(milliseconds: 100), _triggerPlaybackComplete);
      return;
    }
    
    // 兜底：如果 2 秒后仍未触发，强制触发（防止 feedCallback 不工作的情况）
    _fallbackTimer?.cancel();
    _fallbackTimer = Timer(const Duration(seconds: 2), () {
      if (_waitingForPlaybackComplete) {
        AppLogger.w('Playback complete fallback triggered');
        _triggerPlaybackComplete();
      }
    });
  }

  /// 停止播放并清空缓冲区
  Future<void> stopPlayback() async {
    if (!_isInitialized) return;
    
    // 标记为不可用，防止竞态条件
    _isReady = false;
    
    // 取消等待播放完成
    _waitingForPlaybackComplete = false;
    _onPlaybackComplete = null;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    // 注意：_feedCount 在 setup 完成后才重置，避免竞态条件
    
    try {
      // 释放并重新初始化以清空缓冲区
      await FlutterPcmSound.release();
      await FlutterPcmSound.setup(sampleRate: _sampleRate, channelCount: 1);
      await FlutterPcmSound.setFeedThreshold(8000);
      FlutterPcmSound.setFeedCallback(_onFeedCallback);
      _feedCount = 0;  // setup 完成后再重置 feed 计数
      _isReady = true;  // 重新标记为可用
      AppLogger.d('Playback stopped and buffer cleared');
    } catch (e, stackTrace) {
      AppLogger.e('Failed to stop playback', e, stackTrace);
      _isReady = true;  // 即使失败也要恢复，否则播放器将永久不可用
    }
  }

  /// 释放资源
  Future<void> dispose() async {
    if (!_isInitialized) return;
    
    _isReady = false;
    _waitingForPlaybackComplete = false;
    _onPlaybackComplete = null;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    _feedCount = 0;
    
    try {
      await FlutterPcmSound.release();
      _isInitialized = false;
      AppLogger.i('AudioPlayerService disposed');
    } catch (e, stackTrace) {
      AppLogger.e('Failed to dispose AudioPlayerService', e, stackTrace);
    }
  }
}
