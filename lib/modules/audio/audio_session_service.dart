/// XiaoXin APP - 音频会话配置
/// 配置 Android/iOS 音频会话，允许录音和播放同时进行
library;

import 'package:audio_session/audio_session.dart';
import '../../utils/logger.dart';

/// 音频会话服务
/// 解决录音和播放的音频焦点冲突问题
class AudioSessionService {
  AudioSessionService._();
  
  static final AudioSessionService instance = AudioSessionService._();
  
  AudioSession? _session;
  bool _isConfigured = false;
  
  /// 初始化音频会话配置
  /// 应在应用启动时调用，在 AudioService 初始化之前
  Future<void> initialize() async {
    if (_isConfigured) {
      AppLogger.w('AudioSession already configured');
      return;
    }
    
    try {
      _session = await AudioSession.instance;
      
      // 配置音频会话：允许同时录音和播放
      await _session!.configure(AudioSessionConfiguration(
        // Android 配置
        // 使用 media 模式而非 voiceCommunication，确保从扬声器播放
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.media,  // media 模式使用扬声器
          flags: AndroidAudioFlags.none,
        ),
        // Android 音频焦点配置
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        // 允许后台播放
        androidWillPauseWhenDucked: false,
        
        // iOS 配置（playAndRecord 模式允许同时录音和播放）
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        // defaultToSpeaker: 默认使用扬声器而非听筒
        // allowBluetooth: 允许蓝牙设备
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.defaultToSpeaker |
            AVAudioSessionCategoryOptions.allowBluetooth,
        // spokenAudio: 适用于语音内容（voiceChat 与 flutter_pcm_sound 冲突）
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
        avAudioSessionRouteSharingPolicy:
            AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
      ));
      
      // 监听音频焦点变化（用于调试）
      _session!.interruptionEventStream.listen((event) {
        AppLogger.i('AudioSession interruption: begin=${event.begin}, type=${event.type}');
      });
      
      _session!.becomingNoisyEventStream.listen((_) {
        AppLogger.i('AudioSession: becoming noisy (headphones unplugged)');
      });
      
      _isConfigured = true;
      AppLogger.i('AudioSession configured for playAndRecord with mixWithOthers');
      
    } catch (e, stackTrace) {
      AppLogger.e('Failed to configure AudioSession', e, stackTrace);
    }
  }
  
  /// 激活音频会话
  Future<void> setActive(bool active) async {
    try {
      await _session?.setActive(active);
      AppLogger.d('AudioSession active=$active');
    } catch (e) {
      AppLogger.e('Failed to set AudioSession active', e);
    }
  }
  
  /// 释放资源
  Future<void> dispose() async {
    await setActive(false);
  }
}
