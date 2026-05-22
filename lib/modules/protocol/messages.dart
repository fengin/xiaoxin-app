/// XiaoXin APP - 小智协议消息定义
library;

import 'dart:convert';

/// 音频参数
class AudioParams {
  final String format;
  final int sampleRate;
  final int channels;
  final int frameDuration;

  const AudioParams({
    this.format = 'opus',
    this.sampleRate = 16000,
    this.channels = 1,
    this.frameDuration = 60,
  });

  /// 默认客户端音频参数
  static const AudioParams clientDefault = AudioParams();

  /// 默认服务端音频参数
  static const AudioParams serverDefault = AudioParams(sampleRate: 24000);

  Map<String, dynamic> toJson() => {
        'format': format,
        'sample_rate': sampleRate,
        'channels': channels,
        'frame_duration': frameDuration,
      };

  factory AudioParams.fromJson(Map<String, dynamic> json) {
    return AudioParams(
      format: json['format'] ?? 'opus',
      sampleRate: json['sample_rate'] ?? 16000,
      channels: json['channels'] ?? 1,
      frameDuration: json['frame_duration'] ?? 60,
    );
  }
}

/// 特性配置
class Features {
  final bool mcp;
  final bool aec;

  const Features({
    this.mcp = true,
    this.aec = false,
  });

  Map<String, dynamic> toJson() => {
        'mcp': mcp,
        if (aec) 'aec': aec,
      };

  factory Features.fromJson(Map<String, dynamic> json) {
    return Features(
      mcp: json['mcp'] ?? false,
      aec: json['aec'] ?? false,
    );
  }
}

/// Hello 消息（客户端发送）
class HelloMessage {
  final String type = 'hello';
  final int version;
  final Features features;
  final String transport;
  final AudioParams audioParams;
  final Map<String, dynamic>? extend;

  const HelloMessage({
    this.version = 1,
    this.features = const Features(),
    this.transport = 'websocket',
    this.audioParams = AudioParams.clientDefault,
    this.extend,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'version': version,
        'features': features.toJson(),
        'transport': transport,
        'audio_params': audioParams.toJson(),
        if (extend != null) 'extend': extend,
      };

  String toJsonString() => jsonEncode(toJson());
}

/// Hello 响应消息（服务端返回）
class HelloResponse {
  final String type;
  final int version;
  final String transport;
  final String sessionId;
  final AudioParams audioParams;

  const HelloResponse({
    this.type = 'hello',
    this.version = 1,
    this.transport = 'websocket',
    required this.sessionId,
    this.audioParams = AudioParams.serverDefault,
  });

  factory HelloResponse.fromJson(Map<String, dynamic> json) {
    return HelloResponse(
      type: json['type'] ?? 'hello',
      version: json['version'] ?? 1,
      transport: json['transport'] ?? 'websocket',
      sessionId: json['session_id'] ?? '',
      audioParams: json['audio_params'] != null
          ? AudioParams.fromJson(json['audio_params'])
          : AudioParams.serverDefault,
    );
  }
}

/// Listen 消息
class ListenMessage {
  final String type = 'listen';
  final String mode;
  final String state;
  final String? text;  // 用于 state=detect 时传递唤醒词
  final Map<String, dynamic>? extend;

  const ListenMessage({
    required this.mode,
    required this.state,
    this.text,
    this.extend,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'mode': mode,
        'state': state,
        if (text != null) 'text': text,
        if (extend != null) 'extend': extend,
      };

  String toJsonString() => jsonEncode(toJson());
}

/// Abort 消息
class AbortMessage {
  final String type = 'abort';
  final String reason;

  const AbortMessage({this.reason = 'none'});

  Map<String, dynamic> toJson() => {
        'type': type,
        'reason': reason,
      };

  String toJsonString() => jsonEncode(toJson());
}

/// TTS 消息（服务端返回）
class TtsMessage {
  final String type;
  final String state;
  final String? text;

  const TtsMessage({
    this.type = 'tts',
    required this.state,
    this.text,
  });

  factory TtsMessage.fromJson(Map<String, dynamic> json) {
    return TtsMessage(
      type: json['type'] ?? 'tts',
      state: json['state'] ?? '',
      text: json['text'],
    );
  }

  bool get isStart => state == 'start';
  bool get isStop => state == 'stop';
  bool get isSentenceStart => state == 'sentence_start';
}

/// STT 消息（服务端返回）
class SttMessage {
  final String type;
  final String text;

  const SttMessage({
    this.type = 'stt',
    required this.text,
  });

  factory SttMessage.fromJson(Map<String, dynamic> json) {
    return SttMessage(
      type: json['type'] ?? 'stt',
      text: json['text'] ?? '',
    );
  }
}

/// LLM 消息（服务端返回）
class LlmMessage {
  final String type;
  final String? emotion;
  final String? text;

  const LlmMessage({
    this.type = 'llm',
    this.emotion,
    this.text,
  });

  factory LlmMessage.fromJson(Map<String, dynamic> json) {
    return LlmMessage(
      type: json['type'] ?? 'llm',
      emotion: json['emotion'],
      text: json['text'],
    );
  }
}

/// MCP 消息
class McpMessage {
  final String type;
  final Map<String, dynamic> payload;

  const McpMessage({
    this.type = 'mcp',
    required this.payload,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'payload': payload,
      };

  String toJsonString() => jsonEncode(toJson());

  factory McpMessage.fromJson(Map<String, dynamic> json) {
    return McpMessage(
      type: json['type'] ?? 'mcp',
      payload: json['payload'] ?? {},
    );
  }
}

/// 系统消息（服务端返回）
class SystemMessage {
  final String type;
  final String command;

  const SystemMessage({
    this.type = 'system',
    required this.command,
  });

  factory SystemMessage.fromJson(Map<String, dynamic> json) {
    return SystemMessage(
      type: json['type'] ?? 'system',
      command: json['command'] ?? '',
    );
  }
}

/// 消息解析工具
class MessageParser {
  /// 解析服务端消息
  static dynamic parseServerMessage(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    final type = json['type'] as String?;

    switch (type) {
      case 'hello':
        return HelloResponse.fromJson(json);
      case 'tts':
        return TtsMessage.fromJson(json);
      case 'stt':
        return SttMessage.fromJson(json);
      case 'llm':
        return LlmMessage.fromJson(json);
      case 'mcp':
        return McpMessage.fromJson(json);
      case 'system':
        return SystemMessage.fromJson(json);
      default:
        return json;
    }
  }
}
