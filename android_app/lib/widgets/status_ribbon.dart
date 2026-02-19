import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/connection_provider.dart';
import '../providers/job_provider.dart';
import '../providers/project_provider.dart';
import '../theme.dart';

/// Persistent phase-aware status strip displayed below the app bar.
///
/// Communicates the current workflow state at a glance:
///   - Disconnected (red) with tap-to-configure action
///   - No project selected (amber)
///   - Idle / asking / planning / plan ready / executing / complete / failed
///
/// Replaces the old cloud icon and scattered conditional action bars with a
/// single unified element.
class StatusRibbon extends StatelessWidget {
  /// Called when the user taps the ribbon in the disconnected state.
  final VoidCallback? onTapSettings;

  /// Called when the user taps the ribbon in the "no project" state.
  final VoidCallback? onTapProjectPicker;

  /// Called when the user taps "Review Plan" on the plan-ready ribbon.
  final VoidCallback? onTapReviewPlan;

  /// Called when the user taps "Approve & Execute" on the plan-ready ribbon.
  final VoidCallback? onTapApprove;

  /// Called when the user taps the ribbon in the executing state.
  final VoidCallback? onTapViewExecution;

  const StatusRibbon({
    super.key,
    this.onTapSettings,
    this.onTapProjectPicker,
    this.onTapReviewPlan,
    this.onTapApprove,
    this.onTapViewExecution,
  });

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionProvider>();
    final project = context.watch<ProjectProvider>();
    final job = context.watch<JobProvider>();
    final theme = Theme.of(context);

    // Priority order: disconnected > no project > job phase
    if (!connection.isConnected && !connection.isChecking) {
      return _RibbonTile(
        color: theme.colorScheme.error,
        icon: Icons.cloud_off,
        label: 'Not connected',
        trailing: const Text('Tap to configure'),
        onTap: onTapSettings,
      );
    }

    if (connection.isChecking) {
      return _RibbonTile(
        color: AppTheme.textMuted,
        icon: Icons.sync,
        label: 'Connecting...',
        trailing: const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (project.selectedProject == null) {
      return _RibbonTile(
        color: Colors.amber,
        icon: Icons.folder_off_outlined,
        label: 'No project selected',
        trailing: const Text('Tap to pick'),
        onTap: onTapProjectPicker,
      );
    }

    switch (job.phase) {
      case JobPhase.asking:
      case JobPhase.planning:
        return _RibbonTile(
          color: AppTheme.neonGreen,
          icon: Icons.psychology_outlined,
          label: job.phase == JobPhase.asking
              ? 'Thinking...'
              : 'Building plan...',
          trailing: const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );

      case JobPhase.planReady:
        return _PlanReadyRibbon(
          onReview: onTapReviewPlan,
          onApprove: onTapApprove,
        );

      case JobPhase.approved:
      case JobPhase.executing:
        return _RibbonTile(
          color: Colors.blue,
          icon: Icons.play_circle_outline,
          label: 'Executing...',
          trailing: const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          onTap: onTapViewExecution,
        );

      case JobPhase.complete:
        return _RibbonTile(
          color: Colors.green,
          icon: Icons.check_circle_outline,
          label: 'Execution complete',
        );

      case JobPhase.failed:
        return _RibbonTile(
          color: theme.colorScheme.error,
          icon: Icons.error_outline,
          label: job.errorMessage.isNotEmpty
              ? 'Failed'
              : 'Something went wrong',
        );

      case JobPhase.idle:
      case JobPhase.askDone:
        return const SizedBox.shrink();
    }
  }
}

/// The special expanded ribbon shown when a plan is ready for review.
class _PlanReadyRibbon extends StatelessWidget {
  final VoidCallback? onReview;
  final VoidCallback? onApprove;

  const _PlanReadyRibbon({this.onReview, this.onApprove});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.mutedGreen,
        border: Border(
          bottom: BorderSide(
              color: theme.colorScheme.outline, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.description_outlined,
              size: 18, color: AppTheme.neonGreen),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Plan ready',
              style: TextStyle(
                color: AppTheme.neonGreen,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          OutlinedButton(
            onPressed: onReview,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.neonGreen,
              side: const BorderSide(color: AppTheme.darkGreen),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Review', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onApprove,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Approve & Execute',
                style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

/// A single-line ribbon tile used for most states.
class _RibbonTile extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _RibbonTile({
    required this.color,
    required this.icon,
    required this.label,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          border: Border(
            bottom: BorderSide(color: color.withValues(alpha: 0.3), width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
