/// XiaoXin APP - JS Bridge 处理器
/// 处理 H5 与原生之间的消息通信
library;

import 'dart:convert';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../core/device_state.dart';
import '../../core/session_manager.dart';
import '../../modules/audio/audio_service.dart';
import '../../modules/audio/audio_processor.dart';
import '../../modules/settings/config_service.dart';
import '../../utils/logger.dart';
import 'js_bridge_interface.dart';

/// H5 发送消息的回调
typedef SendToH5Callback = void Function(String message);

/// JS Bridge 处理器
class JsBridgeHandler {
  JsBridgeHandler._();

  static final JsBridgeHandler instance = JsBridgeHandler._();

  final VolumeController _volumeController = VolumeController();

  /// 发送消息到 H5 的回调
  SendToH5Callback? onSendToH5;

  /// 初始化
  void initialize() {
    _volumeController.showSystemUI = false;

    // 监听 SessionManager 状态变化
    SessionManager.instance.onStateChanged = _onStateChanged;
    SessionManager.instance.onSttText = _onSttText;
    SessionManager.instance.onLlmText = _onLlmText;
    SessionManager.instance.onTtsStart = _onTtsStart;
    SessionManager.instance.onTtsSentence = _onTtsSentence;
    SessionManager.instance.onTtsStop = _onTtsStop;
    
    // 监听 VAD 状态变化
    AudioProcessor.instance.onVadEnabledChanged = _onVadEnabledChanged;
  }

  /// 处理来自 H5 的消息
  Future<void> handleMessage(String message) async {
    try {
      final json = jsonDecode(message) as Map<String, dynamic>;
      final msg = JsBridgeMessage.fromJson(json);

      AppLogger.d('JS Bridge received: ${msg.type}');

      final response = await _processMessage(msg);
      _sendResponse(response);
    } catch (e, stackTrace) {
      AppLogger.e('JS Bridge error', e, stackTrace);
    }
  }

  /// 处理消息并返回响应
  Future<JsBridgeResponse> _processMessage(JsBridgeMessage msg) async {
    try {
      switch (msg.type) {
        case 'ready':
          return JsBridgeResponse.success(msg.id, data: {'status': 'ready'});

        case 'getDeviceInfo':
          return await _handleGetDeviceInfo(msg.id);

        case 'getAppInfo':
          return await _handleGetAppInfo(msg.id);

        case 'startVoice':
          return await _handleStartVoice(msg.id, msg.data);

        case 'stopVoice':
          return await _handleStopVoice(msg.id);

        case 'abortVoice':
          return await _handleAbortVoice(msg.id);

        case 'getState':
          return _handleGetState(msg.id);

        case 'getConfig':
          return _handleGetConfig(msg.id);

        case 'setConfig':
          return await _handleSetConfig(msg.id, msg.data);

        case 'setVolume':
          return await _handleSetVolume(msg.id, msg.data);

        case 'getVolume':
          return await _handleGetVolume(msg.id);

        case 'setBrightness':
          return await _handleSetBrightness(msg.id, msg.data);

        case 'getBrightness':
          return await _handleGetBrightness(msg.id);

        case 'setKeepScreenOn':
          return await _handleSetKeepScreenOn(msg.id, msg.data);

        case 'startKws':
          return await _handleStartKws(msg.id);

        case 'stopKws':
          return await _handleStopKws(msg.id);
        
        case 'setVoiceParams':
          return await _handleSetVoiceParams(msg.id, msg.data);

        
        case 'enableVad':
          return await _handleEnableVad(msg.id, msg.data);
        
        case 'getVadState':
          return _handleGetVadState(msg.id);
        
        case 'getKwsState':
          return _handleGetKwsState(msg.id);

        default:
          return JsBridgeResponse.error(msg.id, 'Unknown message type: ${msg.type}');
      }
    } catch (e) {
      return JsBridgeResponse.error(msg.id, e.toString());
    }
  }

  /// 获取设备信息
  Future<JsBridgeResponse> _handleGetDeviceInfo(String id) async {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;

    return JsBridgeResponse.success(id, data: {
      'brand': androidInfo.brand,
      'model': androidInfo.model,
      'device': androidInfo.device,
      'sdkInt': androidInfo.version.sdkInt,
      'release': androidInfo.version.release,
    });
  }

  /// 获取应用信息
  Future<JsBridgeResponse> _handleGetAppInfo(String id) async {
    final packageInfo = await PackageInfo.fromPlatform();

    return JsBridgeResponse.success(id, data: {
      'appName': packageInfo.appName,
      'packageName': packageInfo.packageName,
      'version': packageInfo.version,
      'buildNumber': packageInfo.buildNumber,
    });
  }

  /// 开始语音交互
  Future<JsBridgeResponse> _handleStartVoice(String id, Map<String, dynamic>? data) async {
    // 忽略 data 中的参数，只使用 setVoiceParams 设置的参数
    final started = await SessionManager.instance.startSession();
    if (started) {
      return JsBridgeResponse.success(id);
    } else {
      return JsBridgeResponse.error(id, 'Failed to start voice session');
    }
  }

  /// 停止语音交互
  Future<JsBridgeResponse> _handleStopVoice(String id) async {
    await SessionManager.instance.stopSession();
    return JsBridgeResponse.success(id);
  }

  /// 打断语音
  Future<JsBridgeResponse> _handleAbortVoice(String id) async {
    await SessionManager.instance.abortSpeaking(reason: 'h5_action');
    return JsBridgeResponse.success(id);
  }

  /// 启动热词唤醒（KWS）
  Future<JsBridgeResponse> _handleStartKws(String id) async {
    final started = await SessionManager.instance.startKws();
    if (started) {
      _sendEvent('onKwsStateChange', {'enabled': true});
      return JsBridgeResponse.success(id, data: {'status': 'started'});
    } else {
      return JsBridgeResponse.error(id, 'Failed to start KWS');
    }
  }

  /// 停止热词唤醒（KWS）
  Future<JsBridgeResponse> _handleStopKws(String id) async {
    SessionManager.instance.stopKws();
    _sendEvent('onKwsStateChange', {'enabled': false});
    return JsBridgeResponse.success(id, data: {'status': 'stopped'});
  }
  
  /// 设置语音业务参数
  Future<JsBridgeResponse> _handleSetVoiceParams(String id, Map<String, dynamic>? data) async {
    if (data == null) {
      return JsBridgeResponse.error(id, 'Params data required');
    }
    
    // 更新扩展参数（合并更新，同时持久化）
    await ConfigService.instance.setExtendParams(data);
    
    return JsBridgeResponse.success(id, data: ConfigService.instance.config.extendParams);
  }
  
  /// 启用/禁用 VAD
  Future<JsBridgeResponse> _handleEnableVad(String id, Map<String, dynamic>? data) async {
    final enable = data?['enable'] as bool? ?? false;
    await AudioService.instance.enableVad(enable);
    _sendEvent('onVadStateChange', {'enabled': enable});
    return JsBridgeResponse.success(id, data: {'enabled': enable});
  }
  
  /// 获取 VAD 状态
  JsBridgeResponse _handleGetVadState(String id) {
    return JsBridgeResponse.success(id, data: {
      'enabled': AudioService.instance.isVadEnabled,
    });
  }
  
  /// 获取 KWS 状态
  JsBridgeResponse _handleGetKwsState(String id) {
    return JsBridgeResponse.success(id, data: {
      'enabled': AudioService.instance.isKwsEnabled,
    });
  }

  /// 获取当前状态
  JsBridgeResponse _handleGetState(String id) {
    return JsBridgeResponse.success(id, data: {
      'state': SessionManager.instance.currentState.name,
      'sessionId': SessionManager.instance.sessionId,
      'isSpeaking': SessionManager.instance.isSpeaking,
      'kwsEnabled': AudioService.instance.isKwsEnabled,
      'vadEnabled': AudioService.instance.isVadEnabled,
      'voiceEngineReady': SessionManager.instance.isVoiceEngineReady,
    });
  }

  /// 获取配置
  JsBridgeResponse _handleGetConfig(String id) {
    return JsBridgeResponse.success(id, data: {
      'serverUrl': ConfigService.instance.serverUrl,
      'deviceId': ConfigService.instance.deviceId,
      'clientId': ConfigService.instance.clientId,
    });
  }

  /// 设置配置
  Future<JsBridgeResponse> _handleSetConfig(String id, Map<String, dynamic>? data) async {
    if (data == null) {
      return JsBridgeResponse.error(id, 'No config data provided');
    }

    if (data.containsKey('serverUrl')) {
      await ConfigService.instance.setServerUrl(data['serverUrl'] as String);
    }

    return JsBridgeResponse.success(id);
  }

  /// 设置音量
  Future<JsBridgeResponse> _handleSetVolume(String id, Map<String, dynamic>? data) async {
    final value = data?['value'] as num?;
    if (value == null) {
      return JsBridgeResponse.error(id, 'Volume value required');
    }

    _volumeController.setVolume(value.toDouble().clamp(0.0, 1.0));
    return JsBridgeResponse.success(id);
  }

  /// 获取音量
  Future<JsBridgeResponse> _handleGetVolume(String id) async {
    final volume = await _volumeController.getVolume();
    return JsBridgeResponse.success(id, data: {'volume': volume});
  }

  /// 设置亮度
  Future<JsBridgeResponse> _handleSetBrightness(String id, Map<String, dynamic>? data) async {
    final value = data?['value'] as num?;
    if (value == null) {
      return JsBridgeResponse.error(id, 'Brightness value required');
    }

    await ScreenBrightness().setScreenBrightness(value.toDouble().clamp(0.0, 1.0));
    return JsBridgeResponse.success(id);
  }

  /// 获取亮度
  Future<JsBridgeResponse> _handleGetBrightness(String id) async {
    try {
      final sb = ScreenBrightness();
      final brightness = await sb.current;
      return JsBridgeResponse.success(id, data: {'brightness': brightness});
    } catch (e) {
      return JsBridgeResponse.success(id, data: {'brightness': 0.5});
    }
  }

  /// 设置屏幕常亮
  Future<JsBridgeResponse> _handleSetKeepScreenOn(String id, Map<String, dynamic>? data) async {
    try {
      final keepOn = data?['keepOn'] as bool? ?? true;
      
      if (keepOn) {
        await WakelockPlus.enable();
        AppLogger.i('Screen wakelock enabled');
      } else {
        await WakelockPlus.disable();
        AppLogger.i('Screen wakelock disabled');
      }
      
      return JsBridgeResponse.success(id, data: {'keepOn': keepOn});
    } catch (e) {
      AppLogger.e('Failed to set screen keep on', e);
      return JsBridgeResponse.error(id, 'Failed to set screen keep on: $e');
    }
  }

  /// 状态变化通知
  void _onStateChanged(DeviceState state) {
    _sendEvent('onStateChange', {'state': state.name});
  }

  /// STT 文本通知
  void _onSttText(String text) {
    _sendEvent('onSttText', {'text': text});
  }

  /// LLM 文本通知
  void _onLlmText(String text, String? emotion) {
    _sendEvent('onLlmText', {'text': text, 'emotion': emotion});
  }
  
  /// TTS 开始通知
  void _onTtsStart() {
    _sendEvent('onTtsStart', {});
  }
  
  /// TTS 分句通知
  void _onTtsSentence(String text) {
    _sendEvent('onTtsSentence', {'text': text});
  }
  
  /// TTS 结束通知
  void _onTtsStop() {
    _sendEvent('onTtsStop', {});
  }
  
  /// VAD 状态变化通知
  void _onVadEnabledChanged(bool enabled) {
    _sendEvent('onVadStateChange', {'enabled': enabled});
  }

  /// 发送事件到 H5
  void _sendEvent(String type, Map<String, dynamic> data) {
    final message = JsBridgeMessage(
      id: 'event_${DateTime.now().millisecondsSinceEpoch}',
      type: type,
      data: data,
    );
    onSendToH5?.call(message.toJsonString());
  }

  /// 发送响应到 H5
  void _sendResponse(JsBridgeResponse response) {
    onSendToH5?.call(response.toJsonString());
  }

  /// 释放资源
  void dispose() {
    SessionManager.instance.onStateChanged = null;
    SessionManager.instance.onSttText = null;
    SessionManager.instance.onLlmText = null;
    SessionManager.instance.onTtsStart = null;
    SessionManager.instance.onTtsSentence = null;
    SessionManager.instance.onTtsStop = null;
  }
}
