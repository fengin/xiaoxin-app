/// XiaoXin APP - 浮动编辑框组件
/// 用于小屏设备在键盘上方显示编辑框，解决键盘遮挡输入框问题
library;

import 'package:flutter/material.dart';

/// 浮动编辑框组件
class FloatingEditOverlay extends StatefulWidget {
  final String label;
  final String initialValue;
  final TextInputType? keyboardType;

  const FloatingEditOverlay({
    super.key,
    required this.label,
    required this.initialValue,
    this.keyboardType,
  });

  /// 显示浮动编辑框
  static Future<String?> show({
    required BuildContext context,
    required String label,
    required String initialValue,
    TextInputType? keyboardType,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FloatingEditOverlay(
        label: label,
        initialValue: initialValue,
        keyboardType: keyboardType,
      ),
    );
  }

  /// 检测是否为小屏设备（< 5.5 英寸）
  /// 使用屏幕短边逻辑像素判断，横屏时短边是高度
  static bool isSmallScreen(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final shortSide = size.width < size.height ? size.width : size.height;
    
    // 4 寸屏横屏时短边约 280-360 逻辑像素
    // 5.5 寸屏横屏时短边约 360-480 逻辑像素
    // 6+ 寸手机横屏时短边约 400-600 逻辑像素
    // 使用 480 作为阈值，覆盖大部分小屏设备
    final isSmall = shortSide <= 480;
    
    return isSmall;
  }

  @override
  State<FloatingEditOverlay> createState() => _FloatingEditOverlayState();
}

class _FloatingEditOverlayState extends State<FloatingEditOverlay> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 10,
              offset: Offset(0, -2),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题栏
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  // 确认按钮
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop(_controller.text);
                    },
                    child: const Text('确定'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 输入框
              TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: widget.keyboardType,
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Colors.blue,
                      width: 2,
                    ),
                  ),
                ),
                onSubmitted: (value) {
                  Navigator.of(context).pop(value);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

