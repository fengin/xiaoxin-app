# 小新 APP 自动构建与发布指南 (GitHub Actions CI/CD)

本项目已经集成了 **GitHub Actions** 自动化构建与发布流程。每次当您向 GitHub 仓库推送版本标签（Tag，如 `v1.0.0`）时，GitHub 就会自动拉起云端环境，为您并行构建 Android APK 与 iOS 免签名 IPA 包，并自动创建 GitHub Release 页面发布这些安装包。

---

## 🚀 触发与运行机制

工作流支持两种触发方式：

1. **自动发布 Release（推荐）**：
   - 当您在本地或 GitHub 上创建并推送一个以 `v` 开头的标签（例如 `v1.0.0`）时，工作流会自动触发。
   - 构建完成后，会自动在项目的 **Releases** 页面创建一个新版本，并将构建好的安装包作为附件发布。
   
   **快捷触发命令**：
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

2. **手动测试构建 (workflow_dispatch)**：
   - 您可以登录 GitHub 网页端，点击仓库的 **Actions** 菜单。
   - 选择左侧的 **Build & Release** 工作流，点击右侧的 **Run workflow** 手动触发构建。
   - *注意：手动构建不会创建 GitHub Release，但构建成功后，您可以在 Actions 运行详情页面下方的 Artifacts 区域下载到编译出的临时包。*

---

## 🤖 Android 签名与打包说明

为了在“开源共享”与“正式发布”之间取得完美平衡，我们的构建脚本采用了**“优雅签名降级”**策略：
- **无秘钥状态（开箱即用）**：如果您或任何 fork 您项目的开发者在 GitHub 中未配置任何签名 secrets，构建工作流**依然会 100% 成功运行**，它会自动降级使用 debug 签名来打包 APK，生成的 APK 可直接安装测试。
- **有秘钥状态（正式发布）**：一旦您在您的 GitHub 仓库中配置了签名 secrets，工作流就会自动识别并编译出带有您专属官方签名的正式版 APK。

### 🔑 如何在 GitHub 中配置您的 Android 签名密钥？

如果您需要打包官方签名的 APK，请按照以下步骤操作：

#### 第一步：准备密钥文件及参数
1. 准备好您的 `.jks` 证书文件（例如 `my-release-key.jks`）。
2. 确定您的：
   - 密钥别名 (`Key Alias`)
   - 密钥密码 (`Key Password`)
   - 证书库密码 (`Store Password`)

#### 第二步：获取 JKS 文件的 Base64 编码
由于 GitHub 无法直接上传二进制文件，需要先将 `.jks` 转换为 Base64 文本。

- **Windows (PowerShell)**:
  ```powershell
  [Convert]::ToBase64String([IO.File]::ReadAllBytes("path/to/my-release-key.jks"))
  ```
  *(注：请将 `"path/to/my-release-key.jks"` 替换为您证书的实际路径。运行后复制终端中输出的超长字符串。)*

- **macOS / Linux**:
  ```bash
  openssl base64 -in path/to/my-release-key.jks -out keystore_base64.txt
  cat keystore_base64.txt
  ```

#### 第三步：在 GitHub 仓库中配置 Secrets
1. 打开您的 GitHub 仓库页面，点击顶部的 **Settings**。
2. 在左侧边栏找到 **Secrets and variables** -> 点击 **Actions**。
3. 在 **Repository secrets** 区域，点击 **New repository secret** 按钮，依次添加以下 4 个密钥：

| Secret 名称 | 填入的值 | 说明 |
| :--- | :--- | :--- |
| `ANDROID_KEYSTORE_BASE64` | 第二步生成的超长 Base64 字符串 | Android 签名证书文件的 Base64 密文 |
| `ANDROID_KEY_ALIAS` | 您的 Key Alias（例如 `xiaoxin`） | 密钥别名 |
| `ANDROID_KEY_PASSWORD` | 您的 Key Password | 密钥密码 |
| `ANDROID_STORE_PASSWORD` | 您的 Store Password | 证书库密码 |

配置完成后，下次触发构建时就会自动打出您的专属签名正式包！

---

## 🍎 iOS 免签名 IPA 说明

为了让开源项目的分发尽可能简单，iOS 构建采用 **`--no-codesign` (免签名模式)**。

### 1. 为什么采用免签名构建？
正规的 iOS 签名需要配置每年 99 美元的 Apple 开发者账号以及繁琐的 `p12` 证书和描述文件，这对于开源项目共享来说门槛极高。免签名打包可以直接在 GitHub 的 macOS 云端打包机上顺利运行并产生 `.ipa` 文件，任何 fork 您项目的开发者都可以免去证书困扰一键跑通 CI/CD。

### 2. 免签名的 `.ipa` 如何安装到手机上？
未签名的 IPA 无法直接双击通过 App Store 或官方 iTunes 渠道安装在普通未越狱的 iPhone 上，但极其适合以下高阶玩法的开源用户：
- **TrollStore (巨魔)**：如果您的手机系统版本支持 TrollStore，直接将生成的 `xiaoxin-app.ipa` 导入 TrollStore 即可**完美、永久免签安装运行**，极其流畅。
- **Sideloadly / AltStore**：使用这些签名工具，仅需提供您的免费个人 Apple ID（不需要付费开发者账号），即可自动对 `xiaoxin-app.ipa` 进行重签名并安装到您的手机上（个人免费账号自签的有效期为 7 天，到期后工具会自动帮您刷新）。
- **越狱设备**：可直接安装运行。
- **企业签名或开发者重签名**：若需要大规模分发或正式上架，具体的开发者可以自行将生成的 IPA 下载到本地，使用自己的苹果付费证书重新签名并分发。

这样不仅解决了开源项目 CI 打包 iOS 的难题，也极大地方便了开源用户的自签体验！
