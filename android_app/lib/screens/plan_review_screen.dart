import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

import '../providers/job_provider.dart';
import '../theme.dart';

/// Fullscreen plan review screen, available as a fallback if the bottom sheet
/// is not suitable (e.g. deep-link or tablet layout).
///
/// Renders the plan as Markdown with an Approve button at the bottom when the
/// plan is in the PLAN_READY phase.
class PlanReviewScreen extends StatelessWidget {
  const PlanReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final job = context.watch<JobProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plan Review'),
        centerTitle: true,
      ),
      body: job.planMarkdown.isEmpty
          ? Center(
              child: Text(
                'No plan generated yet.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: AppTheme.textMuted,
                ),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: Markdown(
                    data: job.planMarkdown,
                    selectable: true,
                    padding: const EdgeInsets.all(16),
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 14),
                      h1: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold),
                      h2: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
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
                if (job.canApprove)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () async {
                          await job.approveAndExecute();
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Approve & Execute'),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
