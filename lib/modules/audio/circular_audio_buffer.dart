/// XiaoXin APP - 环形音频缓冲区
/// 用于 VAD 预缓存，解决语音开头丢失问题
library;

import 'dart:typed_data';

/// 环形音频缓冲区
/// 
/// 持续存储最近的音频数据，当 VAD 检测到语音开始时，
/// 可以将预缓存的数据包含在语音片段中，确保语音的完整性。
class CircularAudioBuffer {
  /// 缓冲区
  final Uint8List _buffer;
  
  /// 容量（字节）
  final int capacity;
  
  /// 写入位置
  int _writePos = 0;
  
  /// 可用数据量
  int _availableData = 0;

  /// 构造函数
  /// [durationMs] 缓存时长（毫秒）
  /// [sampleRate] 采样率（Hz）
  /// [bytesPerSample] 每个采样的字节数（16bit = 2）
  CircularAudioBuffer({
    required int durationMs,
    required int sampleRate,
    int bytesPerSample = 2,
  }) : capacity = (durationMs * sampleRate * bytesPerSample) ~/ 1000,
       _buffer = Uint8List((durationMs * sampleRate * bytesPerSample) ~/ 1000);

  /// 写入音频数据
  void write(Uint8List data) {
    if (data.isEmpty) return;
    
    for (int i = 0; i < data.length; i++) {
      _buffer[_writePos] = data[i];
      _writePos = (_writePos + 1) % capacity;
      
      if (_availableData < capacity) {
        _availableData++;
      }
    }
  }

  /// 读取所有可用的音频数据
  Uint8List readAll() {
    if (_availableData == 0) {
      return Uint8List(0);
    }
    
    final result = Uint8List(_availableData);
    
    // 计算读取起始位置
    int readPos = (_writePos - _availableData + capacity) % capacity;
    
    // 读取数据
    for (int i = 0; i < _availableData; i++) {
      result[i] = _buffer[(readPos + i) % capacity];
    }
    
    return result;
  }

  /// 清空缓冲区
  void clear() {
    _writePos = 0;
    _availableData = 0;
  }

  /// 获取当前可用数据量（字节）
  int get availableBytes => _availableData;

  /// 获取当前可用数据的时长（毫秒）
  /// [sampleRate] 采样率
  /// [bytesPerSample] 每个采样的字节数
  int getAvailableDurationMs(int sampleRate, {int bytesPerSample = 2}) {
    return (_availableData * 1000) ~/ (sampleRate * bytesPerSample);
  }

  /// 是否为空
  bool get isEmpty => _availableData == 0;

  /// 是否已满
  bool get isFull => _availableData == capacity;
}
