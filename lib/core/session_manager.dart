/// XiaoXin APP - 会话管理器
/// 管理完整的语音会话流程：连接 → 录音 → 发送 → 接收 → 播放
library;

import 'dart:async';
import 'dart:typed_data';
import '../modules/protocol/protocol_service.dart';
import '../modules/protocol/messages.dart';
import '../modules/audio/audio_service.dart';
import '../modules/audio/audio_state_manager.dart';
import '../modules/audio/audio_player_service.dart';
import '../modules/audio/audio_processor.dart';
import '../modules/mcp/mcp_handler.dart';
import 'device_state.dart';
import '../utils/logger.dart';

/// 会话状态变化回调
typedef OnSessionStateChanged = void Function(DeviceState state);

/// STT 文本回调
typedef OnSttTextReceived = void Function(String text);

/// LLM 文本回调
typedef OnLlmTextReceived = void Function(String text, String? emotion);

/// TTS 开始回调
typedef OnTtsStart = void Function();

/// TTS 分句回调
typedef OnTtsSentence = void Function(String text);

/// TTS 结束回调
typedef OnTtsStop = void Function();

/// 会话管理器
class SessionManager {
  SessionManager._();

  static final SessionManager instance = SessionManager._();

  bool _isInitialized = false;
  DeviceState _currentState = DeviceState.idle;
  String? _currentSessionId;
  bool _isSpeaking = false; // TTS 正在播放
  Timer? _voiceEngineCheckTimer; // VoiceEngine就绪检测定时器

  // 回调
  OnSessionStateChanged? onStateChanged;
  OnSttTextReceived? onSttText;
  OnLlmTextReceived? onLlmText;

  // TTS 事件回调
  OnTtsStart? onTtsStart;
  OnTtsSentence? onTtsSentence;
  OnTtsStop? onTtsStop;

  /// 语音引擎就绪回调（模型加载完成时触发）
  void Function()? onVoiceEngineReady;

  /// 当前状态
  DeviceState get currentState => _currentState;

  /// 当前会话 ID
  String? get sessionId => _currentSessionId;

  /// 是否正在播放 TTS
  bool get isSpeaking => _isSpeaking;

  /// 是否有麦克风权限
  bool get hasPermission => AudioService.instance.hasPermission;

  /// VoiceEngine 是否就绪
  bool get isVoiceEngineReady => AudioService.instance.isVoiceEngineReady;

  /// 初始化语音系统
  /// 在 main.dart 中调用，不需要 BuildContext
  Future<bool> initialize() async {
    if (_isInitialized) return hasPermission;

    try {
      AppLogger.d('Initializing SessionManager...');

      // 初始化音频服务（内部并行初始化，异步加载模型）
      final hasPermission = await AudioService.instance.initialize();

      // 设置协议回调
      _setupProtocolCallbacks();

      // 设置热词检测回调
      AudioService.instance.setKeywordDetectedCallback(_onKeywordDetected);

      // 【注意】KWS 不在初始化时自动启动，由业务调用 startKws() 决定何时启动

      _isInitialized = true;
      _setState(DeviceState.idle);
      AppLogger.i('SessionManager initialized (permission=$hasPermission)');

      // 等待 VoiceEngine 就绪后触发回调
      _waitForVoiceEngineReady();

      return hasPermission;
    } catch (e, stackTrace) {
      AppLogger.e('Failed to initialize SessionManager', e, stackTrace);
      return false;
    }
  }

  /// 启动 KWS（常驻热词检测）
  /// 由业务层决定何时调用，如：
  /// - 原生对话界面启动时
  /// - H5 通过接口调用时
  Future<bool> startKws() async {
    if (!_isInitialized) {
      AppLogger.w('SessionManager not initialized, cannot start KWS');
      return false;
    }

    try {
      // 启动录音
      final recordingStarted = await AudioService.instance.startRecording();
      if (!recordingStarted) {
        AppLogger.e('Failed to start recording for KWS');
        return false;
      }

      // 启用 KWS，禁用 VAD（VAD 在热词唤醒后启用）
      AudioService.instance.enableKws(true);
      AudioService.instance.enableVad(false);

      AppLogger.i('KWS started, waiting for wake word');
      return true;
    } catch (e, stackTrace) {
      AppLogger.e('Failed to start KWS', e, stackTrace);
      return false;
    }
  }

  /// 停止 KWS
  void stopKws() {
    AudioService.instance.enableKws(false);
    AudioService.instance.enableVad(false);
    AudioService.instance.stopRecording();
    AppLogger.i('KWS stopped');
  }

  /// 设置协议回调
  void _setupProtocolCallbacks() {
    final protocol = ProtocolService.instance;

    protocol.onConnected = _onConnected;
    protocol.onDisconnected = _onDisconnected;
    protocol.onError = _onError;
    protocol.onJsonMessage = _onJsonMessage;
    protocol.onAudioData = _onAudioData;
  }

  /// 开始语音交互
  Future<bool> startSession() async {
    if (!_isInitialized) {
      AppLogger.e('SessionManager not initialized');
      return false;
    }

    // 只有在 idle 或 error 状态才允许启动新会话
    if (_currentState != DeviceState.idle &&
        _currentState != DeviceState.error) {
      AppLogger.w('Session already in progress (state: $_currentState)');
      return false;
    }

    try {
      _setState(DeviceState.connecting);

      // 建立 WebSocket 连接
      final connected = await ProtocolService.instance.openAudioChannel();
      if (!connected) {
        _setState(DeviceState.error);
        return false;
      }

      return true;
    } catch (e, stackTrace) {
      AppLogger.e('Failed to start session', e, stackTrace);
      _setState(DeviceState.error);
      return false;
    }
  }

  /// 停止语音交互
  /// 按顺序：1) 中止 VAD  2) 发 abort  3) 发 listen stop  4) 关闭 WebSocket
  /// 注意：保持 KWS 常驻监听
  Future<void> stopSession() async {
    if (_currentSessionId == null) {
      AppLogger.w('No active session to stop');
      return;
    }

    try {
      // 1. 中止 VAD 检测
      await AudioService.instance.enableVad(false);

      // 2. 停止播放，清空播放队列
      await AudioService.instance.stopPlayback();

      // 3. 清空录音发送队列
      AudioService.instance.clearBuffers();

      // 4. 发送 abort 打断信号
      ProtocolService.instance.sendAbortSpeaking(reason: 'user_stop');

      // 5. 发送 listen stop 信号
      ProtocolService.instance.sendStopListening();

      // 6. 关闭 WebSocket 连接
      await ProtocolService.instance.closeAudioChannel();

      // 7. 清理会话状态
      _currentSessionId = null;
      _isSpeaking = false;

      // 8. 保持 KWS 活跃（恢复到 idle 状态的 KWS 监听）
      AudioService.instance.enableKws(true);

      _setState(DeviceState.idle);

      AppLogger.i(
        'Session stopped (abort + listen stop + close), KWS still active',
      );
    } catch (e, stackTrace) {
      AppLogger.e('Failed to stop session', e, stackTrace);
    }
  }

  /// 打断当前播放（手动或热词唤醒）
  Future<void> abortSpeaking({String reason = 'user_action'}) async {
    if (!_isSpeaking) return;

    try {
      // 停止播放
      await AudioService.instance.stopPlayback();

      // 发送打断消息
      ProtocolService.instance.sendAbortSpeaking(reason: reason);

      _isSpeaking = false;

      // 恢复 VAD（enableVad 内部会自动恢复录音）
      await AudioService.instance.enableVad(true);

      _setState(DeviceState.listening);

      AppLogger.i('Speaking aborted: $reason');
    } catch (e, stackTrace) {
      AppLogger.e('Failed to abort speaking', e, stackTrace);
    }
  }

  /// WebSocket 连接成功回调
  void _onConnected() {
    _currentSessionId = ProtocolService.instance.sessionId;
    AppLogger.i('Session connected: $_currentSessionId');

    // 设置播放采样率
    final sampleRate = ProtocolService.instance.serverSampleRate;
    AudioService.instance.setPlaybackSampleRate(sampleRate);
    AppLogger.i('Audio playback sample rate set to: $sampleRate');

    // 开始录音
    _startListening();
  }

  /// WebSocket 断开回调
  void _onDisconnected() async {
    AppLogger.i('Session disconnected');

    // 清理会话状态
    _currentSessionId = null;
    _isSpeaking = false;

    // 【重要】不清空播放队列，让告别语等音频自然播完
    // ESP32 设计：断开连接不影响正在播放的音频
    // AudioService.instance.stopPlayback();  // 已移除

    // 清除系统音频播放状态
    AudioStateManager.instance.setSystemAudioPlaying(false);

    // 恢复到 Idle 状态，等待热词唤醒
    _setState(DeviceState.idle);

    // 确保 KWS 仍然活跃
    AudioService.instance.enableKws(true);
    AudioService.instance.enableVad(false); // VAD 在 idle 状态下禁用

    // 【修复】不需要 resumeRecording()
    // 因为 just_audio 已配置 handleAudioSessionActivation: false
    // 播放器不会请求音频焦点，录音会持续运行

    // 注意：服务端可能因超时主动断开连接（发送告别语后关闭 WebSocket）
    // 不自动重连，等待用户通过热词或按钮触发新会话
    AppLogger.i('Session ended, KWS enabled');
  }

  /// WebSocket 错误回调
  void _onError(String message) {
    AppLogger.e('Session error: $message');
    _setState(DeviceState.error);
  }

  /// 处理 JSON 消息
  void _onJsonMessage(dynamic message) {
    if (message is TtsMessage) {
      _handleTtsMessage(message);
    } else if (message is SttMessage) {
      _handleSttMessage(message);
    } else if (message is LlmMessage) {
      _handleLlmMessage(message);
    } else if (message is McpMessage) {
      McpHandler.instance.handleMcpMessage(message);
    } else if (message is SystemMessage) {
      _handleSystemMessage(message);
    }
  }

  /// 只在 Speaking 状态下接收音频
  void _onAudioData(Uint8List data) {
    if (_currentState != DeviceState.speaking) {
      return;
    }
    AudioService.instance.playOpusAudio(data);
  }



  /// 处理 TTS 消息（ESP32 简单逻辑）
  /// - tts start: 清空队列，禁用 VAD
  /// - tts stop: 切换到 Listening，等待播放完成后再按会话状态恢复 VAD
  Future<void> _handleTtsMessage(TtsMessage message) async {
    if (message.isStart) {
      // 【状态保护】如果已经在 speaking 状态，忽略重复的 tts start
      if (_isSpeaking) {
        AppLogger.w('Ignoring duplicate tts start while already speaking');
        return;
      }

      // TTS 开始：切换到 Speaking，禁用 VAD
      _isSpeaking = true;
      _setState(DeviceState.speaking);

      // 【优化】只在播放缓冲区有残留数据时才重建播放器
      // feedCount > 0 表示上一轮被打断，有未播放完的数据需要清空
      // feedCount == 0 表示上一轮已正常播完，无需重建（避免 1-2s 延迟）
      final residualFrames = AudioPlayerService.instance.feedCount;
      if (residualFrames > 0) {
        AppLogger.w(
          '⚠️ TTS start: 检测到残留音频 (feedCount=$residualFrames)，重建播放器清空缓冲区',
        );
        await AudioService.instance.stopPlayback();
      } else {
        AppLogger.i('TTS start: 缓冲区为空，跳过播放器重建');
      }

      AudioService.instance.enableVad(false);
      AudioStateManager.instance.setSystemAudioPlaying(true);
      onTtsStart?.call();
      AppLogger.i('TTS started, VAD disabled');
    } else if (message.isStop) {
      // 【状态保护】只有在 speaking 状态（_isSpeaking=true）才处理 tts stop
      // 如果当前不在 speaking 状态（比如用户已经在说话，状态是 listening），
      // 说明这是一个延迟到达的或意外的 tts stop 消息，应忽略
      if (!_isSpeaking) {
        AppLogger.w(
          'Ignoring tts stop while not speaking (currentState=$_currentState)',
        );
        return;
      }

      // TTS 结束：等待播放缓冲区播放完毕后再启用 VAD，避免回音
      _isSpeaking = false;
      _setState(DeviceState.listening);
      onTtsStop?.call();
      AppLogger.i(
        'TTS stop received, waiting for playback complete before enabling VAD',
      );

      // 标记流结束，等待播放完成后启用 VAD。
      // 如果服务端已断开会话（例如退出对话的告别语），该回调会晚于
      // _onDisconnected() 触发，此时不能把 VAD 重新打开。
      final playbackSessionId = _currentSessionId;
      AudioPlayerService.instance.markStreamEnd(() {
        // 【重要】只清空发送缓冲区，不清空预缓存
        // 预缓存需要保留，用于 VAD 检测到语音开始时补偿语音开头
        AudioProcessor.instance.clearSendBuffer();

        final canResumeVad =
            playbackSessionId != null &&
            playbackSessionId == _currentSessionId &&
            ProtocolService.instance.isConnected &&
            _currentState == DeviceState.listening;
        if (!canResumeVad) {
          AudioService.instance.enableVad(false);
          return;
        }

        AudioService.instance.enableVad(true);
      });
    } else if (message.isSentenceStart && message.text != null) {
      AppLogger.d('TTS sentence: ${message.text}');
      onTtsSentence?.call(message.text!);
      onLlmText?.call(message.text!, null);
    }
  }

  /// 处理 STT 消息
  void _handleSttMessage(SttMessage message) {
    AppLogger.i('STT: ${message.text}');
    onSttText?.call(message.text);
  }

  /// 处理 LLM 消息
  void _handleLlmMessage(LlmMessage message) {
    if (message.text != null) {
      AppLogger.d('LLM: ${message.text}');
      onLlmText?.call(message.text!, message.emotion);
    }
  }

  /// 处理系统消息
  void _handleSystemMessage(SystemMessage message) {
    AppLogger.i('System command: ${message.command}');
    // 处理系统命令（如重启、关机等）
  }

  /// 开始录音和监听
  /// 注意：录音已在 initialize() 时启动，此处只需启用 VAD 并通知服务端
  Future<void> _startListening() async {
    try {
      // 【修正】不在会话开始时发送 listen start
      // listen start 由 audio_processor 在 VAD 检测到语音开始时发送
      // 这样每次对话（而不是每次会话）都有独立的 listen start/stop

      // 启用 VAD（录音已在 initialize 时启动）
      AudioService.instance.enableVad(true);

      _setState(DeviceState.listening);
      AppLogger.i('Listening started, VAD enabled');
    } catch (e, stackTrace) {
      AppLogger.e('Failed to start listening', e, stackTrace);
      _setState(DeviceState.error);
    }
  }

  /// 热词检测回调
  Future<void> _onKeywordDetected(String keyword) async {
    AppLogger.i('Keyword detected: $keyword, currentState=$_currentState');

    // 1. 如果正在播放，打断
    if (_isSpeaking) {
      AppLogger.w('🔊 热词打断 TTS 播放 - currentState=$_currentState');
      await AudioService.instance.stopPlayback();
      ProtocolService.instance.sendAbortSpeaking(reason: 'wake_word');
      _isSpeaking = false;
      AudioStateManager.instance.setSystemAudioPlaying(false);
    }

    // 2. 根据当前状态决定行为
    switch (_currentState) {
      case DeviceState.idle:
        // 无会话，建立新连接
        AppLogger.i('Starting new session');
        // 先建立会话，连接成功后 _onConnected 会被调用
        // 但我们需要在连接后发送热词信息，所以这里可能需要特殊的处理或标志
        // 简单起见，startSession 内部建立连接后，我们可以在这里直接等待（如果 startSession 改为返回 Future<bool>）

        // 由于 startSession 是异步的且不等待连接完成，我们需要一个机制在连接后发送
        // 这里暂时先发送，如果未连接 ProtocolService 会忽略（需要改进）
        // 更好的做法：startSession 改为 async 并等待连接

        // 暂时方案：先启动，连接成功回调里无法区分是热词启动还是普通启动
        // 修正方案：startSession 添加 isWakeWord 参数？
        // 或者：直接在这里等待连接

        _handleWakeWordSessionStart(keyword);
        break;
      case DeviceState.listening:
        // 已有会话且在监听中
        // 【重要】不发送 detected 消息，因为：
        // 1. VAD 已在工作，音频持续发送到服务端
        // 2. 服务端会进行 ASR，得到完整识别结果（热词+后续命令）
        // 3. 发送 detected 会导致服务端把热词单独处理，截断用户输入
        AppLogger.i(
          'Keyword detected in listening state - ignoring (VAD already handling audio)',
        );

        // 也不需要发送预缓存，VAD 已经在持续发送音频了
        //ProtocolService.instance.sendWakeWordDetected(keyword);
        // listening 状态下发送预缓存（支持"热词+命令"一体化）
        //AudioService.instance.sendPreCachedAudio();
        // 确保 VAD 启用（方法内部会判断，如果已启用则不重置 _wasSpeaking）
        AudioService.instance.enableVad(true);
        break;
      case DeviceState.speaking:
        // 播放中唤醒，切换到监听状态
        _setState(DeviceState.listening);

        // 发送热词检测消息
        ProtocolService.instance.sendWakeWordDetected(keyword);

        // 热词打断时不发送预缓存（speaking期间预缓存不写入，发送的是旧数据/回音）
        // 一般音频在播放时，喊热词仅仅目的是为了打断播放，不会增加后续的命令要求
        // AudioService.instance.sendPreCachedAudio();
        AudioProcessor.instance.clearBuffers(); // 清空预缓存，避免污染后续录音

        AudioService.instance.enableVad(true);
        AppLogger.i('Switched to listening after wake word interrupt');
        break;
      case DeviceState.connecting:
        // 正在连接中
        AppLogger.i('Wake word during connecting - waiting');
        break;
      default:
        // 其他状态（error 等）尝试重新开始
        AppLogger.w('Wake word in state $_currentState - restarting session');
        _handleWakeWordSessionStart(keyword);
    }
  }

  /// 处理热词启动会话
  Future<void> _handleWakeWordSessionStart(String keyword) async {
    final success = await startSession();
    if (success) {
      // 连接建立成功后，发送热词信息
      // 注意：startSession 内部可能已经发送了 hello
      // 我们需要确保在 hello 之后，listen start 之前？
      // startSession 内部调用了 _startListening，它发送了 listen start

      // 实际上，如果是热词启动，我们应该让服务端知道
      // 这里的时序有点复杂。
      // 简单做法：连接成功后（startSession await 返回 true），立即发送热词信息
      ProtocolService.instance.sendWakeWordDetected(keyword);
      AudioService.instance.sendPreCachedAudio();
    }
  }

  /// 设置状态
  void _setState(DeviceState state) {
    if (_currentState == state) return;

    final previous = _currentState;
    _currentState = state;

    AppLogger.i('Session state: ${previous.name} -> ${state.name}');
    onStateChanged?.call(state);
  }

  /// 等待 VoiceEngine 就绪并触发回调
  /// 采用轮询检查，避免复杂的回调链
  void _waitForVoiceEngineReady() {
    if (isVoiceEngineReady) {
      // 已就绪，立即触发
      AppLogger.i('VoiceEngine already ready, triggering callback');
      onVoiceEngineReady?.call();
      return;
    }

    // 轮询检查（每 500ms 检查一次，最多等待 60 秒）
    int attempts = 0;
    const maxAttempts = 120; // 60 秒

    _voiceEngineCheckTimer?.cancel();
    _voiceEngineCheckTimer = Timer.periodic(const Duration(milliseconds: 500), (
      timer,
    ) {
      attempts++;
      if (isVoiceEngineReady) {
        timer.cancel();
        _voiceEngineCheckTimer = null;
        AppLogger.i('VoiceEngine ready after ${attempts * 500}ms');
        onVoiceEngineReady?.call();
      } else if (attempts >= maxAttempts) {
        timer.cancel();
        _voiceEngineCheckTimer = null;
        AppLogger.w(
          'VoiceEngine not ready after ${maxAttempts * 500}ms, giving up',
        );
      }
    });
  }

  /// 释放资源
  Future<void> dispose() async {
    _voiceEngineCheckTimer?.cancel();
    _voiceEngineCheckTimer = null;
    await stopSession();
    AudioService.instance.setKeywordDetectedCallback(null);
    await AudioService.instance.dispose();
    _isInitialized = false;
    AppLogger.i('SessionManager disposed');
  }
}
