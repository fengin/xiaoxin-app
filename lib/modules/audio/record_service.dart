/// XiaoXin APP - 录音服务
/// 使用 record 插件进行流式 PCM 录音
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:record/record.dart';
import '../../utils/logger.dart';
import '../../utils/constants.dart';
import '../settings/config_service.dart';

/// 音频数据回调
typedef OnAudioDataCallback = void Function(Uint8List pcmData);

/// 录音服务
class RecordService {
  RecordService._();

  static final RecordService instance = RecordService._();

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _recordSubscription;

  bool _isRecording = false;
  int _dataCounter = 0; // 诊断计数器

  /// 音频数据回调
  OnAudioDataCallback? onAudioData;

  /// 是否正在录音
  bool get isRecording => _isRecording;

  /// 检查录音权限
  Future<bool> hasPermission() async {
    return await _recorder.hasPermission();
  }

  /// 开始录音
  Future<bool> startRecording() async {
    if (_isRecording) {
      AppLogger.w('Already recording');
      return true;
    }

    try {
      // 检查权限
      if (!await hasPermission()) {
        AppLogger.e('Microphone permission not granted');
        return false;
      }

      // 配置录音参数
      // 使用配置的麦克风采样率
      final micSampleRate = ConfigService.instance.micSampleRate;
      final config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: micSampleRate,
        numChannels: AppConstants.audioChannels,
        // 使用较小的缓冲区以降低延迟
        autoGain: true,
        //echoCancel: true, // 启用系统回声消除，提高播放期间热词检测准确性
        echoCancel: !Platform.isIOS, // iOS 使用 voiceChat 模式的系统级回音消除
        noiseSuppress: true,
      );

      // 开始流式录音
      final stream = await _recorder.startStream(config);

      _recordSubscription = stream.listen(
        (data) {
          _dataCounter++;
          // 每 100 次回调打印一次（约每秒）
          if (_dataCounter % 100 == 0) {
            AppLogger.d('RecordService: data callback #$_dataCounter, size=${data.length}');
          }
          onAudioData?.call(data);
        },
        onError: (error) {
          AppLogger.e('Recording error', error);
        },
        onDone: () {
          AppLogger.i('Recording stream done - THIS SHOULD NOT HAPPEN DURING SESSION');
        },
      );

      _isRecording = true;
      AppLogger.i('Recording started (sampleRate: $micSampleRate)');
      return true;
    } catch (e, stackTrace) {
      AppLogger.e('Failed to start recording', e, stackTrace);
      return false;
    }
  }

  /// 停止录音
  Future<void> stopRecording() async {
    if (!_isRecording) {
      return;
    }

    try {
      await _recordSubscription?.cancel();
      _recordSubscription = null;

      await _recorder.stop();

      _isRecording = false;
      AppLogger.i('Recording stopped');
    } catch (e, stackTrace) {
      AppLogger.e('Failed to stop recording', e, stackTrace);
    }
  }

  /// 暂停录音
  Future<void> pauseRecording() async {
    if (!_isRecording) return;

    try {
      await _recorder.pause();
      AppLogger.d('Recording paused');
    } catch (e) {
      AppLogger.e('Failed to pause recording', e);
    }
  }

  /// 恢复录音
  Future<void> resumeRecording() async {
    if (!_isRecording) return;

    try {
      await _recorder.resume();
      AppLogger.d('Recording resumed');
    } catch (e) {
      AppLogger.e('Failed to resume recording', e);
    }
  }

  /// 释放资源
  Future<void> dispose() async {
    await stopRecording();
    _recorder.dispose();
    onAudioData = null;
    AppLogger.i('RecordService disposed');
  }
}
