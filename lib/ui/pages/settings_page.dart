/// XiaoXin APP - 设置页面
/// 采用 Tab 布局：环境配置 | 设备与安全 | 应用锁定
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../models/audio_config.dart';
import '../../models/environment_config.dart';
import '../../modules/settings/config_service.dart';
import '../../modules/ota/ota_service.dart';
import '../../utils/constants.dart';
import '../../utils/logger.dart';
import '../widgets/floating_edit_overlay.dart';

/// 设置页面
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Environment _selectedEnvironment = Environment.test;
  bool _isLoading = false;

  // 环境配置控制器
  final Map<Environment, _EnvControllers> _envControllers = {};
  final TextEditingController _deviceIdController = TextEditingController();
  final TextEditingController _customDeviceNameController = TextEditingController();
  final TextEditingController _authCodeController = TextEditingController();
  final TextEditingController _businessParamsController = TextEditingController();



  // 音频配置
  int _selectedSampleRate = AudioConfig.opusSampleRate;
  
  // VAD 参数
  double _vadThreshold = AppConstants.vadThreshold;
  double _minSilenceDuration = AppConstants.minSilenceDuration;
  double _minSpeechDuration = AppConstants.minSpeechDuration;
  int _vadWindowSize = AppConstants.vadWindowSize;
  int _vadPreCacheDurationMs = AppConstants.vadPreCacheDurationMs;
  
  // KWS 参数
  double _keywordsScore = AppConstants.keywordsScore;
  double _keywordsThreshold = AppConstants.keywordsThreshold;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initControllers();
    _loadSettings();
  }

  void _initControllers() {
    for (final env in Environment.values) {
      _envControllers[env] = _EnvControllers();
    }
  }

  void _loadSettings() {
    final config = ConfigService.instance.config;
    _selectedEnvironment = config.currentEnvironment;
    _deviceIdController.text = config.deviceId;
    _customDeviceNameController.text = config.customDeviceName ?? '';
    _authCodeController.text = config.authCode;

    // 加载音频配置
    final audioConfig = config.audioConfig;
    _selectedSampleRate = audioConfig.micSampleRate;
    _vadThreshold = audioConfig.vadThreshold;
    _minSilenceDuration = audioConfig.minSilenceDuration;
    _minSpeechDuration = audioConfig.minSpeechDuration;
    _vadWindowSize = audioConfig.vadWindowSize;
    _vadPreCacheDurationMs = audioConfig.vadPreCacheDurationMs;
    _keywordsScore = audioConfig.keywordsScore;
    _keywordsThreshold = audioConfig.keywordsThreshold;

    for (final env in Environment.values) {
      final envConfig = config.environments.getConfig(env);
      _envControllers[env]!.otaUrl.text = envConfig.otaUrl;
      _envControllers[env]!.wsUrl.text = envConfig.wsUrl ?? '';
      _envControllers[env]!.h5Url.text = envConfig.h5Url ?? '';
    }

    // 加载业务参数
    final extendParams = config.extendParams;
    if (extendParams != null && extendParams.isNotEmpty) {
      const encoder = JsonEncoder.withIndent('  ');
      _businessParamsController.text = encoder.convert(extendParams);
    } else {
      _businessParamsController.text = '{}';
    }
  }



  @override
  void dispose() {
    _tabController.dispose();
    _deviceIdController.dispose();
    _customDeviceNameController.dispose();
    _authCodeController.dispose();
    _businessParamsController.dispose();
    for (final c in _envControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(text: '环境配置'),
            const Tab(text: '设备与安全'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _refreshOtaConfig,
            tooltip: '刷新 OTA',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildEnvConfigTab(),
                _buildDeviceSecurityTab(),
              ],
            ),
          ),
          // 底部保存按钮
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _saveSettings,
                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save, size: 18),
                label: const Text('保存配置'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ========== Tab 1: 环境配置 ==========
  Widget _buildEnvConfigTab() {
    final config = ConfigService.instance.config;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // 环境选择器
        _buildCompactSection('选择环境', _buildEnvironmentSelector()),
        const SizedBox(height: 8),

        // 当前环境配置
        _buildCompactSection(
          '${_selectedEnvironment.displayName}配置',
          _buildEnvConfigFields(_selectedEnvironment),
        ),
        const SizedBox(height: 8),

        // OTA 授权状态
        _buildCompactSection('授权状态', _buildOtaStatus()),
        const SizedBox(height: 8),

        // 生效中的配置
        _buildCompactSection('生效中的配置', Column(
          children: [
            _buildInfoRow('WebSocket', config.effectiveWsUrl ?? '未配置'),
            _buildInfoRow('H5 页面', config.effectiveH5Url ?? '默认 Demo'),
          ],
        )),
      ],
    );
  }

  Widget _buildEnvironmentSelector() {
    return SegmentedButton<Environment>(
      segments: Environment.values.map((env) {
        return ButtonSegment<Environment>(
          value: env,
          label: Text(env.displayName, style: const TextStyle(fontSize: 12)),
        );
      }).toList(),
      selected: {_selectedEnvironment},
      onSelectionChanged: (selected) {
        setState(() => _selectedEnvironment = selected.first);
      },
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildEnvConfigFields(Environment env) {
    final c = _envControllers[env]!;
    return Column(
      children: [
        _buildCompactTextField(c.otaUrl, 'OTA 地址 *', Icons.cloud_download),
        const SizedBox(height: 6),
        _buildCompactTextField(c.wsUrl, 'WebSocket(可选)', Icons.wifi),
        const SizedBox(height: 6),
        _buildCompactTextField(c.h5Url, 'H5地址(可选)', Icons.web),
      ],
    );
  }

  Widget _buildOtaStatus() {
    final ota = OtaService.instance;
    final hasCode = ota.activationCode != null;
    final isActivated = ota.isActivated;

    return Row(
      children: [
        Icon(
          isActivated
              ? Icons.check_circle
              : (hasCode ? Icons.pending : Icons.help_outline),
          size: 18,
          color: isActivated
              ? Colors.green
              : (hasCode ? Colors.orange : Colors.grey),
        ),
        const SizedBox(width: 8),
        Text(
          isActivated ? '已激活' : (hasCode ? '待激活: ${ota.activationCode}' : '未检查'),
          style: const TextStyle(fontSize: 13),
        ),
      ],
    );
  }

  // ========== Tab 2: 设备与安全 ==========
  Widget _buildDeviceSecurityTab() {
    final config = ConfigService.instance.config;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // 音频配置
        _buildCompactSection('音频配置', Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.mic, size: 16, color: Colors.blue.shade700),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('适配不同设备的麦克风特性',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildSampleRateSelector(),
          ],
        )),
        const SizedBox(height: 8),
        
        // VAD 参数
        _buildCompactSection('VAD 参数（语音活动检测）', Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('安静环境: 阈值0.5, 静音500ms | 嘈杂环境: 阈值0.8, 静音1000ms',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 8),
            _buildParamInputRow('VAD 阈值', _vadThreshold.toString(), 
                '低=灵敏，高=严格，范围 0.3~0.9',
                (v) => setState(() => _vadThreshold = double.tryParse(v) ?? _vadThreshold)),
            _buildParamInputRow('静音时长 (ms)', (_minSilenceDuration * 1000).round().toString(),
                '说完后等待时间，范围 300~2000',
                (v) => setState(() => _minSilenceDuration = (int.tryParse(v) ?? 600) / 1000)),
            _buildParamInputRow('语音时长 (ms)', (_minSpeechDuration * 1000).round().toString(),
                '最小有效语音长度，范围 100~600',
                (v) => setState(() => _minSpeechDuration = (int.tryParse(v) ?? 500) / 1000)),
          ],
        )),
        const SizedBox(height: 8),
        
        // KWS 参数
        _buildCompactSection('KWS 参数（热词唤醒）', Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('播放期间打断: 分数1.8~2.0, 阈值0.2~0.3',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 8),
            _buildParamInputRow('增强分数', _keywordsScore.toString(),
                'Boosting Score：高=灵敏，低=严格，范围 1.0~2.0',
                (v) => setState(() => _keywordsScore = double.tryParse(v) ?? _keywordsScore)),
            _buildParamInputRow('触发阈值', _keywordsThreshold.toString(),
                'Trigger Threshold：高=严格，低=灵敏，范围 0.3~0.8',
                (v) => setState(() => _keywordsThreshold = double.tryParse(v) ?? _keywordsThreshold)),
          ],
        )),
        const SizedBox(height: 8),

        // 设备信息
        _buildCompactSection('设备信息', Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCompactTextField(
              _deviceIdController,
              '设备 ID (MAC)',
              Icons.fingerprint,
            ),
            const SizedBox(height: 4),
            _buildCompactTextField(
              _customDeviceNameController,
              '设备名',
              Icons.devices,
            ),
            const SizedBox(height: 4),
            _buildCompactTextField(
              _authCodeController,
              '授权码',
              Icons.vpn_key,
            ),
            const SizedBox(height: 4),
            _buildInfoRow('客户端 ID', config.clientId),
            const SizedBox(height: 8),
            // 业务参数
            _buildBusinessParamsField(),
          ],
        )),
        const SizedBox(height: 8),

        // 安全设置
        _buildCompactSection('安全设置', Column(
          children: [
            Row(
              children: [
                Icon(Icons.lock_outline, size: 16, color: Colors.orange.shade700),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('管理密码用于进入设置页，默认 123456',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _showChangePasswordDialog,
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('修改管理密码'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        )),
        const SizedBox(height: 8),

        // 应用信息
        _buildCompactSection('应用信息', Column(
          children: [
            _buildInfoRow('应用名称', AppConstants.appName),
            _buildInfoRow('版本', AppConstants.appVersion),
            _buildInfoRow('包名', AppConstants.packageName),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _handleClearCache(context),
                icon: const Icon(Icons.cleaning_services_outlined, size: 16),
                label: const Text('清除网页缓存'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  foregroundColor: Colors.grey.shade700,
                  side: BorderSide(color: Colors.grey.shade400),
                ),
              ),
            ),
          ],
        )),
      ],
    );
  }

  /// 构建采样率选择器
  Widget _buildSampleRateSelector() {
    return Row(
      children: [
        const SizedBox(
          width: 90,
          child: Text('麦克风采样率', style: TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: DropdownButtonFormField<int>(
            // ignore: deprecated_member_use
            value: _selectedSampleRate,
            isDense: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
            items: AudioConfig.supportedSampleRates.map((rate) {
              final isRecommended = rate == AudioConfig.opusSampleRate;
              return DropdownMenuItem<int>(
                value: rate,
                child: Text(
                  isRecommended ? '$rate Hz (推荐)' : '$rate Hz',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isRecommended ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedSampleRate = value);
              }
            },
          ),
        ),
      ],
    );
  }

  /// 构建参数输入行
  Widget _buildParamInputRow(String label, String initialValue, String tip, 
      ValueChanged<String> onChanged) {
    final isSmall = FloatingEditOverlay.isSmallScreen(context);
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            child: isSmall
                ? _buildReadOnlyFieldWithOverlay(
                    label: label,
                    value: initialValue,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: onChanged,
                  )
                : TextFormField(
                    initialValue: initialValue,
                    style: const TextStyle(fontSize: 12),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: onChanged,
                  ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: tip,
            triggerMode: TooltipTriggerMode.tap,
            child: Icon(Icons.info_outline, size: 16, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  /// 构建只读输入框（点击后弹出浮动编辑框）
  Widget _buildReadOnlyFieldWithOverlay({
    required String label,
    required String value,
    TextInputType? keyboardType,
    required ValueChanged<String> onChanged,
  }) {
    return GestureDetector(
      onTap: () async {
        final result = await FloatingEditOverlay.show(
          context: context,
          label: label,
          initialValue: value,
          keyboardType: keyboardType,
        );
        if (result != null) {
          onChanged(result);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          value,
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  /// 构建业务参数编辑字段
  Widget _buildBusinessParamsField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.code, size: 14, color: Colors.blue.shade700),
            const SizedBox(width: 6),
            const Text('业务参数 (JSON)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh, size: 16),
              onPressed: () {
                // 重新加载当前参数
                final config = ConfigService.instance.config;
                final extendParams = config.extendParams;
                if (extendParams != null && extendParams.isNotEmpty) {
                  const encoder = JsonEncoder.withIndent('  ');
                  _businessParamsController.text = encoder.convert(extendParams);
                } else {
                  _businessParamsController.text = '{}';
                }
                setState(() {});
              },
              tooltip: '刷新参数',
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text('H5 通过 setVoiceParams 设置的参数会显示在此处',
            style: TextStyle(fontSize: 10, color: Colors.grey)),
        const SizedBox(height: 6),
        TextField(
          controller: _businessParamsController,
          maxLines: 5,
          minLines: 3,
          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.all(10),
            border: const OutlineInputBorder(),
            isDense: true,
            hintText: '{\n  "key": "value"\n}',
            hintStyle: TextStyle(fontSize: 11, color: Colors.grey.shade400),
          ),
        ),
      ],
    );
  }




  // ========== 公用组件 ==========
  Widget _buildCompactSection(String title, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  /// 构建紧凑的文本输入框
  Widget _buildCompactTextField(TextEditingController controller, String label, IconData icon) {
    final isSmall = FloatingEditOverlay.isSmallScreen(context);
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            child: isSmall
                ? GestureDetector(
                    onTap: () async {
                      final result = await FloatingEditOverlay.show(
                        context: context,
                        label: label,
                        initialValue: controller.text,
                      );
                      if (result != null) {
                        controller.text = result;
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          Icon(icon, size: 14, color: Colors.grey),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              controller.text.isEmpty ? '点击编辑' : controller.text,
                              style: TextStyle(
                                fontSize: 12,
                                color: controller.text.isEmpty ? Colors.grey : Colors.black,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : TextField(
                    controller: controller,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      prefixIcon: Icon(icon, size: 14, color: Colors.grey),
                      prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 16),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  // ========== 操作方法 ==========

  Future<void> _handleClearCache(BuildContext context) async {
    try {
      // 创建一个临时的 WebViewController 来执行清除缓存操作
      // clearCache() 仅清除 HTTP 缓存（如图片、HTML、JS、CSS），不会清除 LocalStorage
      final controller = WebViewController();
      await controller.clearCache();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('网页缓存已清除（登录状态保留）')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清除失败: $e')),
        );
      }
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isLoading = true);
    try {
      // 保存设备 ID
      final newDeviceId = _deviceIdController.text.trim();
      final config = ConfigService.instance.config;
      if (newDeviceId.isNotEmpty && newDeviceId != config.deviceId) {
        try {
          await ConfigService.instance.setDeviceId(newDeviceId);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('MAC格式错误: $e')));
          }
          return;
        }
      }

      // 保存自定义设备名和授权码
      final newDeviceName = _customDeviceNameController.text.trim();
      if (newDeviceName != (config.customDeviceName ?? '')) {
        await ConfigService.instance.setCustomDeviceName(newDeviceName.isEmpty ? null : newDeviceName);
      }
      
      final newAuthCode = _authCodeController.text.trim();
      if (newAuthCode.isNotEmpty && newAuthCode != config.authCode) {
        await ConfigService.instance.setAuthCode(newAuthCode);
      }


      // 保存环境
      await ConfigService.instance.setCurrentEnvironment(_selectedEnvironment);

      // 保存各环境配置（使用 copyWith 保留 OTA 返回的 otaWsUrl/otaH5Url）
      for (final env in Environment.values) {
        final c = _envControllers[env]!;
        final currentConfig = ConfigService.instance.config.environments.getConfig(env);
        final wsText = c.wsUrl.text.trim();
        final h5Text = c.h5Url.text.trim();
        final envConfig = currentConfig.copyWith(
          otaUrl: c.otaUrl.text.trim(),
          wsUrl: wsText.isEmpty ? null : wsText,
          h5Url: h5Text.isEmpty ? null : h5Text,
          clearWsUrl: wsText.isEmpty,  // 用户清空时，真正置为 null
          clearH5Url: h5Text.isEmpty,  // 使 OTA 推送的值能生效
          // 保留 otaWsUrl 和 otaH5Url（不传参数，copyWith 会保留原值）
        );
        await ConfigService.instance.updateEnvironmentConfig(env, envConfig);
      }

      // 保存音频配置
      final oldAudioConfig = config.audioConfig;
      final newAudioConfig = AudioConfig(
        micSampleRate: _selectedSampleRate,
        vadThreshold: _vadThreshold,
        minSilenceDuration: _minSilenceDuration,
        minSpeechDuration: _minSpeechDuration,
        vadWindowSize: _vadWindowSize,
        vadPreCacheDurationMs: _vadPreCacheDurationMs,
        keywordsScore: _keywordsScore,
        keywordsThreshold: _keywordsThreshold,
      );
      
      final audioConfigChanged = newAudioConfig != oldAudioConfig;
      if (audioConfigChanged) {
        AppLogger.i('Audio config changed: $oldAudioConfig -> $newAudioConfig');
        await ConfigService.instance.updateAudioConfig(newAudioConfig);
      }

      // 保存业务参数
      final paramsText = _businessParamsController.text.trim();
      if (paramsText.isNotEmpty && paramsText != '{}') {
        try {
          final params = jsonDecode(paramsText) as Map<String, dynamic>;
          await ConfigService.instance.replaceExtendParams(params);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('JSON格式错误: $e')));
          }
          return;
        }
      } else {
        await ConfigService.instance.clearExtendParams();
      }

      AppLogger.i('Settings saved');
      if (mounted) {
        final msg = audioConfigChanged
            ? '音频配置已更改，须重启应用生效'
            : '配置已保存，当前环境: ${_selectedEnvironment.displayName}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } catch (e) {
      AppLogger.e('Failed to save settings', e);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshOtaConfig() async {
    setState(() => _isLoading = true);
    try {
      final response = await OtaService.instance.checkVersion();
      if (mounted) {
        final msg = response == null
            ? 'OTA 请求失败'
            : (response.isActivated ? '已激活，配置已更新' : '需要激活');
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('刷新失败: $e')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }



  void _showChangePasswordDialog() {
    final currentPwd = TextEditingController();
    final newPwd = TextEditingController();
    final confirmPwd = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.lock_reset, color: Colors.orange, size: 20),
            SizedBox(width: 8),
            Text('修改管理密码', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentPwd,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '当前密码',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: newPwd,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '新密码',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: confirmPwd,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '确认新密码',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              if (newPwd.text != confirmPwd.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('两次密码不一致')));
                return;
              }
              final isValid = await ConfigService.instance
                  .verifyConfigPassword(currentPwd.text);
              if (!context.mounted) return;
              if (!isValid) {
                // ignore: use_build_context_synchronously
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('当前密码错误')));
                return;
              }
              await ConfigService.instance.saveConfigPassword(newPwd.text);
              if (!context.mounted) return;
              if (ctx.mounted) Navigator.pop(ctx);
              // ignore: use_build_context_synchronously
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('✅ 密码已修改')));
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

/// 环境配置控制器组
class _EnvControllers {
  final TextEditingController otaUrl = TextEditingController();
  final TextEditingController wsUrl = TextEditingController();
  final TextEditingController h5Url = TextEditingController();

  void dispose() {
    otaUrl.dispose();
    wsUrl.dispose();
    h5Url.dispose();
  }
}
