/// XiaoXin APP - 全屏 WebView 容器首页
/// 生产环境使用的主页面，加载 H5 应用
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/session_manager.dart';
import '../../modules/webview/js_bridge_handler.dart';
import '../../modules/settings/config_service.dart';
import '../../utils/logger.dart';
import 'settings_page.dart';

/// 全屏 H5 容器首页
/// 
/// 与 [DemoH5Page] 的区别：
/// - 无 AppBar，全屏沉浸式体验
/// - 作为应用首页使用
/// - 自动从配置获取默认 URL
class H5ContainerPage extends StatefulWidget {
  /// H5 页面 URL，如果不传则从配置中获取
  final String? url;

  const H5ContainerPage({
    super.key,
    this.url,
  });

  @override
  State<H5ContainerPage> createState() => _H5ContainerPageState();
}

enum H5ErrorType {
  none,
  network,  // 断网/DNS失败
  timeout,  // 超时
  http,     // 404/500等
  unknown
}

class _H5ContainerPageState extends State<H5ContainerPage> {
  static const double _adminHotAreaSize = 80;
  static const double _adminMoveTolerance = 12;
  static const Duration _adminLongPressDuration = Duration(seconds: 5);

  late final WebViewController _controller;
  Timer? _timeoutTimer;
  Timer? _autoRetryTimer;
  Timer? _adminLongPressTimer;
  int? _adminPointerId;
  bool _adminLongPressTriggered = false;
  bool _isLoading = true;
  bool _hasError = false;
  H5ErrorType _errorType = H5ErrorType.none;
  String _errorMessage = '';
  // 当前主框架 URL，用于在 onHttpError 中区分主文档与子资源错误
  String? _currentMainFrameUrl;

  /// 获取要加载的 URL
  String get _targetUrl {
    // 优先使用传入的 URL，否则从配置获取
    if (widget.url != null && widget.url!.isNotEmpty) {
      return widget.url!;
    }
    // 从配置获取默认 H5 首页 URL
    return ConfigService.instance.h5HomeUrl;
  }

  @override
  void initState() {
    super.initState();
    // 设置完全沉浸式模式（隐藏状态栏和导航栏）
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initWebView();
  }

  @override
  void dispose() {
    _cancelTimeoutTimer();
    _cancelAutoRetryTimer();
    _cancelAdminLongPressTimer();
    // 清理 VoiceEngine 就绪回调，避免回调泄漏
    SessionManager.instance.onVoiceEngineReady = null;
    JsBridgeHandler.instance.onSendToH5 = null;
    
    // 清理 WebView 内存（尝试释放 JS 堆）
    // 注意：这不会清除持久化存储（localStorage/cookies），仅清除内存缓存
    try {
      _controller.clearCache();
      AppLogger.d('H5Container: WebView cache cleared on dispose');
    } catch (e) {
      // 某些情况下可能失败，忽略
      AppLogger.w('H5Container: Failed to clear WebView cache: $e');
    }
    
    // 恢复状态栏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    super.dispose();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
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
            _currentMainFrameUrl = url;
            _startTimeoutTimer();
            setState(() {
              _isLoading = true;
              _hasError = false;
            });
            AppLogger.d('H5Container loading: $url');
          },
          onPageFinished: (url) {
            _cancelTimeoutTimer();
            // 注入防 bounce 脚本
            _injectNoBounceScript();
            // 注入 JS Bridge
            _injectJsBridge();
            AppLogger.d('H5Container loaded: $url');
          },
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url;
            AppLogger.d('H5Container navigation request: $url');

            // 拦截隐私协议等外部链接，改为在系统浏览器中打开
            if (_isExternalUrl(url)) {
              _openInExternalBrowser(url);
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
          onWebResourceError: (WebResourceError error) {
            bool isCriticalError = error.isForMainFrame ?? false;
            
            if (!isCriticalError) {
              final url = error.url?.toLowerCase() ?? '';
              if (url.endsWith('.js') || url.endsWith('.css')) {
                AppLogger.w('H5Container critical subresource load failed: ${error.url} ${error.description}');
              } else {
                AppLogger.w('H5Container subresource error ignored: ${error.url} ${error.description}');
              }
              return;
            }
            _cancelTimeoutTimer();
            AppLogger.e('H5Container error: ${error.description}, type: ${error.errorType}');
            setState(() {
              _hasError = true;

              final desc = error.description.toLowerCase();
              if (desc.contains('err_internet_disconnected') || desc.contains('err_network_changed')) {
                _errorType = H5ErrorType.network;
              }
              else if (error.errorType == WebResourceErrorType.timeout ||
                       error.errorType == WebResourceErrorType.hostLookup ||
                       error.errorType == WebResourceErrorType.connect) {
                _errorType = H5ErrorType.timeout;
              }
              else {
                _errorType = H5ErrorType.unknown;
                _errorMessage = error.description;
              }
            });
            _startAutoRetryTimer();
          },
          onHttpError: (HttpResponseError error) {
            // HttpResponseError 没有 isForMainFrame 字段，通过比对请求 URL 与当前主框架 URL 判断
            final failedUrl = error.request?.uri.toString();
            if (failedUrl == null || failedUrl != _currentMainFrameUrl) {
              AppLogger.w('H5Container subresource HTTP ${error.response?.statusCode} ignored: $failedUrl');
              return;
            }
            _cancelTimeoutTimer();
            AppLogger.e('H5Container HTTP error: ${error.response?.statusCode}');
            setState(() {
              _hasError = true;
              _errorType = H5ErrorType.http;
              _errorMessage = 'HTTP ${error.response?.statusCode}';
            });
            _startAutoRetryTimer();
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


    // 强制清除webview缓存，先注释掉吧，由设置里去清理，不然每次打开应用都重新加载，太慢了
    //_controller.clearCache();

    // 加载页面
    _loadPage();

    // 配置 iOS WebView
    _configureIOSWebView();

    // 设置 JS Bridge 回调
    JsBridgeHandler.instance.onSendToH5 = _sendToH5;
    JsBridgeHandler.instance.initialize();
    
    // 监听语音引擎就绪事件，推送到 H5
    _setupVoiceEngineReadyListener();
  }

  void _startTimeoutTimer() {
    _cancelTimeoutTimer();
    _timeoutTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && _isLoading && !_hasError) {
        AppLogger.e('H5Container: Loading timed out after 15 seconds (Timer forced)');
        // 让 webview 强行停止加载
        _controller.runJavaScript('window.stop();').catchError((_) {});
        setState(() {
          _hasError = true;
          _errorType = H5ErrorType.timeout;
          _isLoading = false;
        });
        _startAutoRetryTimer();
      }
    });
  }

  void _cancelTimeoutTimer() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
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
    AppLogger.i('H5Container: Voice engine ready event sent to H5');
  }

  /// 加载页面（支持 assets 和远程 URL）
  void _loadPage() {
    var url = _targetUrl;

    if (url.isEmpty) {
      setState(() {
        _hasError = true;
        _errorMessage = '未配置 H5 首页 URL';
      });
      return;
    }

    AppLogger.i('H5Container loading URL: $url');
    // 预置主框架 URL，确保 onHttpError 在 onPageStarted 之前触发时也能正确判定
    _currentMainFrameUrl = url;
    // 立即启动超时计时：TCP 连接失败时 onPageStarted 永远不会触发，
    // 必须从 loadRequest 调用起就开始计时，否则要等内核 TCP 重试 60s+ 才报错
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    _startTimeoutTimer();

    try {
      if (url.startsWith('assets/')) {
        _controller.loadFlutterAsset(url).catchError((e) {
          _handleLoadError(e);
        });
      } else {
        // 尝试解析 URI，如果失败会抛出 FormatException
        final uri = Uri.parse(url);
        if (!uri.hasScheme && !url.startsWith('http')) {
           // 如果没有 scheme 且不是 asset，可能是缺少 http/https，或者是 asset 路径写错了
           throw FormatException('Invalid scheme: $url');
        }
        _controller.loadRequest(uri).catchError((e) {
             _handleLoadError(e);
        });
      }
    } catch (e) {
      _handleLoadError(e);
    }
  }

  void _handleLoadError(dynamic error) {
    AppLogger.e('Failed to load page: $error');
    if (mounted) {
      setState(() {
        _hasError = true;
        _errorType = H5ErrorType.unknown;
        _errorMessage = '页面加载失败: $error';
      });
      _startAutoRetryTimer();
    }
  }

  /// 注入防 bounce 脚本
  Future<void> _injectNoBounceScript() async {
    try {
      await _controller.runJavaScript('''
        (function() {
          if (document.getElementById('xiaoxin-no-bounce-style')) return;
          
          var style = document.createElement('style');
          style.id = 'xiaoxin-no-bounce-style';
          style.innerHTML = `
            body, html {
              overflow: hidden !important;
              overscroll-behavior: none !important;
              position: fixed !important;
              height: 100vh !important;
              width: 100vw !important;
            }
            body *, html * {
              -webkit-overflow-scrolling: touch !important;
            }
          `;
          if (document.head) {
            document.head.appendChild(style);
          }
        })();
      ''');
    } catch (e) {
      AppLogger.e('Failed to inject no-bounce script: $e');
    }
  }

  /// 配置 iOS WebView
  void _configureIOSWebView() {
    try {
      final platform = _controller.platform;
      (platform as dynamic).setAllowsBackForwardNavigationGestures(false);
    } catch (e) {
      // Android 或其他平台会抛出异常，忽略即可
    }
  }

  /// 判断是否为需要在外部浏览器打开的链接（隐私政策等）
  bool _isExternalUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path.toLowerCase();
      // 匹配隐私政策页面
      if (path.endsWith('/privacy-policy.html') ||
          path.endsWith('/privacy-policy-en.html')) {
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// 在系统浏览器中打开链接（iOS 上即 Safari）
  Future<void> _openInExternalBrowser(String url) async {
    try {
      AppLogger.i('H5Container: Opening in external browser: $url');
      final uri = Uri.parse(url);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        AppLogger.e('H5Container: Failed to launch external url: $url');
      }
    } catch (e) {
      AppLogger.e('H5Container: Exception launching external url: $url', e);
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
          
          _receive: function(message) {
            try {
              var msg = JSON.parse(message);
              if (msg.id && this._callbacks[msg.id]) {
                this._callbacks[msg.id](msg.success, msg.data, msg.error);
                delete this._callbacks[msg.id];
                return;
              }
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
          
          on: function(event, handler) {
            if (!this._eventHandlers[event]) {
              this._eventHandlers[event] = [];
            }
            this._eventHandlers[event].push(handler);
          },
          
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
          setVoiceParams: function(data, callback) { this._send('setVoiceParams', data, callback); },
          stopVoice: function(callback) { this._send('stopVoice', null, callback); },
          abortVoice: function(callback) { this._send('abortVoice', null, callback); },
          getState: function(callback) { this._send('getState', null, callback); },
          getConfig: function(callback) { this._send('getConfig', null, callback); },
          setConfig: function(data, callback) { this._send('setConfig', data, callback); },
          setVolume: function(value, callback) { this._send('setVolume', {value: value}, callback); },
          getVolume: function(callback) { this._send('getVolume', null, callback); },
          setBrightness: function(value, callback) { this._send('setBrightness', {value: value}, callback); },
          getBrightness: function(callback) { this._send('getBrightness', null, callback); },
          setKeepScreenOn: function(keepOn, callback) { this._send('setKeepScreenOn', {keepOn: keepOn}, callback); },
          startKws: function(callback) { this._send('startKws', null, callback); },
          stopKws: function(callback) { this._send('stopKws', null, callback); },
          enableVad: function(enable, callback) { this._send('enableVad', {enable: enable}, callback); }
        };
        
        // 兼容旧版 AndroidNative 命名空间
        window.AndroidNative = {
          setScreenBrightness: function(brightness) { 
            XiaoXin._send('setBrightness', {value: brightness}); 
            return JSON.stringify({ success: true, message: '亮度设置请求已发送' });
          },
          getScreenBrightness: function(callbackName) { 
            XiaoXin._send('getBrightness', null, function(success, data) {
              if (typeof window[callbackName] === 'function') {
                window[callbackName](JSON.stringify({ success: success, brightness: data.brightness }));
              }
            });
          },
          setKeepScreenOn: function(keepOn) { 
            XiaoXin._send('setKeepScreenOn', {keepOn: keepOn}); 
            return JSON.stringify({ success: true, message: '屏幕常亮设置请求已发送' });
          }
        };
        
        var event = new CustomEvent('xiaoxin:ready');
        window.dispatchEvent(event);
        
        // 兼容旧版就绪事件
        window._voiceInteractionReady = true;
        var legacyEvent = new Event('voiceInteractionReady');
        window.dispatchEvent(legacyEvent);
        
        console.log('XiaoXin JS Bridge initialized (with AndroidNative compatibility)');
      })();
    ''';

    await _controller.runJavaScript(jsCode);
    AppLogger.i('H5Container: JS Bridge injected');
  }


  /// 发送消息到 H5
  void _sendToH5(String message) {
    final escapedMessage = message.replaceAll("'", "\\'");
    _controller.runJavaScript("XiaoXin._receive('$escapedMessage');");
  }

  /// 重新加载页面
  void _retry() {
    _cancelAutoRetryTimer();
    setState(() {
      _hasError = false;
      _errorType = H5ErrorType.none;
      _isLoading = true;
    });
    _loadPage();
  }

  /// 显示密码输入对话框
  void _showPasswordDialog() {
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('输入管理密码'),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          decoration: const InputDecoration(hintText: '密码'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final isValid = await ConfigService.instance
                  .verifyConfigPassword(passwordController.text);
              if (!context.mounted) return;
              if (isValid) {
                Navigator.pop(context);
                // 跳转到设置页面
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SettingsPage(),
                  ),
                );
                // 从设置页返回后重新加载
                _retry();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('密码错误')),
                );
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 判断触摸点是否落在右下角管理入口区域。
  bool _isInAdminHotArea(Offset globalPosition, {double inflate = 0}) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return false;
    }

    final localPosition = renderObject.globalToLocal(globalPosition);
    final size = renderObject.size;
    final hotArea = Rect.fromLTWH(
      size.width - _adminHotAreaSize,
      size.height - _adminHotAreaSize,
      _adminHotAreaSize,
      _adminHotAreaSize,
    ).inflate(inflate);

    return hotArea.contains(localPosition);
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_adminPointerId != null || !_isInAdminHotArea(event.position)) {
      return;
    }

    _adminPointerId = event.pointer;
    _adminLongPressTriggered = false;
    _adminLongPressTimer?.cancel();
    _adminLongPressTimer = Timer(_adminLongPressDuration, () {
      if (!mounted ||
          _adminPointerId != event.pointer ||
          !_isInAdminHotArea(
            event.position,
            inflate: _adminMoveTolerance,
          )) {
        return;
      }

      _adminLongPressTriggered = true;
      _showPasswordDialog();
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_adminPointerId != event.pointer || _adminLongPressTriggered) {
      return;
    }

    if (!_isInAdminHotArea(event.position, inflate: _adminMoveTolerance)) {
      _cancelAdminLongPressTimer();
    }
  }

  void _onPointerEnd(PointerEvent event) {
    if (_adminPointerId == event.pointer) {
      _cancelAdminLongPressTimer();
    }
  }

  void _cancelAdminLongPressTimer() {
    _adminLongPressTimer?.cancel();
    _adminLongPressTimer = null;
    _adminPointerId = null;
    _adminLongPressTriggered = false;
  }

  /// 进入错误页后，每 30 秒自动尝试重新加载页面。
  /// 本地资源（assets://）无需自动重试，直接跳过。
  void _startAutoRetryTimer() {
    _cancelAutoRetryTimer();
    // 本地资源没有网络主机，自动重试无意义
    if (_targetUrl.startsWith('assets/')) return;
    _autoRetryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted || !_hasError) {
        _cancelAutoRetryTimer();
        return;
      }
      AppLogger.i('Auto-retry: reloading page...');
      _retry();
    });
  }

  void _cancelAutoRetryTimer() {
    _autoRetryTimer?.cancel();
    _autoRetryTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerEnd,
        onPointerCancel: _onPointerEnd,
        child: Stack(
          children: [
            // WebView
            if (!_hasError) WebViewWidget(controller: _controller),

            // 加载指示器
            if (_isLoading && !_hasError)
              const Center(
                child: CircularProgressIndicator(),
              ),

            // 错误页面
            if (_hasError) _buildErrorView(),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    IconData iconData;
    String title;
    String subtitle;
    
    String buttonText = '刷新重试';
    IconData buttonIcon = Icons.refresh;
    VoidCallback onButtonPressed = _retry;

    switch (_errorType) {
      case H5ErrorType.http:
        iconData = Icons.find_in_page_outlined;
        title = '页面走丢了';
        subtitle = '您访问的服务暂时不可用，请稍后重试\\n($_errorMessage)';
        break;
      case H5ErrorType.timeout:
      case H5ErrorType.network:
        // 合并超时和断网，统一提供重试
        iconData = Icons.wifi_off_outlined;
        title = '无法连接到服务';
        subtitle = '可能是网络连接断开，或目标服务未响应';
        
        buttonText = '刷新重试';
        buttonIcon = Icons.refresh;
        onButtonPressed = _retry;
        break;
      case H5ErrorType.unknown:
      default:
        iconData = Icons.error_outline;
        title = '页面加载失败';
        subtitle = _errorMessage;
        break;
    }

    // 响应式布局：限制最大宽度，保证在大屏（如10寸/iPad/PC）上内容不会过散
    return Center(
      child: SingleChildScrollView(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                iconData,
                size: 80, // 大尺寸图标
                color: Colors.grey[400],
              ),
              const SizedBox(height: 24),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                      height: 1.5,
                    ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity, // 按钮占满约束宽度
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: onButtonPressed,
                  icon: Icon(buttonIcon),
                  label: Text(
                    buttonText,
                    style: const TextStyle(fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
