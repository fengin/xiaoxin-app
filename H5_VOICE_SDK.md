# H5 语音交互开发指南

> 本文档提供 xiaoxin-app 中 H5 页面与原生语音能力交互的完整开发指南。

---

## 一、概述

xiaoxin-app 提供了完整的 JS Bridge 接口，允许 H5 页面调用原生语音能力，包括：

- **语音会话控制**：开始/停止/打断语音交互
- **热词唤醒（KWS）**：启用/禁用离线热词检测
- **VAD 控制**：启用/禁用语音活动检测
- **设备信息**：获取设备和应用信息
- **系统控制**：音量、亮度等硬件控制

### 技术架构

```
┌────────────────────────┐
│       H5 页面           │
│   window.XiaoXin API   │
└───────────┬────────────┘
            │ postMessage
            ▼
┌────────────────────────┐
│    XiaoXinBridge       │
│  (JavaScript Channel)  │
└───────────┬────────────┘
            │
            ▼
┌────────────────────────┐
│   JsBridgeHandler      │
│   (原生消息处理器)       │
└───────────┬────────────┘
            │
            ▼
┌────────────────────────┐
│   SessionManager       │
│   (语音会话管理)         │
└────────────────────────┘
```

---

## 二、快速开始

### 2.1 监听 Bridge 就绪

H5 页面加载后，原生会注入 `XiaoXin` 对象到 `window`。有两种方式监听就绪事件：

**方式一：使用事件监听（推荐）**

```javascript
window.addEventListener('xiaoxin:ready', function() {
  console.log('XiaoXin Bridge 已就绪');
  initVoice();
});
```

**方式二：轮询检查**

```javascript
function waitForBridge() {
  if (window.XiaoXin) {
    initVoice();
  } else {
    setTimeout(waitForBridge, 100);
  }
}
waitForBridge();
```

### 2.2 监听语音引擎就绪

语音引擎（Sherpa-ONNX 模型）需要约 10-20 秒加载，加载完成后会触发事件：

```javascript
window.addEventListener('xiaoxin:voiceReady', function() {
  console.log('语音引擎已就绪，可以开始使用语音功能');
  XiaoXin.startKws(); // 启动热词监听
});
```

> **注意**：在语音引擎就绪前，`startVoice`、`startKws` 等语音相关接口可能无法正常工作。

### 2.3 基本使用示例

```javascript
function initVoice() {
  // 获取初始状态
  XiaoXin.getState(function(success, data) {
    if (success) {
      console.log('当前状态:', data.state);
      console.log('KWS 启用:', data.kwsEnabled);
      console.log('VAD 启用:', data.vadEnabled);
    }
  });

  // 注册状态变化监听
  XiaoXin.on('onStateChange', function(data) {
    console.log('状态变化:', data.state);
    updateUI(data.state);
  });

  // 注册语音识别结果监听
  XiaoXin.on('onSttText', function(data) {
    console.log('用户说:', data.text);
    showUserMessage(data.text);
  });

  // 注册 AI 回复监听
  XiaoXin.on('onTtsSentence', function(data) {
    console.log('AI 回复:', data.text);
    showAiMessage(data.text);
  });
}
```

---

## 三、API 接口详解

### 3.1 系统接口

#### `ready(callback)`

检查 Bridge 就绪状态。

```javascript
XiaoXin.ready(function(success, data, error) {
  if (success) {
    console.log('Bridge 已就绪');
  }
});
```

#### `getDeviceInfo(callback)`

获取设备信息。

```javascript
XiaoXin.getDeviceInfo(function(success, data) {
  if (success) {
    console.log('设备型号:', data.model);
    console.log('系统版本:', data.systemVersion);
    console.log('平台:', data.platform); // android / ios
  }
});
```

**返回数据**：
| 字段          | 类型   | 说明               |
| ------------- | ------ | ------------------ |
| model         | string | 设备型号           |
| systemVersion | string | 系统版本           |
| platform      | string | 平台 (android/ios) |
| brand         | string | 设备品牌           |

#### `getAppInfo(callback)`

获取应用信息。

```javascript
XiaoXin.getAppInfo(function(success, data) {
  if (success) {
    console.log('版本号:', data.version);
    console.log('构建号:', data.buildNumber);
  }
});
```

**返回数据**：
| 字段        | 类型   | 说明     |
| ----------- | ------ | -------- |
| appName     | string | 应用名称 |
| packageName | string | 包名     |
| version     | string | 版本号   |
| buildNumber | string | 构建号   |

---

### 3.2 语音控制接口

#### `startVoice(data, callback)`

开始语音会话（连接服务端）。

```javascript
XiaoXin.startVoice({}, function(success, data, error) {
  if (success) {
    console.log('语音会话已开始');
  } else {
    console.error('启动失败:', error);
  }
});
```

**参数**：
| 字段 | 类型 | 说明 |
| ---- | ---- | ---- |
| 无   | -    | -    |

#### `setVoiceParams(data, callback)`

设置语音业务参数（扩展参数）。这些参数将在会话建立和后续对话中传递给服务端。

```javascript
XiaoXin.setVoiceParams({
  userId: "1001",
  roleId: "admin",
  customFlag: true
}, function(success, data, error) {
  if (success) {
    console.log('业务参数已设置:', data);
  }
});
```

**参数**：
| 字段 | 类型   | 必填 | 说明                                   |
| ---- | ------ | ---- | -------------------------------------- |
| data | object | 是   | 键值对形式的业务参数，将与现有参数合并 |

#### `stopVoice(callback)`

停止语音会话（断开连接）。

```javascript
XiaoXin.stopVoice(function(success) {
  if (success) {
    console.log('语音会话已停止');
  }
});
```

#### `abortVoice(callback)`

打断当前 TTS 播放。

```javascript
XiaoXin.abortVoice(function(success) {
  if (success) {
    console.log('已打断播放');
  }
});
```

> **使用场景**：用户点击"停止播放"按钮时调用

---

### 3.3 热词唤醒接口（KWS）

#### `startKws(callback)`

启动热词唤醒监听。

```javascript
XiaoXin.startKws(function(success, data, error) {
  if (success) {
    console.log('热词监听已启动');
  } else {
    console.error('启动失败:', error);
  }
});
```

> **说明**：启动后，用户说出唤醒词（如"小新小新"）会自动触发语音会话。

#### `stopKws(callback)`

停止热词唤醒监听。

```javascript
XiaoXin.stopKws(function(success) {
  if (success) {
    console.log('热词监听已停止');
  }
});
```

#### `getKwsState(callback)`

获取当前 KWS（热词唤醒）启用状态。

```javascript
XiaoXin.getKwsState(function(success, data) {
  if (success) {
    console.log('热词监听是否开启:', data.enabled); // true/false
  }
});
```

**返回数据**：
| 字段    | 类型    | 说明              |
| ------- | ------- | ----------------- |
| enabled | boolean | KWS 是否启用      |

---

### 3.4 VAD 控制接口

#### `enableVad(enable, callback)`

启用或禁用 VAD（语音活动检测）。

```javascript
// 启用 VAD
XiaoXin.enableVad(true, function(success) {
  console.log('VAD 已启用');
});

// 禁用 VAD
XiaoXin.enableVad(false, function(success) {
  console.log('VAD 已禁用');
});
```

> **注意**：通常由原生自动控制，H5 一般不需要直接调用此接口。

#### `getVadState(callback)`

获取当前 VAD（语音活动检测）启用状态。

```javascript
XiaoXin.getVadState(function(success, data) {
  if (success) {
    console.log('VAD 是否开启:', data.enabled); // true/false
  }
});
```

**返回数据**：
| 字段    | 类型    | 说明              |
| ------- | ------- | ----------------- |
| enabled | boolean | VAD 是否启用      |

---

### 3.5 状态查询接口

#### `getState(callback)`

获取当前语音状态。

```javascript
XiaoXin.getState(function(success, data) {
  if (success) {
    console.log('状态:', data.state);       // idle/connecting/listening/speaking
    console.log('KWS:', data.kwsEnabled);   // true/false
    console.log('VAD:', data.vadEnabled);   // true/false
  }
});
```

**返回数据**：
| 字段       | 类型    | 说明                                          |
| ---------- | ------- | --------------------------------------------- |
| state      | string  | 当前状态 (idle/connecting/listening/speaking) |
| kwsEnabled | boolean | KWS 是否启用                                  |
| vadEnabled | boolean | VAD 是否启用                                  |

---

### 3.6 配置接口

#### `getConfig(callback)`

获取当前配置。

```javascript
XiaoXin.getConfig(function(success, data) {
  if (success) {
    console.log('服务器地址:', data.serverUrl);
    console.log('设备ID:', data.deviceId);
  }
});
```

**返回数据**：
| 字段      | 类型   | 说明               |
| --------- | ------ | ------------------ |
| serverUrl | string | WebSocket 服务地址 |
| deviceId  | string | 设备ID             |
| h5Url     | string | H5 首页地址        |

#### `setConfig(data, callback)`

更新配置。

```javascript
XiaoXin.setConfig({
  serverUrl: 'wss://example.com/ws'
}, function(success, data, error) {
  if (success) {
    console.log('配置已更新');
  }
});
```

---

### 3.7 硬件控制接口

#### `setVolume(value, callback)` / `getVolume(callback)`

设置/获取系统音量。

```javascript
// 设置音量 (0.0 - 1.0)
XiaoXin.setVolume(0.8, function(success) {
  console.log('音量已设置');
});

// 获取音量
XiaoXin.getVolume(function(success, data) {
  console.log('当前音量:', data.value);
});
```

#### `setBrightness(value, callback)` / `getBrightness(callback)`

设置/获取屏幕亮度。

```javascript
// 设置亮度 (0.0 - 1.0)
XiaoXin.setBrightness(0.5, function(success) {
  console.log('亮度已设置');
});

// 获取亮度
XiaoXin.getBrightness(function(success, data) {
  console.log('当前亮度:', data.value);
});
```

---

## 四、事件回调

H5 可以通过 `XiaoXin.on(event, handler)` 注册事件监听。

### 4.1 状态事件

#### `onStateChange`

会话状态变化。

```javascript
XiaoXin.on('onStateChange', function(data) {
  // data.state: 'idle' | 'connecting' | 'listening' | 'speaking'
  switch (data.state) {
    case 'idle':
      showIdleUI();
      break;
    case 'listening':
      showListeningUI();
      break;
    case 'speaking':
      showSpeakingUI();
      break;
  }
});
```

**状态说明**：
| 状态       | 说明                 |
| ---------- | -------------------- |
| idle       | 空闲状态（等待唤醒） |
| connecting | 正在连接服务器       |
| listening  | 正在聆听用户说话     |
| speaking   | 正在播放 AI 回复     |

#### `onKwsStateChange`

KWS 启用状态变化。

```javascript
XiaoXin.on('onKwsStateChange', function(data) {
  console.log('KWS 状态:', data.enabled);
});
```

#### `onVadStateChange`

VAD 启用状态变化。

```javascript
XiaoXin.on('onVadStateChange', function(data) {
  console.log('VAD 状态:', data.enabled);
});
```

---

### 4.2 对话事件

#### `onSttText`

语音识别结果（用户说的话）。

```javascript
XiaoXin.on('onSttText', function(data) {
  console.log('用户:', data.text);
  addMessage('user', data.text);
});
```

#### `onLlmText`

LLM 回复文本（AI 回复）。

```javascript
XiaoXin.on('onLlmText', function(data) {
  console.log('AI:', data.text);
  console.log('情绪:', data.emotion);  // 可能为 null
});
```

#### `onTtsStart`

TTS 播放开始。

```javascript
XiaoXin.on('onTtsStart', function(data) {
  showPlayingIndicator();
});
```

#### `onTtsSentence`

TTS 分句文本（用于实时显示 AI 正在说的内容）。

```javascript
XiaoXin.on('onTtsSentence', function(data) {
  updateCurrentSentence(data.text);
});
```

#### `onTtsStop`

TTS 播放结束。

```javascript
XiaoXin.on('onTtsStop', function(data) {
  hidePlayingIndicator();
});
```

---

## 五、完整示例

### 5.1 语音对话页面

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>语音对话</title>
  <style>
    body { font-family: sans-serif; padding: 20px; }
    #status { padding: 10px; background: #f0f0f0; margin-bottom: 20px; }
    #messages { height: 300px; overflow-y: auto; border: 1px solid #ccc; padding: 10px; }
    .message { margin: 10px 0; padding: 10px; border-radius: 8px; }
    .user { background: #e3f2fd; text-align: right; }
    .ai { background: #f5f5f5; }
    button { padding: 10px 20px; margin: 5px; font-size: 16px; }
  </style>
</head>
<body>
  <div id="status">状态: 初始化中...</div>
  <div id="messages"></div>
  <div>
    <button onclick="startVoice()">🎤 开始对话</button>
    <button onclick="stopVoice()">⏹️ 停止</button>
    <button onclick="abortVoice()">🔇 打断</button>
  </div>

  <script>
    // 等待 Bridge 就绪
    window.addEventListener('xiaoxin:ready', initBridge);

    function initBridge() {
      console.log('Bridge 已就绪');
      
      // 获取初始状态
      XiaoXin.getState(function(success, data) {
        if (success) updateStatus(data.state);
      });

      // 注册事件监听
      XiaoXin.on('onStateChange', function(data) {
        updateStatus(data.state);
      });

      XiaoXin.on('onSttText', function(data) {
        addMessage('user', data.text);
      });

      XiaoXin.on('onTtsSentence', function(data) {
        addMessage('ai', data.text);
      });
    }

    function updateStatus(state) {
      const statusMap = {
        'idle': '🟢 空闲（等待唤醒）',
        'connecting': '🟡 连接中...',
        'listening': '🔴 正在聆听...',
        'speaking': '🔵 AI 正在回复...'
      };
      document.getElementById('status').textContent = '状态: ' + (statusMap[state] || state);
    }

    function addMessage(type, text) {
      const div = document.createElement('div');
      div.className = 'message ' + type;
      div.textContent = (type === 'user' ? '我: ' : 'AI: ') + text;
      document.getElementById('messages').appendChild(div);
      div.scrollIntoView();
    }

    function startVoice() {
      XiaoXin.startVoice({}, function(success, data, error) {
        if (!success) alert('启动失败: ' + error);
      });
    }

    function stopVoice() {
      XiaoXin.stopVoice();
    }

    function abortVoice() {
      XiaoXin.abortVoice();
    }
  </script>
</body>
</html>
```

---

## 六、最佳实践

### 6.1 初始化顺序

```javascript
// 1. 监听 Bridge 就绪
window.addEventListener('xiaoxin:ready', function() {
  // 2. 注册所有事件监听
  registerEventListeners();
  
  // 3. 获取初始状态
  XiaoXin.getState(initUI);
});

// 4. 监听语音引擎就绪
window.addEventListener('xiaoxin:voiceReady', function() {
  // 5. 启动 KWS（可选）
  XiaoXin.startKws();
});
```

### 6.2 错误处理

```javascript
XiaoXin.startVoice({}, function(success, data, error) {
  if (!success) {
    switch (error) {
      case 'NO_PERMISSION':
        showPermissionDialog();
        break;
      case 'NETWORK_ERROR':
        showNetworkError();
        break;
      default:
        console.error('未知错误:', error);
    }
  }
});
```

### 6.3 状态同步

```javascript
// 页面显示时同步状态
document.addEventListener('visibilitychange', function() {
  if (!document.hidden) {
    XiaoXin.getState(function(success, data) {
      if (success) updateUI(data.state);
    });
  }
});
```

### 6.4 避免重复注册

```javascript
let listenersRegistered = false;

function registerEventListeners() {
  if (listenersRegistered) return;
  
  XiaoXin.on('onStateChange', handleStateChange);
  XiaoXin.on('onSttText', handleSttText);
  // ...
  
  listenersRegistered = true;
}
```

---

## 七、常见问题

### Q1: Bridge 一直不就绪？

检查 WebView 是否正确加载，查看控制台是否有 JS 错误。

### Q2: 调用 startVoice 无响应？

1. 确认语音引擎已就绪（监听 `xiaoxin:voiceReady` 事件）
2. 检查麦克风权限是否已授权
3. 查看原生日志是否有错误

### Q3: 热词唤醒不工作？

1. 确认已调用 `startKws()`
2. 确认语音引擎已就绪
3. 检查麦克风权限

### Q4: 如何移除事件监听？

```javascript
function myHandler(data) { /* ... */ }

// 注册
XiaoXin.on('onStateChange', myHandler);

// 移除
XiaoXin.off('onStateChange', myHandler);
```

---

## 八、调试建议

1. **打开控制台**：查看 `XiaoXin JS Bridge initialized` 日志确认注入成功
2. **检查事件**：在控制台直接调用 `XiaoXin.getState(console.log)` 测试
3. **查看原生日志**：使用 `adb logcat` (Android) 或 Xcode Console (iOS) 查看详细日志
4. **网络调试**：确认 WebSocket 服务地址可访问

---

## 九、版本兼容

| 接口                    | 最低版本 | 说明         |
| ----------------------- | -------- | ------------ |
| startVoice              | 1.0.0    | 基础语音功能 |
| setVoiceParams          | 1.2.0    | 业务参数设置 |
| startKws/stopKws        | 1.0.0    | 热词唤醒     |
| setVolume/setBrightness | 1.1.0    | 硬件控制     |
| getConfig/setConfig     | 1.0.0    | 配置管理     |
