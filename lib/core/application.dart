/// XiaoXin APP - 应用控制器
library;

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'device_state.dart';
import '../utils/logger.dart';

/// 应用控制器状态
class ApplicationState {
  final DeviceState deviceState;
  final ListeningMode listeningMode;
  final bool isVoiceDetected;
  final String? lastWakeWord;
  final String? sessionId;
  final String? errorMessage;

  const ApplicationState({
    this.deviceState = DeviceState.unknown,
    this.listeningMode = ListeningMode.autoStop,
    this.isVoiceDetected = false,
    this.lastWakeWord,
    this.sessionId,
    this.errorMessage,
  });

  ApplicationState copyWith({
    DeviceState? deviceState,
    ListeningMode? listeningMode,
    bool? isVoiceDetected,
    String? lastWakeWord,
    String? sessionId,
    String? errorMessage,
  }) {
    return ApplicationState(
      deviceState: deviceState ?? this.deviceState,
      listeningMode: listeningMode ?? this.listeningMode,
      isVoiceDetected: isVoiceDetected ?? this.isVoiceDetected,
      lastWakeWord: lastWakeWord ?? this.lastWakeWord,
      sessionId: sessionId ?? this.sessionId,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// 应用控制器 Notifier
class ApplicationNotifier extends StateNotifier<ApplicationState> {
  ApplicationNotifier() : super(const ApplicationState());

  // 状态变更事件流
  final _stateEventController = StreamController<DeviceStateEvent>.broadcast();
  Stream<DeviceStateEvent> get stateEventStream => _stateEventController.stream;

  /// 设置设备状态
  void setDeviceState(DeviceState newState) {
    if (state.deviceState == newState) return;

    final previousState = state.deviceState;
    state = state.copyWith(deviceState: newState);

    AppLogger.i('STATE: ${previousState.name} -> ${newState.name}');

    _stateEventController.add(DeviceStateEvent(
      previousState: previousState,
      currentState: newState,
    ));
  }

  /// 设置监听模式
  void setListeningMode(ListeningMode mode) {
    state = state.copyWith(listeningMode: mode);
    setDeviceState(DeviceState.listening);
  }

  /// 设置语音检测状态
  void setVoiceDetected(bool detected) {
    state = state.copyWith(isVoiceDetected: detected);
  }

  /// 设置唤醒词
  void setLastWakeWord(String wakeWord) {
    state = state.copyWith(lastWakeWord: wakeWord);
  }

  /// 设置会话 ID
  void setSessionId(String? sessionId) {
    state = state.copyWith(sessionId: sessionId);
  }

  /// 设置错误信息
  void setError(String? message) {
    state = state.copyWith(
      deviceState: message != null ? DeviceState.error : state.deviceState,
      errorMessage: message,
    );
  }

  /// 开始语音交互
  Future<void> startListening({ListeningMode mode = ListeningMode.autoStop}) async {
    if (state.deviceState == DeviceState.idle) {
      setDeviceState(DeviceState.connecting);
      // 连接逻辑将在 Protocol 模块中实现
    } else if (state.deviceState == DeviceState.speaking) {
      // 打断当前播放
      // AbortSpeaking 逻辑将在 Audio 模块中实现
    }
  }

  /// 停止语音交互
  Future<void> stopListening() async {
    if (state.deviceState == DeviceState.listening) {
      setDeviceState(DeviceState.idle);
    }
  }

  /// 处理热词唤醒
  void onWakeWordDetected(String wakeWord) {
    AppLogger.i('Wake word detected: $wakeWord');
    setLastWakeWord(wakeWord);

    if (state.deviceState == DeviceState.idle) {
      startListening();
    } else if (state.deviceState == DeviceState.speaking) {
      // 打断播放
      setDeviceState(DeviceState.listening);
    }
  }

  /// 处理语音活动检测变化
  void onVadStateChanged(bool isSpeaking) {
    setVoiceDetected(isSpeaking);
  }

  /// 重置状态
  void reset() {
    state = const ApplicationState(deviceState: DeviceState.idle);
  }

  @override
  void dispose() {
    _stateEventController.close();
    super.dispose();
  }
}

/// 应用状态 Provider
final applicationProvider =
    StateNotifierProvider<ApplicationNotifier, ApplicationState>((ref) {
  return ApplicationNotifier();
});

/// 设备状态 Provider (便捷访问)
final deviceStateProvider = Provider<DeviceState>((ref) {
  return ref.watch(applicationProvider).deviceState;
});
