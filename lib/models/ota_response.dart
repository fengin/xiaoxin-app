/// XiaoXin APP - OTA 响应模型
/// 解析 OTA 接口返回的 JSON 数据
library;

/// OTA 响应模型
class OtaResponse {
  /// 激活信息
  final ActivationInfo? activation;

  /// WebSocket 配置
  final WebSocketConfig? websocket;

  /// H5 页面地址
  final String? h5Url;

  /// 服务器时间
  final ServerTime? serverTime;

  const OtaResponse({
    this.activation,
    this.websocket,
    this.h5Url,
    this.serverTime,
  });

  /// 是否需要激活（有激活码）
  bool get needsActivation =>
      activation?.code != null && activation!.code!.isNotEmpty;

  /// 是否已激活（没有激活码表示已激活）
  bool get isActivated =>
      activation?.code == null || activation!.code!.isEmpty;

  factory OtaResponse.fromJson(Map<String, dynamic> json) {
    return OtaResponse(
      activation: json['activation'] != null
          ? ActivationInfo.fromJson(json['activation'] as Map<String, dynamic>)
          : null,
      websocket: json['websocket'] != null
          ? WebSocketConfig.fromJson(json['websocket'] as Map<String, dynamic>)
          : null,
      h5Url: json['h5_url'] as String?,
      serverTime: json['server_time'] != null
          ? ServerTime.fromJson(json['server_time'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// 激活信息
class ActivationInfo {
  /// 激活码（6位数字）
  final String? code;

  /// 提示信息
  final String? message;

  /// 激活挑战（用于 HMAC 验证）
  final String? challenge;

  /// 超时时间（毫秒）
  final int? timeoutMs;

  const ActivationInfo({
    this.code,
    this.message,
    this.challenge,
    this.timeoutMs,
  });

  factory ActivationInfo.fromJson(Map<String, dynamic> json) {
    return ActivationInfo(
      code: json['code'] as String?,
      message: json['message'] as String?,
      challenge: json['challenge'] as String?,
      timeoutMs: json['timeout_ms'] as int?,
    );
  }
}

/// WebSocket 配置
class WebSocketConfig {
  /// WebSocket 地址
  final String? url;

  /// 认证 Token
  final String? token;

  const WebSocketConfig({
    this.url,
    this.token,
  });

  factory WebSocketConfig.fromJson(Map<String, dynamic> json) {
    return WebSocketConfig(
      url: json['url'] as String?,
      token: json['token'] as String?,
    );
  }
}

/// 服务器时间
class ServerTime {
  /// 时间戳（毫秒）
  final int? timestamp;

  /// 时区偏移（分钟）
  final int? timezoneOffset;

  const ServerTime({
    this.timestamp,
    this.timezoneOffset,
  });

  factory ServerTime.fromJson(Map<String, dynamic> json) {
    return ServerTime(
      timestamp: json['timestamp'] as int?,
      timezoneOffset: json['timezone_offset'] as int?,
    );
  }
}
