/// XiaoXin APP - JS Bridge 接口
/// 定义 H5 与原生通信的接口
library;

import 'dart:convert';

/// JS Bridge 消息类型
enum JsBridgeMessageType {
  // 系统相关
  ready,          // H5 准备就绪
  getDeviceInfo,  // 获取设备信息
  getAppInfo,     // 获取应用信息
  
  // 语音相关
  startVoice,     // 开始语音交互
  stopVoice,      // 停止语音交互
  abortVoice,     // 打断语音
  
  // 状态相关
  getState,       // 获取当前状态
  onStateChange,  // 状态变化通知
  
  // 对话相关
  onSttText,      // STT 文本通知
  onLlmText,      // LLM 文本通知
  onTtsStart,     // TTS 开始通知
  onTtsEnd,       // TTS 结束通知
  
  // MCP 相关
  onMcpMessage,   // MCP 消息通知
  sendMcpResponse,// 发送 MCP 响应
  
  // 配置相关
  getConfig,      // 获取配置
  setConfig,      // 设置配置
  
  // 音量/亮度控制
  setVolume,      // 设置音量
  getVolume,      // 获取音量
  setBrightness,  // 设置亮度
  getBrightness,  // 获取亮度
}

/// JS Bridge 消息
class JsBridgeMessage {
  final String id;
  final String type;
  final Map<String, dynamic>? data;
  final String? error;

  JsBridgeMessage({
    required this.id,
    required this.type,
    this.data,
    this.error,
  });

  factory JsBridgeMessage.fromJson(Map<String, dynamic> json) {
    return JsBridgeMessage(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? '',
      data: json['data'] as Map<String, dynamic>?,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      if (data != null) 'data': data,
      if (error != null) 'error': error,
    };
  }

  String toJsonString() => jsonEncode(toJson());
}

/// JS Bridge 响应
class JsBridgeResponse {
  final String id;
  final bool success;
  final dynamic data;
  final String? error;

  JsBridgeResponse({
    required this.id,
    required this.success,
    this.data,
    this.error,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'success': success,
      if (data != null) 'data': data,
      if (error != null) 'error': error,
    };
  }

  String toJsonString() => jsonEncode(toJson());

  factory JsBridgeResponse.success(String id, {dynamic data}) {
    return JsBridgeResponse(id: id, success: true, data: data);
  }

  factory JsBridgeResponse.error(String id, String error) {
    return JsBridgeResponse(id: id, success: false, error: error);
  }
}
