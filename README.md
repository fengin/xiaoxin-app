# 小新 APP (Xiaoxin App)

> 仿小智客户端 xiaozhi-esp32 实现的 Flutter 跨平台移动端 APP，与小智平台通信遵循小智协议

## 项目简介

小新 APP 是一个基于 Flutter 开发的跨平台语音交互客户端，实现了与 [xiaozhi-esp32](https://github.com/78/xiaozhi-esp32) 相同的通信协议，可连接 xiaozhi-esp32-server-java/python/golang 后端服务。

---

## 核心特性

- ✅ **跨平台**：支持 Android 和 iOS
- ✅ **小智协议**：遵循小智 WebSocket 通信协议（包括 MCP 工具调用）
- ✅ **离线唤醒**：基于 Sherpa-ONNX 的热词唤醒（KWS）和 VAD 检测
- ✅ **流式语音**：Opus 编解码，流式语音交互，低延迟播放
- ✅ **H5 容器**：WebView + JS Bridge，支持业务扩展和语音能力调用
- ✅ **前台服务保活**：Android 前台服务保活，支持后台语音交互
- ✅ **设备ID唯一性**：基于硬件ID生成稳定设备标识（跨卸载保持）
- ✅ **语音参数配置化**：支持 VAD/KWS 灵敏度、采样率等参数自定义
- ✅ **播放和监听单通道**：考虑很多设备不支持回音消除，本设计播放和监听没有支持双工同步，即播放完说话才能被监听，唯有播放时支持热词打断；

---

## 技术栈

| 分类    | 技术                      | 说明                      |
| ----- | ----------------------- | ----------------------- |
| 框架    | Flutter 3.19+           | 跨平台 UI 框架               |
| 语音引擎  | Sherpa-ONNX (VAD + KWS) | 离线语音活动检测和热词唤醒           |
| 通信协议  | WebSocket (小智协议)        | 与服务端实时通信                |
| 音频编解码 | Opus                    | 高效音频压缩                  |
| 音频播放  | flutter_pcm_sound       | 直接 PCM 播放，低延迟           |
| H5 容器 | webview_flutter         | WebView 容器，支持 JS Bridge |
| 录音    | record                  | 跨平台录音支持                 |
| 存储    | shared_preferences      | 配置持久化                   |

---

## 模块架构

```
xiaoxin-app/lib/
├── main.dart                           # 应用入口
│
├── core/                               # 🔴 核心层
│   ├── application.dart               # 应用控制器（生命周期管理）
│   ├── device_state.dart              # 设备状态机定义
│   └── session_manager.dart           # 会话管理器（核心控制器）
│
├── models/                             # 📦 数据模型
│   ├── environment_config.dart        # 多环境配置模型
│   ├── audio_config.dart              # 音频配置模型
│   └── ota_response.dart              # OTA 响应模型
│
├── modules/                            # 🔵 业务模块层
│   ├── audio/                         # 音频模块
│   │   ├── audio_service.dart         # 音频服务门面（统一接口）
│   │   ├── audio_processor.dart       # 音频处理器（录音→编码→发送）
│   │   ├── audio_player_service.dart  # 播放服务（PCM 直接播放）
│   │   ├── audio_session_service.dart # 音频会话（焦点管理）
│   │   ├── circular_audio_buffer.dart # 预缓存环形缓冲区
│   │   ├── opus_service.dart          # Opus 编解码
│   │   └── record_service.dart        # 录音服务
│   │
│   ├── voice/                         # 语音引擎模块
│   │   ├── voice_engine.dart          # 语音引擎（VAD + KWS）
│   │   └── sherpa_onnx_manager.dart   # Sherpa-ONNX 模型管理
│   │
│   ├── protocol/                      # 协议模块
│   │   ├── protocol_service.dart      # WebSocket 通信服务
│   │   └── messages.dart              # 小智协议消息定义
│   │
│   ├── mcp/                           # MCP 模块
│   │   └── mcp_handler.dart           # MCP 消息处理器
│   │
│   ├── webview/                       # H5 容器模块
│   │   ├── js_bridge_handler.dart     # JS Bridge 消息处理
│   │   └── js_bridge_interface.dart   # JS Bridge 接口定义
│   │
│   ├── settings/                      # 设置模块
│   │   ├── config_service.dart        # 配置管理服务
│   │   └── permission_service.dart    # 权限管理服务
│   │
│   └── ota/                           # OTA 模块
│       └── ota_service.dart           # OTA 服务（设备授权）
│
├── ui/                                 # 🟢 UI 层
│   ├── pages/
│   │   ├── loading_page.dart          # 加载页（VoiceEngine初始化）
│   │   ├── h5_container_page.dart     # H5 容器首页（生产环境）
│   │   ├── demo_native_page.dart      # 原生语音对话演示页
│   │   ├── demo_h5_page.dart          # H5 演示页
│   │   └── settings_page.dart         # 设置页
│   └── widgets/                       # 通用组件
│
├── services/                           # 🔧 系统服务层
│   └── background_service.dart        # 后台/前台服务（Android保活）
│
└── utils/                              # 🟡 工具层
    ├── logger.dart                    # 日志工具
    └── constants.dart                 # 常量定义
```

---

## 核心机制

### 设备状态机

```dart
enum DeviceState {
  unknown,      // 未知状态
  idle,         // 空闲状态（热词监听中）
  connecting,   // 正在建立 WebSocket 连接
  listening,    // 聆听中（录音并上传）
  speaking,     // 回复中（播放 TTS 音频）
  configuring,  // 配置中
  error,        // 错误状态
}
```

### 设备ID唯一性

小新 APP 采用基于硬件ID的稳定设备标识生成机制：

| 平台      | 硬件ID来源                         | 唯一性保障                |
| ------- | ------------------------------ | -------------------- |
| Android | `androidId`                    | 应用签名不变时稳定，卸载重装后保持    |
| iOS     | Keychain + identifierForVendor | 存入 Keychain，卸载重装后可恢复 |

生成的设备ID为 MAC 地址格式（`AA:BB:CC:DD:EE:FF`），兼容服务端设备验证。

### 前后台服务保活（Android）

使用 `flutter_background_service` 和 `flutter_local_notifications` 实现 Android 前台服务：

- **前台服务**：在通知栏显示持续通知，防止进程被系统回收
- **触发时机**：语音会话开始时启动，会话结束或应用退到后台时可选停止
- **保活效果**：后台语音交互持续生效，热词唤醒不中断

> iOS 采用系统原生的后台音频模式，无需额外前台服务

### 语音参数配置化

支持通过设置页或配置文件自定义语音参数：

| 参数              | 默认值    | 说明                     |
| --------------- | ------ | ---------------------- |
| `micSampleRate` | 16000  | 麦克风采样率（支持 11025/16000） |
| VAD 灵敏度         | 默认     | 语音活动检测灵敏度（引擎内置）        |
| KWS 热词          | "小新小新" | 唤醒热词配置                 |

小屏设备（短边 ≤ 480dp）默认使用 11025Hz 采样率以优化性能。

---

## 相关项目

- [xiaozhi-esp32](https://github.com/78/xiaozhi-esp32) - 小智官方ESP32 客户端，仅供参考，不进行开发
- xiaoxin-app - 基于小智协议实现的应用客户端，采用flutter开发，支持编译为Android/iOS等客户端
- [xiaozhi-esp32-server-java](https://github.com/joey-zhou/xiaozhi-esp32-server-java) - 符合小智协议的Java 服务端

---

## 文档

- [小智协议](小智协议/)
- [语音对话技术说明](./语音对话技术说明.md)
- [H5 语音交互开发指南](./H5_VOICE_SDK.md)

---

## 应用标识

| 平台      | 包名/Bundle ID       | 显示名称 |
| ------- | ------------------ | ---- |
| Android | `chat.xiaoxin.app` | 小新   |
| iOS     | `chat.xiaoxin.app` | 小新   |
| Dart 包名 | `xiaoxin`          | -    |

---

## 快速开始

```bash
# 克隆项目
git clone <repo-url>
cd xiaoxin-app

# 安装依赖
flutter pub get

# 运行（需要连接设备或模拟器）
flutter run
```

### 界面切换（H5 / Native）

本项目同时支持 **H5 容器界面（示例）** 与 **原生语音对话界面（示例）**。您可以在 [loading_page.dart](file:///d:/code/work/xiaoxin/xiaoxin-app-opensource/lib/ui/pages/loading_page.dart) 中，通过切换目标页面来更改应用的默认启动主界面：

```dart
// lib/ui/pages/loading_page.dart

// 📌 切换目标页：H5ContainerPage (生产) 或 DemoNativePage (调试)
builder: (_) => const H5ContainerPage(), // 生产环境：跳转至 H5 容器页面，加载业务前端系统
// builder: (_) => const DemoNativePage(),  // 调试环境：跳转至原生语音对话演示页面，方便底层链路调优
```

- **H5ContainerPage**：标准H5容器，支持小新的JSBridge调用。加载配置的 WebSocket H5 前端，拥有完整的 H5 视图逻辑，通过 JS Bridge 桥接调用底层的语音对话生命周期，详细H5调用demo见assets/web/demo.html。
- **DemoNativePage**：纯原生调试界面。无需依赖任何 H5 网页或 WebView 渲染，能够最直观地实时显示 VAD 状态、离线热词唤醒匹配、WebSocket 连接状态及对麦克风录音的直接交互，极其适合音质调优、低延迟验证与开发测试。

---

## 更新日志

### [1.0.0+1] - 2026-05-22

- **全新开源首发**：正式公开发布小新 APP 语音对话客户端源代码。
- **端侧 AI 语音链路**：集成了基于 `Sherpa-ONNX` 的中文 Zipformer KWS (热词唤醒) 及 `Silero VAD` (语音活动检测) 高性能离线端侧推理链路，首发自带 13MB 级极致精简的端侧模型包。
- **Opus 流式传输**：实现本地 PCM 采样、Opus 流式双向编解码与播放，完美匹配服务端进行超低延迟语音交互。
- **全屏沉浸式 H5 业务容器**：支持右下角隐藏管理密码入口，支持 JS Bridge 音量控制、屏幕亮度、屏幕常亮、语音控制等原生功能无缝双向互调，兼容经典 `AndroidNative` 接口。
- **多环境自适应**：保留多环境架构（测试/预发/生产），置空带内部语义的配置默认值，首次启动在无可用远程 H5 地址时自动平滑 fallback 至本地 `assets/web/demo.html` 演示页，极大地提升了开箱即用的稳定性。
- **文档体系建设**：提供了详细的 [H5_VOICE_SDK.md](H5_VOICE_SDK.md) 原生扩展接口手册、[语音对话技术说明.md](%E8%AF%AD%E9%9F%B3%E5%AF%B9%E8%AF%9D%E6%8A%80%E6%9C%AF%E8%AF%B4%E6%98%8E.md) 架构指南、[MODEL_LICENSES.md](MODEL_LICENSES.md) 及 [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) 合规清单。
