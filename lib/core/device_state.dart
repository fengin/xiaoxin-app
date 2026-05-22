/// XiaoXin APP - 设备状态机
library;

/// 设备状态枚举
enum DeviceState {
  /// 未知状态
  unknown,

  /// 空闲状态 - 热词监听中
  idle,

  /// 连接中 - 正在建立 WebSocket 连接
  connecting,

  /// 聆听中 - 录音并上传
  listening,

  /// 回复中 - 播放 TTS 音频
  speaking,

  /// 配置中 - WiFi 或其他配置
  configuring,

  /// 错误状态
  error,
}

/// 状态变更事件
class DeviceStateEvent {
  final DeviceState previousState;
  final DeviceState currentState;
  final DateTime timestamp;

  DeviceStateEvent({
    required this.previousState,
    required this.currentState,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() {
    return 'DeviceStateEvent(${previousState.name} -> ${currentState.name})';
  }
}

/// 打断原因
enum AbortReason {
  /// 无原因
  none,

  /// 热词唤醒打断
  wakeWordDetected,

  /// 用户手动打断
  userAction,

  /// 超时打断
  timeout,
}

/// 监听模式
enum ListeningMode {
  /// 自动停止模式 - 检测到语音结束后自动停止
  autoStop,

  /// 手动停止模式 - 需要用户手动停止
  manualStop,

  /// 实时模式 - 需要 AEC 支持
  realtime,
}

/// 设备状态名称（用于显示）
extension DeviceStateExtension on DeviceState {
  String get displayName {
    switch (this) {
      case DeviceState.unknown:
        return '未知';
      case DeviceState.idle:
        return '待机';
      case DeviceState.connecting:
        return '连接中';
      case DeviceState.listening:
        return '聆听中';
      case DeviceState.speaking:
        return '回复中';
      case DeviceState.configuring:
        return '配置中';
      case DeviceState.error:
        return '错误';
    }
  }
}
