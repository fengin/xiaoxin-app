# 第三方软件依赖许可证声明 (Third Party Licenses)

小新 APP 开源版在开发中使用了多款优秀的开源第三方组件。为尊重其版权，并方便后续开发者使用与审查，特列出本项目主要依赖库及其开源许可证清单：

## 1. 语音链路核心依赖

| 依赖库名称 | 主要用途 | 许可证类型 |
|---|---|---|
| **sherpa_onnx** | ONNX 引擎封装（KWS & VAD 端侧推理） | Apache License 2.0 |
| **opus_flutter** / **opus_dart** | Opus 音频编解码（语音流实时压缩与解压） | MIT License |
| **flutter_pcm_sound** | PCM 原始音频数据低延迟实时播放 | MIT License |
| **record** | 麦克风低延迟音频录制（支持流式 PCM 捕获） | MIT License |
| **web_socket_channel** | WebSocket 实时流式双向对话协议通信 | BSD-3-Clause |

## 2. 核心架构与基础设施

| 依赖库名称 | 主要用途 | 许可证类型 |
|---|---|---|
| **flutter_riverpod** | 应用状态管理与依赖注入 | MIT License |
| **webview_flutter** | 全屏 H5 业务容器（WebView集成） | BSD-3-Clause |
| **url_launcher** | 跳转至外部系统浏览器打开链接 | BSD-3-Clause |
| **flutter_background_service** | Flutter 原生后台挂载常驻服务 | MIT License |
| **flutter_local_notifications** | 后台常驻服务的系统前台通知栏 | BSD-3-Clause |
| **dio** | 网络请求库（用于 OTA 接口调用） | MIT License |
| **shared_preferences** | 轻量级本地 KV 键值配置存储 | BSD-3-Clause |
| **flutter_secure_storage** | iOS Keychain 级的设备标识等敏感存储 | BSD-3-Clause |
| **device_info_plus** | 自动提取设备类型、品牌与系统版本 | BSD-3-Clause |
| **path_provider** | 自动查找系统临时/文档缓存目录 | BSD-3-Clause |
| **permission_handler** | 原生麦克风、通知等权限运行时申请 | MIT License |
| **logger** | 统一的日志分级与打印控制 | MIT License |

## 3. 设备状态控制依赖

| 依赖库名称 | 主要用途 | 许可证类型 |
|---|---|---|
| **volume_controller** | 原生系统媒体音量获取与平滑调控 | MIT License |
| **screen_brightness** | 原生屏幕亮度动态调控（支持平滑渐变） | MIT License |
| **wakelock_plus** | 屏幕挂起控制（保持常亮，防止对话被截断） | BSD-3-Clause |
| **uuid** | 生成唯一的 UUID 作为客户端会话标识 | MIT License |

---

> [!NOTE]
> 本项目的依赖均属于主流、宽松的开源协议（MIT, BSD, Apache 2.0），允许商业使用、修改和再分发。
> 详细依赖版本和锁定信息，请参阅本仓库的 [pubspec.yaml](pubspec.yaml) 文件。
