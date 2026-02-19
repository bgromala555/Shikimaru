import 'package:flutter/material.dart';

import '../models/job_event.dart';

/// A scrollable list of execution log events with auto-scroll.
class LogViewer extends StatefulWidget {
  final List<JobEvent> events;

  const LogViewer({super.key, required this.events});

  @override
  State<LogViewer> createState() => _LogViewerState();
}

class _LogViewerState extends State<LogViewer> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant LogViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-scroll to bottom when new events arrive
    if (widget.events.length > oldWidget.events.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Color _eventColor(EventType type, ThemeData theme) {
    switch (type) {
      case EventType.step:
        return theme.colorScheme.primary;
      case EventType.log:
        return theme.colorScheme.onSurface;
      case EventType.done:
        return Colors.green;
      case EventType.error:
        return theme.colorScheme.error;
    }
  }

  IconData _eventIcon(EventType type) {
    switch (type) {
      case EventType.step:
        return Icons.play_arrow;
      case EventType.log:
        return Icons.terminal;
      case EventType.done:
        return Icons.check_circle;
      case EventType.error:
        return Icons.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (widget.events.isEmpty) {
      return const Center(child: Text('Waiting for events...'));
    }

    return ListView.builder(
      controller: _scrollController,
      itemCount: widget.events.length,
      padding: const EdgeInsets.all(8),
      itemBuilder: (context, index) {
        final event = widget.events[index];
        final color = _eventColor(event.eventType, theme);

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_eventIcon(event.eventType), size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: SelectableText(
                  event.data,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
