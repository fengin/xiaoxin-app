/// XiaoXin APP - 音频重采样工具
/// 使用线性插值实现采样率转换
library;

import 'dart:typed_data';
import '../../utils/logger.dart';

/// 音频重采样器
class AudioResampler {
  AudioResampler._();

  static final AudioResampler instance = AudioResampler._();

  /// 线性插值重采样
  /// 将音频数据从 inputSampleRate 转换到 outputSampleRate
  ///
  /// [inputData] 输入的 16-bit PCM 音频数据（小端序）
  /// [inputSampleRate] 输入采样率
  /// [outputSampleRate] 输出采样率
  ///
  /// 返回重采样后的 16-bit PCM 数据
  Uint8List resample({
    required Uint8List inputData,
    required int inputSampleRate,
    required int outputSampleRate,
  }) {
    // 如果采样率相同，直接返回
    if (inputSampleRate == outputSampleRate) {
      return inputData;
    }

    // 将字节数据转换为 Int16 样本
    final inputSamples = _bytesToInt16List(inputData);
    if (inputSamples.isEmpty) {
      return inputData;
    }

    // 计算输出样本数
    final ratio = outputSampleRate / inputSampleRate;
    final outputLength = (inputSamples.length * ratio).ceil();

    // 执行线性插值重采样
    final outputSamples = Int16List(outputLength);

    for (var i = 0; i < outputLength; i++) {
      // 计算输入位置（浮点数）
      final inputPos = i / ratio;
      final inputIndex = inputPos.floor();
      final fraction = inputPos - inputIndex;

      if (inputIndex >= inputSamples.length - 1) {
        // 边界处理：使用最后一个样本
        outputSamples[i] = inputSamples[inputSamples.length - 1];
      } else {
        // 线性插值
        final sample1 = inputSamples[inputIndex];
        final sample2 = inputSamples[inputIndex + 1];
        final interpolated = sample1 + (sample2 - sample1) * fraction;
        outputSamples[i] = interpolated.round().clamp(-32768, 32767);
      }
    }

    // 转换回字节数据
    return _int16ListToBytes(outputSamples);
  }

  /// 将字节数据转换为 Int16 列表（小端序）
  Int16List _bytesToInt16List(Uint8List bytes) {
    if (bytes.length % 2 != 0) {
      AppLogger.w('Audio data length is not even, truncating last byte');
    }
    final sampleCount = bytes.length ~/ 2;
    final samples = Int16List(sampleCount);

    for (var i = 0; i < sampleCount; i++) {
      // 小端序：低字节在前
      final low = bytes[i * 2];
      final high = bytes[i * 2 + 1];
      samples[i] = (high << 8) | low;
      // 处理有符号数
      if (samples[i] > 32767) {
        samples[i] = samples[i] - 65536;
      }
    }

    return samples;
  }

  /// 将 Int16 列表转换为字节数据（小端序）
  Uint8List _int16ListToBytes(Int16List samples) {
    final bytes = Uint8List(samples.length * 2);

    for (var i = 0; i < samples.length; i++) {
      var sample = samples[i];
      // 处理负数
      if (sample < 0) {
        sample = sample + 65536;
      }
      // 小端序：低字节在前
      bytes[i * 2] = sample & 0xFF;
      bytes[i * 2 + 1] = (sample >> 8) & 0xFF;
    }

    return bytes;
  }
}
