/// XiaoXin APP - H5 WebView 演示页
/// 提供带 AppBar 的 WebView 容器，用于开发调试
library;

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/session_manager.dart';
import '../../modules/webview/js_bridge_handler.dart';
import '../../utils/logger.dart';

/// H5 演示页 - 带 AppBar 的 WebView 容器
class DemoH5Page extends StatefulWidget {
  /// H5 页面 URL
  final String url;

  /// 页面标题
  final String? title;

  const DemoH5Page({
    super.key,
    required this.url,
    this.title,
  });

  @override
  State<DemoH5Page> createState() => _DemoH5PageState();
}

class _DemoH5PageState extends State<DemoH5Page> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String _pageTitle = '';

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (progress == 100) {
              setState(() {
                _isLoading = false;
              });
            }
          },
          onPageStarted: (url) {
            setState(() {
              _isLoading = true;
            });
            AppLogger.d('WebView loading: $url');
          },
          onPageFinished: (url) {
            // 🔧 注入防 bounce 脚本 (禁用 iOS 橡皮筋效果)
            _injectNoBounceScript();
            // 注入 JS Bridge
            _injectJsBridge();
            _controller.getTitle().then((title) {
              if (title != null && title.isNotEmpty && widget.title == null) {
                setState(() {
                  _pageTitle = title;
                });
              }
            });
            AppLogger.d('WebView loaded: $url');
          },
          onWebResourceError: (error) {
            AppLogger.e('WebView error: ${error.description}');
          },
        ),
      )
      ..addJavaScriptChannel(
        'XiaoXinBridge',
        onMessageReceived: (message) {
          AppLogger.d('JS Bridge message: ${message.message}');
          JsBridgeHandler.instance.handleMessage(message.message);
        },
      );

    // 根据 URL 类型加载页面
    _loadPage();

    // 🔧 iOS 特定配置: 禁用前进后退手势
    _configureIOSWebView();

    // 设置发送消息到 H5 的回调
    JsBridgeHandler.instance.onSendToH5 = _sendToH5;
    JsBridgeHandler.instance.initialize();
    
    // 监听语音引擎就绪事件，推送到 H5
    _setupVoiceEngineReadyListener();
  }
  
  /// 监听语音引擎就绪并通知 H5
  void _setupVoiceEngineReadyListener() {
    if (SessionManager.instance.isVoiceEngineReady) {
      // 已就绪，页面加载完成后发送事件
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _notifyH5VoiceReady();
      });
    } else {
      // 设置回调等待就绪
      SessionManager.instance.onVoiceEngineReady = () {
        if (mounted) _notifyH5VoiceReady();
      };
    }
  }
  
  /// 通知 H5 语音引擎已就绪
  void _notifyH5VoiceReady() {
    _controller.runJavaScript('''
      window.dispatchEvent(new CustomEvent('xiaoxin:voiceReady'));
      console.log('XiaoXin: Voice engine ready event dispatched');
    ''');
    AppLogger.d('DemoH5Page: Voice engine ready event sent to H5');
  }

  /// 加载页面（支持 assets 和远程 URL）
  void _loadPage() {
    final url = widget.url;
    
    if (url.startsWith('assets/')) {
      // 加载 Flutter assets 文件
      AppLogger.i('Loading Flutter asset: $url');
      _controller.loadFlutterAsset(url);
    } else {
      // 加载远程 URL
      AppLogger.i('Loading URL: $url');
      _controller.loadRequest(Uri.parse(url));
    }
  }

  /// 🔧 注入防 bounce 脚本
  /// 禁用 iOS WebView 的橡皮筋效果，防止整个页面被拉动
  /// 同时保留内部可滚动元素(div)的滑动功能
  Future<void> _injectNoBounceScript() async {
    try {
      await _controller.runJavaScript('''
        (function() {
          if (document.getElementById('xiaoxin-no-bounce-style')) return;
          
          console.log('🔧 Injecting no-bounce script...');

          var style = document.createElement('style');
          style.id = 'xiaoxin-no-bounce-style';
          style.innerHTML = `
            /* 禁用 body 和 html 的滚动和橡皮筋效果 */
            body, html {
              overflow: hidden !important;
              overscroll-behavior: none !important;
              position: fixed !important;
              height: 100vh !important;
              width: 100vw !important;
            }

            /* 为子元素启用平滑滚动 */
            body *, html * {
              -webkit-overflow-scrolling: touch !important;
            }
          `;

          if (document.head) {
            document.head.appendChild(style);
          }

          console.log('✅ No-bounce script injected successfully');
        })();
      ''');
      AppLogger.d('✅ No-bounce script injected');
    } catch (e) {
      AppLogger.e('❌ Failed to inject no-bounce script: $e');
    }
  }

  /// 🔧 配置 iOS WebView
  void _configureIOSWebView() {
    // 检查是否是 WebKit（iOS）平台
    final platform = _controller.platform;
    // 使用动态调用避免编译时依赖
    try {
      // 尝试禁用前进后退手势（仅 iOS 可用）
      (platform as dynamic).setAllowsBackForwardNavigationGestures(false);
      AppLogger.d('iOS WebView: disabled back/forward gestures');
    } catch (e) {
      // Android 或其他平台会抛出异常，忽略即可
    }
  }

  /// 注入 JS Bridge 脚本
  Future<void> _injectJsBridge() async {
    const jsCode = '''
      (function() {
        if (window.XiaoXin) return;
        
        window.XiaoXin = {
          _callbacks: {},
          _callbackId: 0,
          
          // 发送消息到原生
          _send: function(type, data, callback) {
            var id = 'cb_' + (++this._callbackId);
            if (callback) {
              this._callbacks[id] = callback;
            }
            var message = JSON.stringify({
              id: id,
              type: type,
              data: data || {}
            });
            XiaoXinBridge.postMessage(message);
          },
          
          // 接收原生消息
          _receive: function(message) {
            try {
              var msg = JSON.parse(message);
              
              // 处理回调
              if (msg.id && this._callbacks[msg.id]) {
                this._callbacks[msg.id](msg.success, msg.data, msg.error);
                delete this._callbacks[msg.id];
                return;
              }
              
              // 处理事件
              if (msg.type && this._eventHandlers[msg.type]) {
                this._eventHandlers[msg.type].forEach(function(handler) {
                  handler(msg.data);
                });
              }
            } catch (e) {
              console.error('XiaoXin._receive error:', e);
            }
          },
          
          _eventHandlers: {},
          
          // 监听事件
          on: function(event, handler) {
            if (!this._eventHandlers[event]) {
              this._eventHandlers[event] = [];
            }
            this._eventHandlers[event].push(handler);
          },
          
          // 移除事件监听
          off: function(event, handler) {
            if (this._eventHandlers[event]) {
              this._eventHandlers[event] = this._eventHandlers[event].filter(function(h) {
                return h !== handler;
              });
            }
          },
          
          // API 方法
          ready: function(callback) { this._send('ready', null, callback); },
          getDeviceInfo: function(callback) { this._send('getDeviceInfo', null, callback); },
          getAppInfo: function(callback) { this._send('getAppInfo', null, callback); },
          startVoice: function(data, callback) { this._send('startVoice', data, callback); },
          stopVoice: function(callback) { this._send('stopVoice', null, callback); },
          abortVoice: function(callback) { this._send('abortVoice', null, callback); },
          getState: function(callback) { this._send('getState', null, callback); },
          getConfig: function(callback) { this._send('getConfig', null, callback); },
          setConfig: function(data, callback) { this._send('setConfig', data, callback); },
          setVolume: function(value, callback) { this._send('setVolume', {value: value}, callback); },
          getVolume: function(callback) { this._send('getVolume', null, callback); },
          setBrightness: function(value, callback) { this._send('setBrightness', {value: value}, callback); },
          getBrightness: function(callback) { this._send('getBrightness', null, callback); },
          startKws: function(callback) { this._send('startKws', null, callback); },
          stopKws: function(callback) { this._send('stopKws', null, callback); },
          enableVad: function(enable, callback) { this._send('enableVad', {enable: enable}, callback); }
        };
        
        // 通知 H5 Bridge 已就绪
        // 【方式一】触发自定义事件 - H5 使用 window.addEventListener('xiaoxin:ready', handler) 监听
        var event = new CustomEvent('xiaoxin:ready');
        window.dispatchEvent(event);
        
        // 【方式二】调用全局回调函数 - H5 使用 window.onXiaoXinReady = handler 设置
        // 注意：方式一和方式二只需使用其中一种，否则 handler 会被调用两次
        // if (window.onXiaoXinReady) {
        //   window.onXiaoXinReady();
        // }
        
        console.log('XiaoXin JS Bridge initialized');
      })();
    ''';

    await _controller.runJavaScript(jsCode);
    AppLogger.i('JS Bridge injected');
  }

  /// 发送消息到 H5
  void _sendToH5(String message) {
    final escapedMessage = message.replaceAll("'", "\\'");
    _controller.runJavaScript("XiaoXin._receive('$escapedMessage');");
  }

  @override
  void dispose() {
    JsBridgeHandler.instance.onSendToH5 = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? (_pageTitle.isNotEmpty ? _pageTitle : '加载中...')),
        centerTitle: true,
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'refresh':
                  _controller.reload();
                  break;
                case 'back':
                  _controller.goBack();
                  break;
                case 'forward':
                  _controller.goForward();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'refresh', child: Text('刷新')),
              const PopupMenuItem(value: 'back', child: Text('后退')),
              const PopupMenuItem(value: 'forward', child: Text('前进')),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
