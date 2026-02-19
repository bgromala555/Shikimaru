import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../theme.dart';

/// A single chat message bubble with left/right alignment.
///
/// User messages appear on the right with the primary color background.
/// Bot messages appear on the left with a surface variant color and render
/// their content as Markdown so that code blocks, bold, lists, headers, etc.
/// display correctly.
class MessageBubble extends StatelessWidget {
  /// The message content (plain text for user, Markdown for bot).
  final String text;

  /// Whether this message was sent by the user.
  final bool isUser;

  /// When the message was created.
  final DateTime timestamp;

  /// Whether this message represents an error (shows retry affordance).
  final bool isError;

  /// Called when the user taps the retry button on an error bubble.
  final VoidCallback? onRetry;

  const MessageBubble({
    super.key,
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isError = false,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;

    final bgColor = isError
        ? theme.colorScheme.errorContainer
        : isUser
            ? AppTheme.mutedGreen.withValues(alpha: 0.8)
            : AppTheme.surfaceContainerDark;

    final textColor = isError
        ? theme.colorScheme.onErrorContainer
        : isUser
            ? AppTheme.neonGreen
            : AppTheme.textSecondary;

    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: isUser ? const Radius.circular(16) : Radius.zero,
      bottomRight: isUser ? Radius.zero : const Radius.circular(16),
    );

    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: borderRadius,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isUser)
              SelectableText(
                text,
                style: TextStyle(color: textColor, fontSize: 15),
              )
            else
              MarkdownBody(
                data: text,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  p: TextStyle(color: textColor, fontSize: 15),
                  h1: TextStyle(
                      color: textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                  h2: TextStyle(
                      color: textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                  h3: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600),
                  code: TextStyle(
                    color: AppTheme.neonGreen,
                    backgroundColor: AppTheme.surfaceDark,
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                  codeblockDecoration: BoxDecoration(
                    color: AppTheme.surfaceDark,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  codeblockPadding: const EdgeInsets.all(12),
                  listBullet: TextStyle(color: textColor),
                  strong: TextStyle(
                      color: textColor, fontWeight: FontWeight.bold),
                  em: TextStyle(
                      color: textColor, fontStyle: FontStyle.italic),
                  blockquoteDecoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                          color: AppTheme.darkGreen, width: 3),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
                if (isError && onRetry != null) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: onRetry,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.refresh,
                              size: 14,
                              color: theme.colorScheme.error),
                          const SizedBox(width: 4),
                          Text(
                            'Retry',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
