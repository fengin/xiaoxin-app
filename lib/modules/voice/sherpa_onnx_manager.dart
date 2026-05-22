/// XiaoXin APP - Sherpa-ONNX 管理器
/// 负责初始化和管理 KWS（热词唤醒）和 VAD（语音活动检测）模型
library;

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart';
import '../../utils/logger.dart';
import '../../utils/constants.dart';
import '../settings/config_service.dart';

/// Sherpa-ONNX 管理器（单例）
class SherpaOnnxManager {
  static final SherpaOnnxManager instance = SherpaOnnxManager._();
  SherpaOnnxManager._();

  KeywordSpotter? _kws;
  VoiceActivityDetector? _vad;
  OnlineStream? _kwsStream;

  bool _isInitialized = false;
  String? _modelsDir;

  /// 是否已初始化
  bool get isInitialized => _isInitialized;

  /// 复制 asset 文件到本地目录
  Future<String> _copyAssetToFile(String assetPath) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = assetPath.split('/').last;
      final filePath = '${appDir.path}/sherpa_models/$fileName';
      final file = File(filePath);

      if (await file.exists()) {
        AppLogger.d('Model file already exists: $filePath');
        return filePath;
      }

      await file.parent.create(recursive: true);
      final byteData = await rootBundle.load(assetPath);
      await file.writeAsBytes(byteData.buffer.asUint8List());

      AppLogger.d('Copied $assetPath to $filePath');
      return filePath;
    } catch (e, stackTrace) {
      AppLogger.e('Failed to copy asset $assetPath', e, stackTrace);
      rethrow;
    }
  }

  /// 复制所有模型文件
  Future<void> _copyModelFiles() async {
    final startTime = DateTime.now();
    AppLogger.d('Copying model files...');

    final modelFiles = [
      'assets/models/encoder-epoch-12-avg-2-chunk-16-left-64.onnx',
      'assets/models/decoder-epoch-12-avg-2-chunk-16-left-64.onnx',
      'assets/models/joiner-epoch-12-avg-2-chunk-16-left-64.onnx',
      'assets/models/silero_vad.onnx',
      'assets/models/tokens.txt',
      'assets/models/keywords.txt',
    ];

    for (final assetPath in modelFiles) {
      await _copyAssetToFile(assetPath);
    }

    final appDir = await getApplicationDocumentsDirectory();
    _modelsDir = '${appDir.path}/sherpa_models';

    final duration = DateTime.now().difference(startTime);
    AppLogger.i('Model files copied in ${duration.inMilliseconds}ms');
  }

  /// 初始化 Sherpa-ONNX
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      final startTime = DateTime.now();
      AppLogger.i('Initializing Sherpa-ONNX...');

      // 增加延时让出主线程，确保 Loading 页面能够渲染初始状态文案
      await Future.delayed(const Duration(milliseconds: 100));

      // 1. 初始化 sherpa-onnx 绑定
      initBindings();
      AppLogger.d('Bindings initialized');

      // 2. 复制模型文件（移动平台需要）
      if (Platform.isAndroid || Platform.isIOS) {
        await _copyModelFiles();
      } else {
        _modelsDir = 'assets/models';
      }

      // 3. 初始化 KWS (增加延时打断主线程阻塞，避免 ANR，并让 UI 刷新)
      await Future.delayed(const Duration(milliseconds: 100));
      await _initializeKws();

      // 4. 初始化 VAD (再次延时，分段执行)
      await Future.delayed(const Duration(milliseconds: 100));
      await _initializeVad();

      _isInitialized = true;
      final duration = DateTime.now().difference(startTime);
      AppLogger.i('Sherpa-ONNX initialized in ${duration.inMilliseconds}ms');
      return true;
    } catch (e, stackTrace) {
      AppLogger.e('Failed to initialize Sherpa-ONNX', e, stackTrace);
      return false;
    }
  }

  /// 初始化 KWS（关键词检测）
  /// 采样率跟随麦克风配置，以适配不同设备
  Future<void> _initializeKws() async {
    final audioConfig = ConfigService.instance.audioConfig;
    final micSampleRate = audioConfig.micSampleRate;
    AppLogger.d('Initializing KWS with sampleRate=$micSampleRate, '
        'keywordsScore=${audioConfig.keywordsScore}, keywordsThreshold=${audioConfig.keywordsThreshold}...');

    final kwsConfig = KeywordSpotterConfig(
      feat: FeatureConfig(
        sampleRate: micSampleRate,  // 跟随麦克风采样率
        featureDim: 80,
      ),
      model: OnlineModelConfig(
        transducer: OnlineTransducerModelConfig(
          encoder: '$_modelsDir/encoder-epoch-12-avg-2-chunk-16-left-64.onnx',
          decoder: '$_modelsDir/decoder-epoch-12-avg-2-chunk-16-left-64.onnx',
          joiner: '$_modelsDir/joiner-epoch-12-avg-2-chunk-16-left-64.onnx',
        ),
        tokens: '$_modelsDir/tokens.txt',
        numThreads: 1,
        provider: 'cpu',
      ),
      maxActivePaths: 4,
      keywordsFile: '$_modelsDir/keywords.txt',
      keywordsScore: audioConfig.keywordsScore,
      keywordsThreshold: audioConfig.keywordsThreshold,
    );

    _kws = KeywordSpotter(kwsConfig);
    _kwsStream = _kws!.createStream();

    AppLogger.i('KWS initialized with sampleRate=$micSampleRate');
  }

  /// 初始化 VAD（语音活动检测）
  Future<void> _initializeVad() async {
    final audioConfig = ConfigService.instance.audioConfig;
    AppLogger.d('Initializing VAD with threshold=${audioConfig.vadThreshold}, '
        'silence=${audioConfig.minSilenceDuration}s, speech=${audioConfig.minSpeechDuration}s, '
        'windowSize=${audioConfig.vadWindowSize}...');

    final vadConfig = VadModelConfig(
      sileroVad: SileroVadModelConfig(
        model: '$_modelsDir/silero_vad.onnx',
        threshold: audioConfig.vadThreshold,
        minSilenceDuration: audioConfig.minSilenceDuration,
        minSpeechDuration: audioConfig.minSpeechDuration,
        windowSize: audioConfig.vadWindowSize,
        maxSpeechDuration: 30.0,
      ),
      sampleRate: AppConstants.audioSampleRate,
      numThreads: 1,
      provider: 'cpu',
    );

    _vad = VoiceActivityDetector(
      config: vadConfig,
      bufferSizeInSeconds: 30.0,
    );

    AppLogger.i('VAD initialized');
  }

  /// 获取 KWS 实例
  KeywordSpotter? get kws => _kws;

  /// 获取 KWS 流
  OnlineStream? get kwsStream => _kwsStream;

  /// 获取 VAD 实例
  VoiceActivityDetector? get vad => _vad;

  /// 重置 KWS 流
  void resetKwsStream() {
    if (_kws != null) {
      _kwsStream?.free();
      _kwsStream = _kws!.createStream();
    }
  }

  /// 释放资源
  void dispose() {
    AppLogger.d('Releasing Sherpa-ONNX resources...');
    _isInitialized = false;

    try {
      _kwsStream?.free();
      _kwsStream = null;
    } catch (e) {
      AppLogger.e('Error releasing KWS stream', e);
    }

    try {
      _kws?.free();
      _kws = null;
    } catch (e) {
      AppLogger.e('Error releasing KWS', e);
    }

    try {
      _vad?.free();
      _vad = null;
    } catch (e) {
      AppLogger.e('Error releasing VAD', e);
    }

    _modelsDir = null;
    AppLogger.i('Sherpa-ONNX resources released');
  }
}
