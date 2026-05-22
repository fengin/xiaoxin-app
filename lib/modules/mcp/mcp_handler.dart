/// XiaoXin APP - MCP 消息处理器
/// 处理 MCP 协议消息，包括透传 H5、音量控制、亮度控制
library;

import 'package:volume_controller/volume_controller.dart';
import 'package:screen_brightness/screen_brightness.dart';
import '../protocol/messages.dart';
import '../protocol/protocol_service.dart';
import '../../utils/logger.dart';

/// MCP 消息透传回调（传给 H5）
typedef OnMcpMessageForH5 = void Function(Map<String, dynamic> payload);

/// MCP 处理器
class McpHandler {
  McpHandler._();

  static final McpHandler instance = McpHandler._();

  final VolumeController _volumeController = VolumeController();

  /// H5 消息回调
  OnMcpMessageForH5? onMcpMessageForH5;

  /// 初始化
  void initialize() {
    // 隐藏系统音量 UI
    _volumeController.showSystemUI = false;
  }

  /// 处理 MCP 消息
  void handleMcpMessage(McpMessage message) {
    final payload = message.payload;
    
    // 检查是否是 JSON-RPC 格式的 MCP 消息
    final method = payload['method'] as String?;
    final id = payload['id'];
    
    // 如果是 JSON-RPC 请求，优先处理
    if (method != null) {
      _handleMcpRequest(method, id, payload);
      return;
    }
    
    // 否则按原有逻辑处理
    final type = payload['type'] as String?;
    AppLogger.d('Received MCP message: type=$type, method=$method');

    switch (type) {
      case 'volume_control':
        _handleVolumeControl(payload);
        break;
      case 'brightness_control':
        _handleBrightnessControl(payload);
        break;
      default:
        // 其他消息透传给 H5
        _forwardToH5(payload);
    }
  }

  /// 处理 MCP JSON-RPC 请求
  void _handleMcpRequest(String method, dynamic id, Map<String, dynamic> payload) {
    AppLogger.i('MCP request: method=$method, id=$id');
    
    switch (method) {
      case 'initialize':
        _handleInitialize(id);
        break;
      case 'tools/list':
        _handleToolsList(id);
        break;
      case 'tools/call':
        _handleToolsCall(id, payload['params'] as Map<String, dynamic>?);
        break;
      default:
        // 未知方法，透传给 H5
        _forwardToH5(payload);
    }
  }

  /// 处理 initialize 请求
  void _handleInitialize(dynamic id) {
    // 返回客户端 capabilities
    final response = {
      'jsonrpc': '2.0',
      'id': id,
      'result': {
        'protocolVersion': '2024-11-05',
        'capabilities': {
          'tools': {
            'listChanged': false,
          },
        },
        'serverInfo': {
          'name': 'XiaoXin-App',
          'version': '1.0.0',
        },
      },
    };
    
    ProtocolService.instance.sendMcpMessage(response);
    AppLogger.i('MCP initialize response sent');
  }

  /// 处理 tools/list 请求
  void _handleToolsList(dynamic id) {
    // 返回可用的工具列表
    final response = {
      'jsonrpc': '2.0',
      'id': id,
      'result': {
        'tools': [
          {
            'name': 'volume_control',
            'description': '调节设备音量。action说明：set需要value参数(0.0-1.0)；low=0.2静音级, medium=0.5舒适级, high=0.8响亮级, max=1.0最大；increase/decrease相对调节±0.1；mute静音；get获取当前音量',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'action': {'type': 'string', 'enum': ['set', 'get', 'mute', 'max', 'low', 'medium', 'high', 'increase', 'decrease']},
                'value': {'type': 'number', 'description': '仅action=set时需要，范围0.0-1.0，参考：0.2低/0.5中/0.8高'},
              },
              'required': ['action'],
            },
          },
          {
            'name': 'brightness_control',
            'description': '调节屏幕亮度。action说明：set需要value参数(0.0-1.0)；low=0.2护眼级, medium=0.5舒适级, high=0.8明亮级, max=1.0最亮；increase/decrease相对调节±0.1；reset恢复系统默认；get获取当前亮度',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'action': {'type': 'string', 'enum': ['set', 'get', 'reset', 'max', 'low', 'medium', 'high', 'increase', 'decrease']},
                'value': {'type': 'number', 'description': '仅action=set时需要，范围0.0-1.0，参考：0.2低/0.5中/0.8高'},
              },
              'required': ['action'],
            },
          },
        ],
      },
    };
    
    ProtocolService.instance.sendMcpMessage(response);
    AppLogger.i('MCP tools/list response sent');
  }

  /// 处理 tools/call 请求
  void _handleToolsCall(dynamic id, Map<String, dynamic>? params) {
    final toolName = params?['name'] as String?;
    final arguments = params?['arguments'] as Map<String, dynamic>?;
    
    AppLogger.i('MCP tools/call: $toolName, args=$arguments');
    
    // 根据工具名称调用对应处理
    switch (toolName) {
      case 'volume_control':
        _handleVolumeControl(arguments ?? {});
        _sendToolCallSuccess(id, 'Volume control executed');
        break;
      case 'brightness_control':
        _handleBrightnessControl(arguments ?? {});
        _sendToolCallSuccess(id, 'Brightness control executed');
        break;
      default:
        _sendToolCallError(id, 'Unknown tool: $toolName');
    }
  }

  /// 发送工具调用成功响应
  void _sendToolCallSuccess(dynamic id, String message) {
    final response = {
      'jsonrpc': '2.0',
      'id': id,
      'result': {
        'content': [
          {'type': 'text', 'text': message},
        ],
      },
    };
    ProtocolService.instance.sendMcpMessage(response);
  }

  /// 发送工具调用错误响应
  void _sendToolCallError(dynamic id, String error) {
    final response = {
      'jsonrpc': '2.0',
      'id': id,
      'error': {
        'code': -32601,
        'message': error,
      },
    };
    ProtocolService.instance.sendMcpMessage(response);
  }

  /// 处理音量控制
  Future<void> _handleVolumeControl(Map<String, dynamic> payload) async {
    try {
      final action = payload['action'] as String?;
      final value = payload['value'];

      switch (action) {
        case 'set':
          if (value is num) {
            final volume = value.toDouble().clamp(0.0, 1.0);
            _volumeController.setVolume(volume);
            AppLogger.i('Volume set to: $volume');
          }
          break;
        case 'get':
          final current = await _volumeController.getVolume();
          AppLogger.i('Current volume: $current');
          break;
        case 'mute':
          _volumeController.muteVolume();
          AppLogger.i('Volume muted');
          break;
        case 'max':
          _volumeController.maxVolume();
          AppLogger.i('Volume set to max');
          break;
        case 'low':
          _volumeController.setVolume(0.2);
          AppLogger.i('Volume set to low (0.2)');
          break;
        case 'medium':
          _volumeController.setVolume(0.5);
          AppLogger.i('Volume set to medium (0.5)');
          break;
        case 'high':
          _volumeController.setVolume(0.8);
          AppLogger.i('Volume set to high (0.8)');
          break;
        case 'increase':
          final currentUp = await _volumeController.getVolume();
          final newUp = (currentUp + 0.1).clamp(0.0, 1.0);
          _volumeController.setVolume(newUp);
          AppLogger.i('Volume increased to: $newUp');
          break;
        case 'decrease':
          final currentDown = await _volumeController.getVolume();
          final newDown = (currentDown - 0.1).clamp(0.0, 1.0);
          _volumeController.setVolume(newDown);
          AppLogger.i('Volume decreased to: $newDown');
          break;
        default:
          AppLogger.w('Unknown volume action: $action');
      }
    } catch (e, stackTrace) {
      AppLogger.e('Failed to handle volume control', e, stackTrace);
    }
  }

  /// 处理亮度控制
  Future<void> _handleBrightnessControl(Map<String, dynamic> payload) async {
    try {
      final action = payload['action'] as String?;
      final value = payload['value'];
      final screenBrightness = ScreenBrightness();

      switch (action) {
        case 'set':
          if (value is num) {
            final level = value.toDouble().clamp(0.0, 1.0);
            await screenBrightness.setScreenBrightness(level);
            AppLogger.i('Brightness set to: $level');
          }
          break;
        case 'get':
          final current = await screenBrightness.current;
          AppLogger.i('Current brightness: $current');
          break;
        case 'reset':
          await screenBrightness.resetScreenBrightness();
          AppLogger.i('Brightness reset to system default');
          break;
        case 'max':
          await screenBrightness.setScreenBrightness(1.0);
          AppLogger.i('Brightness set to max (1.0)');
          break;
        case 'low':
          await screenBrightness.setScreenBrightness(0.2);
          AppLogger.i('Brightness set to low (0.2)');
          break;
        case 'medium':
          await screenBrightness.setScreenBrightness(0.5);
          AppLogger.i('Brightness set to medium (0.5)');
          break;
        case 'high':
          await screenBrightness.setScreenBrightness(0.8);
          AppLogger.i('Brightness set to high (0.8)');
          break;
        case 'increase':
          final currentUp = await screenBrightness.current;
          final newUp = (currentUp + 0.1).clamp(0.0, 1.0);
          await screenBrightness.setScreenBrightness(newUp);
          AppLogger.i('Brightness increased to: $newUp');
          break;
        case 'decrease':
          final currentDown = await screenBrightness.current;
          final newDown = (currentDown - 0.1).clamp(0.0, 1.0);
          await screenBrightness.setScreenBrightness(newDown);
          AppLogger.i('Brightness decreased to: $newDown');
          break;
        default:
          AppLogger.w('Unknown brightness action: $action');
      }
    } catch (e, stackTrace) {
      AppLogger.e('Failed to handle brightness control', e, stackTrace);
    }
  }

  /// 透传消息给 H5
  void _forwardToH5(Map<String, dynamic> payload) {
    if (onMcpMessageForH5 != null) {
      onMcpMessageForH5!(payload);
      AppLogger.d('MCP message forwarded to H5');
    } else {
      AppLogger.w('No H5 callback registered for MCP message');
    }
  }

  /// 释放资源
  void dispose() {
    // VolumeController 不需要显式释放
  }

  /// 发送 MCP 事件到 H5
  void notifyH5McpEvent(String eventType, Map<String, dynamic> data) {
    if (onMcpMessageForH5 != null) {
      onMcpMessageForH5!({
        'event': eventType,
        ...data,
      });
      AppLogger.d('MCP event sent to H5: $eventType');
    }
  }

  /// 处理 IoT 设备控制消息
  void handleIotControl(Map<String, dynamic> payload) {
    final device = payload['device'] as String?;
    final action = payload['action'] as String?;
    final params = payload['params'] as Map<String, dynamic>?;

    AppLogger.i('IoT control: device=$device, action=$action, params=$params');

    // 透传给 H5 处理
    _forwardToH5({
      'type': 'iot_control',
      'device': device,
      'action': action,
      'params': params,
    });
  }
}
