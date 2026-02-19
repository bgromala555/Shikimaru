import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../theme.dart';

/// A card that renders a Markdown plan with an optional Approve button.
///
/// Used by the [PlanReviewScreen] fullscreen fallback; the primary plan review
/// experience is now the draggable bottom sheet in [ChatScreen].
class PlanCard extends StatelessWidget {
  final String markdown;
  final bool canApprove;
  final VoidCallback? onApprove;

  const PlanCard({
    super.key,
    required this.markdown,
    this.canApprove = false,
    this.onApprove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.description_outlined,
                    color: theme.colorScheme.onPrimaryContainer),
                const SizedBox(width: 8),
                Text(
                  'Generated Plan',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          // Markdown body
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Markdown(
                data: markdown,
                selectable: true,
                shrinkWrap: false,
                styleSheet: MarkdownStyleSheet(
                  p: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 14),
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
                ),
              ),
            ),
          ),

          // Approve button
          if (canApprove)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: FilledButton.icon(
                onPressed: onApprove,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Approve Plan'),
              ),
            ),
        ],
      ),
    );
  }
}
