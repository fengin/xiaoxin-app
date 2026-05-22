/// XiaoXin APP - 音频状态管理
library;

import 'dart:async';
import '../../utils/logger.dart';

/// 音频状态管理器
/// 用于协调播放和录音状态，实现回音消除
class AudioStateManager {
  AudioStateManager._();

  static final AudioStateManager instance = AudioStateManager._();

  bool _isSystemAudioPlaying = false;
  DateTime? _playStartTime;

  final _stateController = StreamController<bool>.broadcast();

  /// 是否正在播放系统音频
  bool get isSystemAudioPlaying => _isSystemAudioPlaying;

  /// 音频状态变化流
  Stream<bool> get onStateChange => _stateController.stream;

  /// 播放时长（毫秒）
  int get audioPlayingDuration {
    if (_playStartTime == null) return 0;
    return DateTime.now().difference(_playStartTime!).inMilliseconds;
  }

  /// 设置系统音频播放状态
  void setSystemAudioPlaying(bool isPlaying) {
    if (_isSystemAudioPlaying == isPlaying) return;

    _isSystemAudioPlaying = isPlaying;

    if (isPlaying) {
      _playStartTime = DateTime.now();
      AppLogger.d('Audio playback started');
    } else {
      _playStartTime = null;
      AppLogger.d('Audio playback stopped');
    }

    _stateController.add(isPlaying);
  }

  /// 打断系统音频播放
  void interruptSystemAudio() {
    if (_isSystemAudioPlaying) {
      setSystemAudioPlaying(false);
      AppLogger.i('System audio interrupted');
    }
  }

  /// 释放资源
  void dispose() {
    _stateController.close();
  }
}
