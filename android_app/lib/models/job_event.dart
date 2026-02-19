/// Categories of server-sent events from the runner.
enum EventType { step, log, done, error }

/// A single SSE event received during job execution.
class JobEvent {
  final EventType eventType;
  final String data;

  const JobEvent({required this.eventType, required this.data});

  /// Parse an SSE event type string into the enum.
  static EventType _parseEventType(String raw) {
    switch (raw) {
      case 'step':
        return EventType.step;
      case 'log':
        return EventType.log;
      case 'done':
        return EventType.done;
      case 'error':
        return EventType.error;
      default:
        return EventType.log;
    }
  }

  /// Create from raw SSE fields (event type string + data line).
  factory JobEvent.fromSse(String eventType, String data) {
    return JobEvent(
      eventType: _parseEventType(eventType),
      data: data,
    );
  }

  /// Whether this event signals the end of the stream.
  bool get isTerminal =>
      eventType == EventType.done || eventType == EventType.error;
}
