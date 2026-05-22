/// XiaoXin APP - 对话消息展示组件
/// 显示 STT/LLM 对话内容
library;

import 'package:flutter/material.dart';

/// 消息类型
enum MessageType {
  user,      // 用户消息（STT）
  assistant, // 助手消息（LLM）
  system,    // 系统消息
}

/// 对话消息
class ChatMessage {
  final String id;
  final MessageType type;
  final String text;
  final String? emotion;
  final DateTime timestamp;

  ChatMessage({
    String? id,
    required this.type,
    required this.text,
    this.emotion,
    DateTime? timestamp,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        timestamp = timestamp ?? DateTime.now();
}

/// 对话消息列表组件
class ChatMessageList extends StatelessWidget {
  final List<ChatMessage> messages;
  final ScrollController? scrollController;

  const ChatMessageList({
    super.key,
    required this.messages,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              '开始对话吧',
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        return ChatMessageBubble(message: messages[index]);
      },
    );
  }
}

/// 单条消息气泡
class ChatMessageBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatMessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.type == MessageType.user;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            _buildAvatar(context, isUser),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser
                    ? colorScheme.primaryContainer
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    // 如果有表情，在文本开头显示
                    message.emotion != null 
                        ? '${_getEmotionEmoji(message.emotion!)} ${message.text}'
                        : message.text,
                    style: TextStyle(
                      color: isUser
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurface,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            _buildAvatar(context, isUser),
          ],
        ],
      ),
    );
  }

  Widget _buildAvatar(BuildContext context, bool isUser) {
    return CircleAvatar(
      radius: 16,
      backgroundColor: isUser
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.secondary,
      child: Icon(
        isUser ? Icons.person : Icons.smart_toy,
        size: 18,
        color: Colors.white,
      ),
    );
  }

  String _getEmotionEmoji(String emotion) {
    switch (emotion) {
      case 'happy':
        return '😊';
      case 'sad':
        return '😢';
      case 'angry':
        return '😠';
      case 'surprised':
        return '😮';
      case 'thinking':
        return '🤔';
      case 'neutral':
        return '😐';
      default:
        return '';
    }
  }
}

/// 对话状态指示器
class ChatStatusIndicator extends StatelessWidget {
  final String status;
  final bool isAnimating;

  const ChatStatusIndicator({
    super.key,
    required this.status,
    this.isAnimating = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isAnimating)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          if (isAnimating) const SizedBox(width: 8),
          Text(
            status,
            style: TextStyle(
              color: Theme.of(context).colorScheme.outline,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
