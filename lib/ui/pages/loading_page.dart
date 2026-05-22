/// XiaoXin APP - 启动加载页
/// 显示加载界面，执行耗时初始化，完成后跳转到目标页
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/session_manager.dart';
import '../../utils/logger.dart';
// 目标页面（手动切换）
import 'h5_container_page.dart';
import 'demo_native_page.dart';

/// 启动加载页
/// 
/// 职责：
/// 1. 显示静态加载界面（不受主线程阻塞影响）
/// 2. 执行耗时初始化（语音引擎、KWS 模型加载等）
/// 3. 初始化完成后跳转到目标页面
class LoadingPage extends StatefulWidget {
  const LoadingPage({super.key});

  @override
  State<LoadingPage> createState() => _LoadingPageState();
}

class _LoadingPageState extends State<LoadingPage> {
  String _statusText = '应用加载中...';
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    // 使用 addPostFrameCallback 确保第一帧渲染完成后再开始初始化
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAndNavigate();
    });
  }

  /// 执行初始化并跳转
  Future<void> _initializeAndNavigate() async {
    try {
      final startTime = DateTime.now();
      AppLogger.i('LoadingPage: Starting initialization...');

      // 更新状态提示
      if (mounted) {
        setState(() {
          _statusText = '正在初始化语音服务...';
        });
      }

      // 执行耗时初始化
      await SessionManager.instance.initialize();  // 语音系统（包含模型加载）

      // 更新状态提示：等待语音引擎就绪
      if (mounted) {
        setState(() {
          _statusText = '正在加载语音引擎...';
        });
      }

      // 等待 VoiceEngine 真正就绪（模型加载完成）
      await _waitForVoiceEngineReady();

      final duration = DateTime.now().difference(startTime);
      AppLogger.i('LoadingPage: All initialization completed in ${duration.inMilliseconds}ms');

      // 跳转到目标页面
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            // 📌 切换目标页：H5ContainerPage (生产) 或 DemoNativePage (调试)
            //builder: (_) => const H5ContainerPage(),
            builder: (_) => const DemoNativePage(),
          ),
        );
      }
    } catch (e, stackTrace) {
      AppLogger.e('LoadingPage: Initialization failed', e, stackTrace);
      if (mounted) {
        setState(() {
          _hasError = true;
          _statusText = '初始化失败: $e';
        });
      }
    }
  }

  /// 等待 VoiceEngine 就绪（模型加载完成）
  Future<void> _waitForVoiceEngineReady() async {
    // 如果已经就绪，直接返回
    if (SessionManager.instance.isVoiceEngineReady) {
      AppLogger.i('LoadingPage: VoiceEngine already ready');
      return;
    }
    
    // 使用 Completer 配合回调
    final completer = Completer<void>();
    
    SessionManager.instance.onVoiceEngineReady = () {
      if (!completer.isCompleted) {
        completer.complete();
        AppLogger.i('LoadingPage: VoiceEngine ready (via callback)');
      }
    };
    
    // 等待回调触发
    await completer.future;
    
    // 清空回调，避免与目标页面冲突
    SessionManager.instance.onVoiceEngineReady = null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo 或应用图标（可选）
            Icon(
              Icons.mic,
              size: 80,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 32),
            
            // 应用名称
            Text(
              '小新',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            
            // 状态提示（静态文案，不受主线程阻塞影响）
            Text(
              _statusText,
              style: TextStyle(
                fontSize: 16,
                color: _hasError ? Colors.red : Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            
            // 错误时显示重试按钮
            if (_hasError) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _hasError = false;
                    _statusText = '应用加载中...';
                  });
                  _initializeAndNavigate();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
