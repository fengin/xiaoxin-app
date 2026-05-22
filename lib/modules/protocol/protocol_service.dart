/// XiaoXin APP - WebSocket 协议服务
library;

import 'dart:async';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'messages.dart';
import '../settings/config_service.dart';
import '../../utils/constants.dart';
import '../../utils/logger.dart';

/// WebSocket 连接状态
enum WebSocketState {
  disconnected,
  connecting,
  connected,
  error,
}

/// 协议服务回调
typedef OnAudioDataCallback = void Function(Uint8List data);
typedef OnJsonMessageCallback = void Function(dynamic message);
typedef OnConnectedCallback = void Function();
typedef OnDisconnectedCallback = void Function();
typedef OnErrorCallback = void Function(String message);

/// WebSocket 协议服务
class ProtocolService {
  ProtocolService._();

  static final ProtocolService instance = ProtocolService._();

  WebSocketChannel? _channel;
  WebSocketState _state = WebSocketState.disconnected;
  StreamSubscription? _subscription;

  // 服务端返回的音频采样率
  int _serverSampleRate = AppConstants.serverAudioSampleRate;
  String? _sessionId;

  // 回调函数
  OnAudioDataCallback? onAudioData;
  OnJsonMessageCallback? onJsonMessage;
  OnConnectedCallback? onConnected;
  OnDisconnectedCallback? onDisconnected;
  OnErrorCallback? onError;

  /// 获取连接状态
  WebSocketState get state => _state;

  /// 是否已连接
  bool get isConnected => _state == WebSocketState.connected;

  /// 获取会话 ID
  String? get sessionId => _sessionId;

  /// 获取服务端音频采样率
  int get serverSampleRate => _serverSampleRate;

  /// 打开音频通道
  Future<bool> openAudioChannel() async {
    if (_state == WebSocketState.connected) {
      AppLogger.w('WebSocket already connected');
      return true;
    }

    _state = WebSocketState.connecting;

    try {
      final config = ConfigService.instance.config;
      final wsUrl = config.effectiveWsUrl;
      
      if (wsUrl == null || wsUrl.isEmpty) {
        AppLogger.e('WebSocket URL not configured');
        _state = WebSocketState.disconnected;
        return false;
      }
      
      final uri = Uri.parse(wsUrl);

      // 构建请求头
      final headers = <String, String>{
        'Protocol-Version': AppConstants.protocolVersion.toString(),
        'Device-Id': config.deviceId,
        'Client-Id': config.clientId,
      };

      AppLogger.i('Connecting to WebSocket: $wsUrl');
      AppLogger.d('Headers: $headers');

      // 使用 IOWebSocketChannel 以支持传递自定义 HTTP 头
      _channel = IOWebSocketChannel.connect(
        uri,
        headers: headers,
      );

      // 等待连接完成
      await _channel!.ready;

      _state = WebSocketState.connected;
      AppLogger.i('WebSocket connected');

      // 订阅消息
      _subscription = _channel!.stream.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
      );

      // 发送 hello 消息
      await _sendHello();

      return true;
    } catch (e, stackTrace) {
      AppLogger.e('WebSocket connection failed', e, stackTrace);
      _state = WebSocketState.error;
      onError?.call('连接失败: $e');
      return false;
    }
  }

  /// 关闭音频通道
  Future<void> closeAudioChannel() async {
    AppLogger.i('Closing WebSocket connection');

    await _subscription?.cancel();
    _subscription = null;

    await _channel?.sink.close();
    _channel = null;

    _state = WebSocketState.disconnected;
    _sessionId = null;

    onDisconnected?.call();
  }

  /// 发送 Hello 消息
  Future<void> _sendHello() async {
    final hello = HelloMessage(
      version: AppConstants.protocolVersion,
      features: const Features(mcp: true),
      audioParams: AudioParams.clientDefault,
      extend: ConfigService.instance.config.extendParams,
    );

    _sendJson(hello.toJsonString());
    AppLogger.d('Sent hello message (extend: ${hello.extend})');
  }

  /// 发送 Listen 消息
  void sendStartListening({
    String mode = 'auto',
    Map<String, dynamic>? extend,
  }) {
    final listen = ListenMessage(
      mode: mode,
      state: 'start',
      extend: extend ?? ConfigService.instance.config.extendParams,
    );
    AppLogger.d('[Performance] [$_sessionId] [Client_Send] type=listen_start time=${DateTime.now().millisecondsSinceEpoch}');
    _sendJson(listen.toJsonString());
    AppLogger.d('Sent listen start message');
  }

  /// 发送停止监听
  void sendStopListening() {
    final listen = const ListenMessage(
      mode: 'auto',
      state: 'stop',
    );
    _sendJson(listen.toJsonString());
    AppLogger.d('Sent listen stop message');
  }

  /// 发送热词检测消息
  void sendWakeWordDetected(String keyword) {
    // 构造 listen detect 消息
    final listen = ListenMessage(
      mode: 'manual', // 保持手动模式
      state: 'detect',
      text: keyword,
    );
    AppLogger.d('[Performance] [$_sessionId] [Client_Send] type=wake_detection time=${DateTime.now().millisecondsSinceEpoch}');
    _sendJson(listen.toJsonString());
    AppLogger.i('Sent wake word detected: $keyword');
  }

  /// 发送打断消息
  void sendAbortSpeaking({String reason = 'none'}) {
    final abort = AbortMessage(reason: reason);
    _sendJson(abort.toJsonString());
    AppLogger.d('Sent abort message: $reason');
  }

  /// 发送 MCP 消息
  void sendMcpMessage(Map<String, dynamic> payload) {
    final mcp = McpMessage(payload: payload);
    _sendJson(mcp.toJsonString());
    AppLogger.d('Sent MCP message');
  }

  /// 发送音频数据（v1 协议：直接发送 Opus）
  void sendAudio(Uint8List opusData) {
    if (!isConnected) {
      AppLogger.w('Cannot send audio: not connected');
      return;
    }
    _channel?.sink.add(opusData);
  }

  /// 发送 JSON 消息
  void _sendJson(String json) {
    if (!isConnected) {
      AppLogger.w('Cannot send message: not connected');
      return;
    }
    _channel?.sink.add(json);
  }

  /// 处理接收到的数据
  void _onData(dynamic data) {
    if (data is String) {
      // JSON 消息
      _handleJsonMessage(data);
    } else if (data is List<int>) {
      // 二进制音频数据
      _handleAudioData(Uint8List.fromList(data));
    }
  }

  /// 处理 JSON 消息
  void _handleJsonMessage(String data) {
    try {
      final message = MessageParser.parseServerMessage(data);

      if (message is HelloResponse) {
        _sessionId = message.sessionId;
        _serverSampleRate = message.audioParams.sampleRate;
        AppLogger.i('Session established: $_sessionId');
        AppLogger.i('Server audio sample rate: $_serverSampleRate');
        onConnected?.call();
      }

      // 性能日志：收到 TTS 首包
      if (message is TtsMessage && (message.state == 'start' || message.state == 'sentence_start')) {
        AppLogger.d('[Performance] [$_sessionId] [Client_Recv_First] type=${message.state} time=${DateTime.now().millisecondsSinceEpoch}');
      }

      onJsonMessage?.call(message);
    } catch (e, stackTrace) {
      AppLogger.e('Failed to parse JSON message', e, stackTrace);
    }
  }

  /// 处理音频数据
  void _handleAudioData(Uint8List data) {
    // [调试时取消注释] AppLogger.d('[AUDIO_RECV] Received ${data.length} bytes');
    onAudioData?.call(data);
  }

  /// 处理错误
  void _onError(dynamic error) {
    AppLogger.e('WebSocket error', error);
    _state = WebSocketState.error;
    onError?.call('连接错误: $error');
  }

  /// 处理连接关闭
  void _onDone() {
    AppLogger.i(
        'WebSocket connection closed. Code: ${_channel?.closeCode}, Reason: ${_channel?.closeReason}');
    _state = WebSocketState.disconnected;
    onDisconnected?.call();
  }

  /// 释放资源
  Future<void> dispose() async {
    await closeAudioChannel();
  }
}
