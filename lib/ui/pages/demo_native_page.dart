/// XiaoXin APP - 原生语音对话演示页
/// 用于开发调试的 Flutter 原生语音对话界面，展示语音交互功能
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/application.dart';
import '../../core/device_state.dart';
import '../../core/session_manager.dart';
import '../widgets/chat_message_widget.dart';
import 'settings_page.dart';
import 'demo_h5_page.dart';

/// 原生语音对话演示页 - 用于开发调试的 Flutter 原生语音对话界面
class DemoNativePage extends ConsumerStatefulWidget {
  const DemoNativePage({super.key});

  @override
  ConsumerState<DemoNativePage> createState() => _DemoNativePageState();
}

class _DemoNativePageState extends ConsumerState<DemoNativePage> {
  bool _isInitialized = false;
  final List<ChatMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();
  
  // 当前 AI 回复的累积文本
  String _currentAiResponse = '';
  // 上一个分句的原始文本（包含原始标点）
  String _lastSentence = '';
  // 标记是否是新的 AI 回复（用于区分更新已有消息还是添加新消息）
  bool _isNewResponse = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    // SessionManager 可能还在后台初始化中（UI 先行策略）
    // 这里设置回调并等待就绪
    _initializeCallbacks();

    setState(() {
      _isInitialized = true;
    });

    // 【问题】在 initState 或其调用的异步方法中直接修改 Provider 状态会导致异常错误：
    //   "Tried to modify a provider while the widget tree was building"
    // 【原因】initState 期间 widget tree 正在构建，此时修改 Provider 可能导致 UI 状态不一致
    // 【解决】使用 addPostFrameCallback 将状态修改延迟到当前帧构建完成之后执行
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(applicationProvider.notifier).setDeviceState(DeviceState.idle);
      }
    });
    
    // 等待语音引擎就绪后启动 KWS
    _startKwsWhenReady();
  }
  
  /// 等待语音引擎就绪后启动 KWS
  void _startKwsWhenReady() {
    if (SessionManager.instance.isVoiceEngineReady) {
      // 已就绪，立即启动
      _doStartKws();
    } else {
      // 设置回调等待就绪
      SessionManager.instance.onVoiceEngineReady = () {
        if (mounted) _doStartKws();
      };
      debugPrint('🎤 DemoNativePage: Waiting for VoiceEngine ready...');
    }
  }
  
  /// 实际启动 KWS
  Future<void> _doStartKws() async {
    final hasPermission = SessionManager.instance.hasPermission;
    debugPrint('🎤 DemoNativePage: hasPermission=$hasPermission, starting KWS...');
    if (hasPermission) {
      await SessionManager.instance.startKws();
      debugPrint('🎤 DemoNativePage: KWS started');
    } else {
      debugPrint('🎤 DemoNativePage: No permission, skipping KWS');
    }
  }
  
  /// 初始化 SessionManager 回调
  /// 从 H5 页面返回后需要重新调用此方法恢复回调
  void _initializeCallbacks() {
    SessionManager.instance.onStateChanged = _onStateChanged;
    SessionManager.instance.onSttText = _onSttText;
    SessionManager.instance.onTtsStart = _onTtsStart;
    SessionManager.instance.onTtsSentence = _onTtsSentence;
    SessionManager.instance.onTtsStop = _onTtsStop;
    
    // 注意：不在这里调用 ref.read()，因为可能在 initState 期间被调用
    // 状态同步由 _initialize 中的 addPostFrameCallback 或调用方负责
  }

  void _onStateChanged(DeviceState state) {
    ref.read(applicationProvider.notifier).setDeviceState(state);
  }

  void _onSttText(String text) {
    setState(() {
      _messages.add(ChatMessage(type: MessageType.user, text: text));
    });
    _scrollToBottom();
  }
  
  void _onTtsStart() {
    // TTS 开始，初始化新的 AI 回复
    // 注意：只重置状态，不修改已显示的消息
    _currentAiResponse = '';
    _lastSentence = '';
    _isNewResponse = true;  // 标记这是新的回复
  }
  
  void _onTtsSentence(String text) {
    setState(() {
      // 如果有上一句，恢复其原始标点
      if (_lastSentence.isNotEmpty) {
        // 移除之前的 "..." 并恢复原始标点
        _currentAiResponse = _currentAiResponse.replaceAll(RegExp(r'\.{3}$'), '');
        // 确保上一句以原始标点结尾
        if (_lastSentence.isNotEmpty && !_currentAiResponse.endsWith(_lastSentence.substring(_lastSentence.length - 1))) {
          // 还原上一句的标点
          final lastChar = _lastSentence[_lastSentence.length - 1];
          if (RegExp(r'[。！？，、]').hasMatch(lastChar)) {
            _currentAiResponse += lastChar;
          }
        }
      }
      
      // 记录当前句子（用于下次恢复标点）
      _lastSentence = text;
      
      // 拼接新句子（去掉末尾标点，加上 ...)
      String displayText = text;
      // 移除末尾标点，用 ... 替代
      displayText = displayText.replaceAll(RegExp(r'[。！？，、]+$'), '');
      displayText += '...';
      
      _currentAiResponse += displayText;
      
      // 更新或添加消息
      _updateOrAddAiMessage(_currentAiResponse);
    });
    _scrollToBottom();
  }
  
  void _onTtsStop() {
    // TTS 结束，移除末尾的 ... 并恢复最后一句的标点
    if (_currentAiResponse.isEmpty) return;  // 如果没有内容，不处理
    
    setState(() {
      _currentAiResponse = _currentAiResponse.replaceAll(RegExp(r'\.{3}$'), '');
      if (_lastSentence.isNotEmpty) {
        final lastChar = _lastSentence[_lastSentence.length - 1];
        if (RegExp(r'[。！？，、]').hasMatch(lastChar)) {
          _currentAiResponse += lastChar;
        }
      }
      
      // 最终更新消息（只有有内容时才更新）
      if (_currentAiResponse.isNotEmpty) {
        _updateOrAddAiMessage(_currentAiResponse);
      }
      
      // 清空状态，但不影响已添加的消息
      _currentAiResponse = '';
      _lastSentence = '';
    });
    _scrollToBottom();
  }
  
  void _updateOrAddAiMessage(String text) {
    // 如果文本为空，不做任何操作
    if (text.isEmpty) return;
    
    // 如果是新的回复，添加新消息；否则更新最后一条 AI 消息
    if (_isNewResponse) {
      _messages.add(ChatMessage(
        type: MessageType.assistant,
        text: text,
      ));
      _isNewResponse = false;  // 后续分句更新这条消息
    } else if (_messages.isNotEmpty && _messages.last.type == MessageType.assistant) {
      _messages.last = ChatMessage(
        type: MessageType.assistant,
        text: text,
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    SessionManager.instance.onStateChanged = null;
    SessionManager.instance.onSttText = null;
    SessionManager.instance.onTtsStart = null;
    SessionManager.instance.onTtsSentence = null;
    SessionManager.instance.onTtsStop = null;
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(applicationProvider);
    final deviceState = appState.deviceState;

    return Scaffold(
      appBar: AppBar(
        title: const Text('小新'),
        centerTitle: true,
        actions: [
          // H5 Demo 入口
          IconButton(
            icon: const Icon(Icons.web),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const DemoH5Page(
                    url: 'assets/web/demo.html',
                    title: 'H5 Demo',
                  ),
                ),
              );
              // 从 H5 页面返回后，重新初始化回调（因为 JsBridgeHandler 会覆盖回调）
              _initializeCallbacks();
              // 同步当前状态到 UI
              ref.read(applicationProvider.notifier).setDeviceState(
                SessionManager.instance.currentState,
              );
            },
            tooltip: 'H5 Demo',
          ),
          // 设置入口
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 状态显示区域
            _buildStatusArea(deviceState),

            // 对话内容区域
            Expanded(
              child: ChatMessageList(
                messages: _messages,
                scrollController: _scrollController,
              ),
            ),

            // 控制按钮区域
            _buildControlArea(deviceState),
          ],
        ),
      ),
    );
  }

  /// 状态显示区域
  Widget _buildStatusArea(DeviceState state) {
    Color statusColor;
    IconData statusIcon;

    switch (state) {
      case DeviceState.idle:
        statusColor = Colors.grey;
        statusIcon = Icons.mic_off;
        break;
      case DeviceState.connecting:
        statusColor = Colors.orange;
        statusIcon = Icons.sync;
        break;
      case DeviceState.listening:
        statusColor = Colors.green;
        statusIcon = Icons.mic;
        break;
      case DeviceState.speaking:
        statusColor = Colors.blue;
        statusIcon = Icons.volume_up;
        break;
      case DeviceState.error:
        statusColor = Colors.red;
        statusIcon = Icons.error;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help;
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(statusIcon, color: statusColor, size: 20),
          const SizedBox(width: 8),
          Text(
            state.displayName,
            style: TextStyle(
              color: statusColor,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// 控制按钮区域
  Widget _buildControlArea(DeviceState state) {
    final isActive = state == DeviceState.listening ||
        state == DeviceState.speaking ||
        state == DeviceState.connecting;

    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 清空对话按钮
          if (_messages.isNotEmpty && !isActive)
            Padding(
              padding: const EdgeInsets.only(right: 20),
              child: IconButton(
                onPressed: () {
                  setState(() {
                    _messages.clear();
                  });
                },
                icon: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.outline,
                ),
                tooltip: '清空对话',
              ),
            ),

          // 主控制按钮
          GestureDetector(
            onTap: _isInitialized ? () => _toggleVoice(state) : null,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
                boxShadow: [
                  BoxShadow(
                    color: (isActive
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.primary)
                        .withValues(alpha: 0.3),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(
                isActive ? Icons.stop : Icons.mic,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleVoice(DeviceState state) {
    if (state == DeviceState.idle) {
      // 开始会话
      SessionManager.instance.startSession();
      setState(() {
        _messages.clear();
      });
    } else if (state == DeviceState.speaking) {
      // 打断播放
      SessionManager.instance.abortSpeaking(reason: 'user_action');
    } else {
      // 停止会话
      SessionManager.instance.stopSession();
    }
  }
}
