/// XiaoXin APP - 主入口
/// 精简入口，只做必要配置，启动后进入 LoadingPage
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'modules/settings/config_service.dart';
import 'services/background_service.dart';
import 'ui/pages/loading_page.dart';
import 'utils/constants.dart';
import 'utils/logger.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 只初始化必要配置（快速）
  await ConfigService.instance.initialize();
  // 动态获取应用版本号和包名（从 pubspec.yaml）
  await AppConstants.initAsync();
  final audioConfig = ConfigService.instance.audioConfig;
  final appConfig = ConfigService.instance.config;
  AppLogger.i('ConfigService initialized');
  AppLogger.i('  Device: id=${appConfig.deviceId}, clientId=${appConfig.clientId}');
  AppLogger.i('  Environment: ${appConfig.currentEnvironment.displayName}, '
      'wsUrl=${appConfig.effectiveWsUrl ?? "未配置，由OTA推送"}, '
      'h5Url=${appConfig.effectiveH5Url ?? "未配置，由OTA推送"}');
  AppLogger.i('  AudioConfig: '
      'sampleRate=${audioConfig.micSampleRate}, '
      'vadThreshold=${audioConfig.vadThreshold}, '
      'minSilence=${audioConfig.minSilenceDuration}s, '
      'minSpeech=${audioConfig.minSpeechDuration}s, '
      'vadWindow=${audioConfig.vadWindowSize}, '
      'preCacheMs=${audioConfig.vadPreCacheDurationMs}, '
      'kwsScore=${audioConfig.keywordsScore}, '
      'kwsThreshold=${audioConfig.keywordsThreshold}');

  // 初始化并启动后台服务（保活）
  await BackgroundServiceManager.instance.initialize();
  await BackgroundServiceManager.instance.start();

  // 启动应用，首页为 LoadingPage
  AppLogger.i('XiaoXin APP starting...');
  runApp(const ProviderScope(child: XiaoXinApp()));
}

class XiaoXinApp extends StatelessWidget {
  const XiaoXinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'XiaoXin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      // 首页为加载页，初始化完成后跳转到目标页
      home: const LoadingPage(),
    );
  }
}
