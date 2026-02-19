import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/job_provider.dart';
import '../theme.dart';
import '../widgets/log_viewer.dart';

/// Screen that displays streaming execution logs.
///
/// Shows a real-time log viewer that auto-scrolls as events arrive from the
/// runner's polling endpoint.  A status chip at the top indicates the current
/// phase and a "Back to Chat" button appears when execution is done.
class ExecutionScreen extends StatelessWidget {
  const ExecutionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final job = context.watch<JobProvider>();

    final Color statusColor;
    final String statusText;
    final IconData statusIcon;

    switch (job.phase) {
      case JobPhase.executing:
      case JobPhase.approved:
        statusColor = theme.colorScheme.primary;
        statusText = 'Executing...';
        statusIcon = Icons.play_circle_outline;
      case JobPhase.complete:
        statusColor = Colors.green;
        statusText = 'Complete';
        statusIcon = Icons.check_circle_outline;
      case JobPhase.failed:
        statusColor = theme.colorScheme.error;
        statusText = 'Failed';
        statusIcon = Icons.error_outline;
      default:
        statusColor = theme.colorScheme.outline;
        statusText = 'Idle';
        statusIcon = Icons.hourglass_empty;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Execution'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Status bar
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: statusColor.withValues(alpha: 0.1),
            child: Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${job.events.length} events',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),

          // Log viewer
          Expanded(
            child: LogViewer(events: job.events),
          ),

          // Back to Chat button when done
          if (job.phase == JobPhase.complete || job.phase == JobPhase.failed)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('Back to Chat'),
                  style: FilledButton.styleFrom(
                    backgroundColor: job.phase == JobPhase.complete
                        ? AppTheme.neonGreen
                        : theme.colorScheme.error,
                    foregroundColor: job.phase == JobPhase.complete
                        ? AppTheme.backgroundDark
                        : theme.colorScheme.onError,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
