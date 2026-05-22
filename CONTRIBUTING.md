# 贡献指南 (Contributing to Xiaoxin App)

感谢您对小新 APP 的关注与支持！我们非常欢迎社区成员参与项目的共同建设。无论是以提问、报告 Bug、提出新想法，还是直接提交代码的形式，您的贡献对我们都十分宝贵。

---

## 如何贡献

### 1. 报告 Bug 和提出建议
如果您在运行中遇到任何问题，或者希望我们添加新功能，欢迎通过 GitHub Issues 提交：
* 在提问前，请先搜索已有的 Issue，确认是否有人已经提出过类似问题。
* 提 Bug 时，请尽量提供**完整的运行日志、设备环境说明（Android/iOS/Flutter 版本）以及可以复现的步骤**。

### 2. 提交代码 (Pull Request)
若您已经修复了一个 Bug 或开发了新功能，欢迎随时提交 Pull Request (PR)：
1. **Fork** 本仓库到您个人的 GitHub 账号下。
2. 基于最新 `main` 分支拉出一条您的专属开发分支：
   ```bash
   git checkout -b feature/your-awesome-feature
   ```
3. 在开发分支上编写、调试代码。
4. **确保代码风格与规范一致**：提交前请运行 `flutter analyze` 检查静态代码规范，确保无任何 Error/Warning 警告。
5. 提交 commit（请提供清晰有意义的提交文案）。
6. 将分支推送到您的远程 Fork 仓库：
   ```bash
   git push origin feature/your-awesome-feature
   ```
7. 访问原项目 GitHub 页面，发起一个新的 **Pull Request**，并描述您的修改内容和测试验证效果。

---

## 代码规范与技术选型

1. **核心语音链路**：我们的语音录音、音视频格式转换、VAD (语音活动检测) 及 KWS (唤醒检测) 极度追求性能与低延迟，修改核心通信/采集代码时请充分考量低端硬件的并发与对齐风险（如 armeabi-v7a 上的 onnxruntime 对齐问题）。
2. **H5 容器与 JS Bridge**：`h5_container_page.dart` 和 `js_bridge_handler.dart` 提供对 H5 界面的深度能力集成。新增加的方法建议在 `H5_VOICE_SDK.md` 协议文档中一并更新，并保持向后兼容。
3. **状态管理**：应用使用 `flutter_riverpod` 作为核心状态管理框架，请尽量避免在 UI 层做重状态处理，将业务及长生命周期的服务收拢在 Provider 中，保持视图层纯粹与高性能。
