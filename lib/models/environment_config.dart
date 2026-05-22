/// XiaoXin APP - 环境配置模型
/// 支持三套环境（测试/预发/生产），每套环境包含 OTA/WebSocket/H5 配置
library;

/// 环境类型枚举
enum Environment {
  test('测试环境'),
  pre('预发环境'),
  prod('生产环境');

  final String displayName;
  const Environment(this.displayName);
}

/// 单个环境的配置
class EnvironmentConfig {
  /// OTA 接口地址（必填，用户配置）
  final String otaUrl;

  /// WebSocket 地址（用户本地配置，可选）
  final String? wsUrl;

  /// H5 页面地址（用户本地配置，可选）
  final String? h5Url;

  /// OTA 返回的 WebSocket 地址（自动同步）
  final String? otaWsUrl;

  /// OTA 返回的 H5 地址（自动同步）
  final String? otaH5Url;

  const EnvironmentConfig({
    required this.otaUrl,
    this.wsUrl,
    this.h5Url,
    this.otaWsUrl,
    this.otaH5Url,
  });

  /// 获取有效的 WS 地址（本地配置优先 > OTA 返回）
  String? get effectiveWsUrl =>
      (wsUrl != null && wsUrl!.isNotEmpty) ? wsUrl : otaWsUrl;

  /// 获取有效的 H5 地址（本地配置优先 > OTA 返回）
  String? get effectiveH5Url =>
      (h5Url != null && h5Url!.isNotEmpty) ? h5Url : otaH5Url;

  EnvironmentConfig copyWith({
    String? otaUrl,
    String? wsUrl,
    String? h5Url,
    String? otaWsUrl,
    String? otaH5Url,
    bool clearWsUrl = false,
    bool clearH5Url = false,
    bool clearOtaWsUrl = false,
    bool clearOtaH5Url = false,
  }) {
    return EnvironmentConfig(
      otaUrl: otaUrl ?? this.otaUrl,
      wsUrl: clearWsUrl ? null : (wsUrl ?? this.wsUrl),
      h5Url: clearH5Url ? null : (h5Url ?? this.h5Url),
      otaWsUrl: clearOtaWsUrl ? null : (otaWsUrl ?? this.otaWsUrl),
      otaH5Url: clearOtaH5Url ? null : (otaH5Url ?? this.otaH5Url),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'otaUrl': otaUrl,
      'wsUrl': wsUrl,
      'h5Url': h5Url,
      'otaWsUrl': otaWsUrl,
      'otaH5Url': otaH5Url,
    };
  }

  factory EnvironmentConfig.fromJson(Map<String, dynamic> json) {
    return EnvironmentConfig(
      otaUrl: json['otaUrl'] as String? ?? '',
      wsUrl: json['wsUrl'] as String?,
      h5Url: json['h5Url'] as String?,
      otaWsUrl: json['otaWsUrl'] as String?,
      otaH5Url: json['otaH5Url'] as String?,
    );
  }

  /// 默认测试环境配置
  factory EnvironmentConfig.defaultTest() {
    return const EnvironmentConfig(
      otaUrl: 'http://your-server-ip:8091/api/device/ota',
      wsUrl: 'ws://your-server-ip:8091/ws/xiaoxin/v1/',
      h5Url: null,
    );
  }

  /// 默认预发环境配置
  factory EnvironmentConfig.defaultPre() {
    return const EnvironmentConfig(
      otaUrl: 'http://your-server-ip:8091/api/device/ota',
      wsUrl: null,
      h5Url: null,
    );
  }

  /// 默认生产环境配置
  factory EnvironmentConfig.defaultProd() {
    return const EnvironmentConfig(
      otaUrl: 'https://api.tenclass.net/xiaozhi/ota/',
      wsUrl: null,
      h5Url: null,
    );
  }
}

/// 多环境配置管理
class MultiEnvironmentConfig {
  /// 测试环境配置
  final EnvironmentConfig test;

  /// 预发环境配置
  final EnvironmentConfig pre;

  /// 生产环境配置
  final EnvironmentConfig prod;

  /// 当前选中的环境
  final Environment current;

  const MultiEnvironmentConfig({
    required this.test,
    required this.pre,
    required this.prod,
    this.current = Environment.pre,
  });

  /// 获取当前环境的配置
  EnvironmentConfig get currentConfig {
    switch (current) {
      case Environment.test:
        return test;
      case Environment.pre:
        return pre;
      case Environment.prod:
        return prod;
    }
  }

  /// 获取指定环境的配置
  EnvironmentConfig getConfig(Environment env) {
    switch (env) {
      case Environment.test:
        return test;
      case Environment.pre:
        return pre;
      case Environment.prod:
        return prod;
    }
  }

  MultiEnvironmentConfig copyWith({
    EnvironmentConfig? test,
    EnvironmentConfig? pre,
    EnvironmentConfig? prod,
    Environment? current,
  }) {
    return MultiEnvironmentConfig(
      test: test ?? this.test,
      pre: pre ?? this.pre,
      prod: prod ?? this.prod,
      current: current ?? this.current,
    );
  }

  /// 更新指定环境的配置
  MultiEnvironmentConfig updateEnvironment(
    Environment env,
    EnvironmentConfig config,
  ) {
    switch (env) {
      case Environment.test:
        return copyWith(test: config);
      case Environment.pre:
        return copyWith(pre: config);
      case Environment.prod:
        return copyWith(prod: config);
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'test': test.toJson(),
      'pre': pre.toJson(),
      'prod': prod.toJson(),
      'current': current.name,
    };
  }

  factory MultiEnvironmentConfig.fromJson(Map<String, dynamic> json) {
    // 兼容旧版本的 staging/production 命名
    final preJson = json['pre'] ?? json['staging'];
    final prodJson = json['prod'] ?? json['production'];

    return MultiEnvironmentConfig(
      test: json['test'] != null
          ? EnvironmentConfig.fromJson(json['test'] as Map<String, dynamic>)
          : EnvironmentConfig.defaultTest(),
      pre: preJson != null
          ? EnvironmentConfig.fromJson(preJson as Map<String, dynamic>)
          : EnvironmentConfig.defaultPre(),
      prod: prodJson != null
          ? EnvironmentConfig.fromJson(prodJson as Map<String, dynamic>)
          : EnvironmentConfig.defaultProd(),
      current: _parseEnvironment(json['current'] as String?),
    );
  }

  /// 解析环境名称（兼容旧版本）
  static Environment _parseEnvironment(String? name) {
    if (name == null) return Environment.pre;
    // 兼容旧版本命名
    if (name == 'staging') return Environment.pre;
    if (name == 'production') return Environment.prod;
    return Environment.values.firstWhere(
      (e) => e.name == name,
      orElse: () => Environment.pre,
    );
  }

  /// 默认配置
  factory MultiEnvironmentConfig.defaultConfig() {
    return MultiEnvironmentConfig(
      test: EnvironmentConfig.defaultTest(),
      pre: EnvironmentConfig.defaultPre(),
      prod: EnvironmentConfig.defaultProd(),
      current: Environment.pre,
    );
  }
}
