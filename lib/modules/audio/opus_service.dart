/// XiaoXin APP - Opus 编解码服务
/// 使用 opus_flutter 进行 Opus 音频编解码
library;

import 'dart:typed_data';
import 'package:opus_flutter/opus_flutter.dart' as opus_flutter;
import 'package:opus_dart/opus_dart.dart';
import '../../utils/logger.dart';
import '../../utils/constants.dart';

/// Opus 编解码服务
class OpusService {
  OpusService._();

  static final OpusService instance = OpusService._();

  SimpleOpusEncoder? _encoder;
  SimpleOpusDecoder? _decoder;
  bool _isInitialized = false;

  /// 是否已初始化
  bool get isInitialized => _isInitialized;

  /// 初始化 Opus 编解码器
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      AppLogger.d('Initializing Opus codec...');

      // 使用 opus_flutter 加载动态库并初始化 opus_dart
      final lib = await opus_flutter.load();
      initOpus(lib);

      // 创建编码器（用于发送录音数据）
      // 16kHz, 单声道, 60ms 帧
      _encoder = SimpleOpusEncoder(
        sampleRate: AppConstants.audioSampleRate,
        channels: AppConstants.audioChannels,
        application: Application.voip,
      );

      // 创建解码器（用于接收服务端音频）
      // 服务端返回 24kHz
      _decoder = SimpleOpusDecoder(
        sampleRate: AppConstants.serverAudioSampleRate,
        channels: AppConstants.audioChannels,
      );

      _isInitialized = true;
      AppLogger.i('Opus codec initialized (version: ${getOpusVersion()})');
      return true;
    } catch (e, stackTrace) {
      AppLogger.e('Failed to initialize Opus codec', e, stackTrace);
      return false;
    }
  }

  /// 编码 PCM 数据为 Opus
  /// [pcmData]: 16-bit PCM 数据（little-endian）
  /// 返回: Opus 编码后的数据，失败返回 null
  Uint8List? encode(Uint8List pcmData) {
    if (!_isInitialized || _encoder == null) {
      AppLogger.w('Opus encoder not initialized');
      return null;
    }

    try {
      // 将 Uint8List 转换为 Int16List（PCM 16-bit）
      final int16Data = Int16List.view(pcmData.buffer);

      // 编码（SimpleOpusEncoder 接受 Int16List）
      final encoded = _encoder!.encode(input: int16Data);
      return encoded;
    } catch (e, stackTrace) {
      AppLogger.e('Opus encoding failed', e, stackTrace);
      return null;
    }
  }

  /// 解码 Opus 数据为 PCM
  /// [opusData]: Opus 编码的数据
  /// 返回: PCM 数据（Uint8List，包含 Int16 数据），失败返回 null
  Uint8List? decode(Uint8List opusData) {
    if (!_isInitialized || _decoder == null) {
      AppLogger.w('Opus decoder not initialized');
      return null;
    }

    try {
      // 解码
      final decodedData = _decoder!.decode(input: opusData);

      // SimpleOpusDecoder in opus_dart returns Int16List directly
      return Uint8List.view(decodedData.buffer);
    } catch (e, stackTrace) {
      AppLogger.e('Opus decoding failed', e, stackTrace);
      return null;
    }
  }

  /// 设置解码器采样率
  /// 当服务端协议握手返回不同采样率时调用
  void setDecoderSampleRate(int sampleRate) {
    if (_decoder != null) {
      try {
        _decoder!.destroy();
      } catch (e) {
        AppLogger.e('Error destroying existing Opus decoder', e);
      }
      _decoder = null;
    }

    try {
      _decoder = SimpleOpusDecoder(
        sampleRate: sampleRate,
        channels: AppConstants.audioChannels,
      );
      AppLogger.i('Opus decoder sample rate updated to: $sampleRate');
    } catch (e, stackTrace) {
      AppLogger.e('Failed to recreate Opus decoder with rate $sampleRate', e, stackTrace);
    }
  }

  /// 释放资源
  void dispose() {
    try {
      _encoder?.destroy();
      _encoder = null;
    } catch (e) {
      AppLogger.e('Error destroying Opus encoder', e);
    }

    try {
      _decoder?.destroy();
      _decoder = null;
    } catch (e) {
      AppLogger.e('Error destroying Opus decoder', e);
    }

    _isInitialized = false;
    AppLogger.i('OpusService disposed');
  }
}
