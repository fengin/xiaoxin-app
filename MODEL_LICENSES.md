# 随附模型来源与许可证说明 (Model Sources and Licenses)

本项目 `assets/models/` 目录下随附了用于语音活动检测 (VAD) 和热词唤醒 (KWS) 的轻量级 ONNX 模型。为了保证合规性，现将这些模型的来源、许可证及再分发条件说明如下：

---

## 1. Silero VAD 模型 (Voice Activity Detection)

* **文件名**：`silero_vad.onnx`
* **来源**：[snakers4/silero-vad](https://github.com/snakers4/silero-vad)
* **介绍**：Silero VAD 是一款高度优化、高准确率、低延迟的语音活动检测模型，广泛用于检测是否有人正在说话。
* **许可证**：[MIT License](https://github.com/snakers4/silero-vad/blob/master/LICENSE)
* **再分发许可**：允许（需随附 MIT 声明）。
* **模型版权所有者**：© Snakers4 / Silero Team

---

## 2. Sherpa-ONNX Zipformer KWS 模型 (Keyword Spotting)

* **相关文件**：
  * `encoder-epoch-12-avg-2-chunk-16-left-64.onnx` (编码器)
  * `decoder-epoch-12-avg-2-chunk-16-left-64.onnx` (解码器)
  * `joiner-epoch-12-avg-2-chunk-16-left-64.onnx` (连接器)
  * `tokens.txt` (词表/Token 文件)
* **来源**：[k2-fsa/sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) 预训练热词模型库。
* **模型类型**：Zipformer KWS 中文语音唤醒模型。
* **介绍**：基于下一代 Kaldi/k2 生态构建，通过轻量级 Zipformer 结构实现端侧高精度的热词（如“小新小新”）实时检测和打断。
* **许可证**：[Apache License 2.0](http://www.apache.org/licenses/LICENSE-2.0)
* **再分发许可**：允许（需随附 Apache 2.0 声明）。
* **模型版权所有者**：© k2-fsa authors

---

## 3. 热词配置文件

* **文件名**：`keywords.txt`
* **说明**：配置热词的发音拼音和对应的文本标签（如 `x iǎo x īn x iǎo x īn @小新小新`）。用户可根据自身需求在此文件中修改和扩展自定义唤醒词，其格式与拼音映射遵循 `sherpa_onnx` 规范。
* **版权说明**：公共领域 (Public Domain) / 宽松使用。

---

> [!NOTE]
> 本项目自带的模型均符合其开源许可证的要求进行随包分发。如果您需要商业化部署或替换为其他语种/更大参数量的模型，请前往 [k2-fsa/sherpa-onnx 模型中心](https://github.com/k2-fsa/sherpa-onnx) 自行下载并替换。
