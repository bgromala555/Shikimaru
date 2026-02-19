import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/ask_models.dart';
import '../models/job_event.dart';
import '../models/plan_models.dart';
import '../services/runner_api.dart';

/// The workflow phase the current job is in.
enum JobPhase {
  idle,
  asking,
  askDone,
  planning,
  planReady,
  approved,
  executing,
  complete,
  failed,
}

/// The type of action that produced a chat message, used for retry logic.
enum MessageAction { ask, plan, none }

/// A single chat message displayed in the conversation view.
class ChatMessage {
  /// The message content (plain text for user, Markdown for bot).
  final String text;

  /// Whether this message was sent by the user.
  final bool isUser;

  /// When the message was created.
  final DateTime timestamp;

  /// Whether this message represents an error from the runner.
  final bool isError;

  /// The action that generated this message, so failed operations can be
  /// retried without requiring the user to retype their input.
  final MessageAction action;

  ChatMessage({
    required this.text,
    required this.isUser,
    DateTime? timestamp,
    this.isError = false,
    this.action = MessageAction.none,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Manages the current job lifecycle, chat messages, plan data, and execution
/// events.
///
/// This is the primary state holder for the chat + execution flow.
class JobProvider extends ChangeNotifier {
  final RunnerApi _api;

  JobPhase _phase = JobPhase.idle;
  String _jobId = '';
  String _planId = '';
  String _planMarkdown = '';
  String _sessionId = '';
  final List<ChatMessage> _messages = [];
  final List<JobEvent> _events = [];
  List<ClarificationQuestion> _questions = [];
  String _errorMessage = '';
  Timer? _pollTimer;

  JobProvider(this._api);

  JobPhase get phase => _phase;
  String get jobId => _jobId;
  String get planId => _planId;
  String get planMarkdown => _planMarkdown;
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  List<JobEvent> get events => List.unmodifiable(_events);
  List<ClarificationQuestion> get questions => List.unmodifiable(_questions);
  String get errorMessage => _errorMessage;
  bool get canAsk =>
      _phase == JobPhase.idle ||
      _phase == JobPhase.askDone ||
      _phase == JobPhase.planReady ||
      _phase == JobPhase.complete ||
      _phase == JobPhase.failed;
  bool get canPlan =>
      _phase == JobPhase.idle ||
      _phase == JobPhase.askDone ||
      _phase == JobPhase.planReady ||
      _phase == JobPhase.complete ||
      _phase == JobPhase.failed;
  bool get canApprove => _phase == JobPhase.planReady;
  bool get canExecute => _phase == JobPhase.approved;

  /// Reset the job state for a new conversation.
  void reset() {
    _pollTimer?.cancel();
    _phase = JobPhase.idle;
    _jobId = '';
    _planId = '';
    _planMarkdown = '';
    _sessionId = '';
    _messages.clear();
    _events.clear();
    _questions = [];
    _errorMessage = '';
    notifyListeners();
  }

  /// Build a history payload from current messages for API context.
  List<Map<String, String>> _buildHistory() {
    return _messages.map((m) {
      return {
        'role': m.isUser ? 'user' : 'assistant',
        'content': m.text,
      };
    }).toList();
  }

  /// Retry the last failed action by re-sending the most recent user message.
  ///
  /// Removes the error bot message and the preceding user message, then
  /// replays the action.
  Future<void> retryLast(String projectPath) async {
    if (_messages.length < 2) return;

    final errorMsg = _messages.last;
    if (!errorMsg.isError) return;

    final action = errorMsg.action;
    // Walk back to find the user message that triggered the error
    String? userText;
    for (int i = _messages.length - 2; i >= 0; i--) {
      if (_messages[i].isUser) {
        userText = _messages[i].text;
        _messages.removeAt(i);
        break;
      }
    }
    _messages.removeLast(); // remove the error bot message
    notifyListeners();

    if (userText == null) return;

    switch (action) {
      case MessageAction.ask:
        await ask(projectPath, userText);
      case MessageAction.plan:
        await buildPlan(projectPath, userText);
      case MessageAction.none:
        break;
    }
  }

  /// Send a read-only Ask to the runner.
  Future<void> ask(String projectPath, String message) async {
    _addUserMessage(message);
    _phase = JobPhase.asking;
    _errorMessage = '';
    notifyListeners();

    try {
      final response = await _api.postAsk(
        projectPath: projectPath,
        message: message,
        history: _buildHistory(),
        sessionId: _sessionId,
      );
      _jobId = response.jobId;
      _sessionId = response.sessionId;
      _questions = response.questions;
      _addBotMessage(response.askText);
      _phase = JobPhase.askDone;
    } catch (e) {
      _errorMessage = 'Ask failed: $e';
      _phase = JobPhase.failed;
      _addBotMessage('Error: $e', isError: true, action: MessageAction.ask);
    }

    notifyListeners();
  }

  /// Generate a plan via the runner.
  Future<void> buildPlan(String projectPath, String objective) async {
    _addUserMessage(objective);
    _phase = JobPhase.planning;
    _errorMessage = '';
    notifyListeners();

    try {
      final response = await _api.postPlan(
        projectPath: projectPath,
        objective: objective,
        history: _buildHistory(),
        sessionId: _sessionId,
      );
      _jobId = response.jobId;
      _planId = response.planId;
      _planMarkdown = response.planMarkdown;
      _sessionId = response.sessionId;
      _questions = response.questions;
      _addBotMessage(response.planMarkdown);
      _phase = JobPhase.planReady;
    } catch (e) {
      _errorMessage = 'Plan generation failed: $e';
      _phase = JobPhase.failed;
      _addBotMessage(
          'Error: $e', isError: true, action: MessageAction.plan);
    }

    notifyListeners();
  }

  /// Approve the current plan and immediately begin execution.
  ///
  /// This is a single atomic operation so the user doesn't get stuck
  /// in an "approved but not executing" state.
  Future<void> approveAndExecute() async {
    if (_planId.isEmpty) return;
    _errorMessage = '';

    try {
      await _api.postApprove(planId: _planId);
      _phase = JobPhase.approved;
      _addBotMessage('Plan approved. Starting execution...');
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Approval failed: $e';
      _addBotMessage('Error: $e', isError: true);
      _phase = JobPhase.failed;
      notifyListeners();
      return;
    }

    await execute();
  }

  /// Execute the approved plan and poll for progress updates.
  ///
  /// Uses a lightweight polling approach instead of SSE because SSE streams
  /// are unreliable over mobile Wi-Fi.  The live message in chat is updated
  /// every few seconds with the latest event data from the runner.
  Future<void> execute() async {
    if (_planId.isEmpty) return;
    _phase = JobPhase.executing;
    _errorMessage = '';
    _events.clear();
    notifyListeners();

    try {
      final response = await _api.postExecute(planId: _planId);
      _jobId = response.jobId;

      _addBotMessage('Executing... (this may take a few minutes)');
      final liveIdx = _messages.length - 1;
      int lastEventCount = 0;

      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
        try {
          final status = await _api.getJobStatus(_jobId);
          final state = status['state'] as String? ?? '';
          final eventCount = status['event_count'] as int? ?? 0;
          final latestEvent = status['latest_event'] as String? ?? '';

          if (eventCount > lastEventCount && latestEvent.isNotEmpty) {
            lastEventCount = eventCount;
            _events.add(JobEvent(
              eventType: EventType.log,
              data: latestEvent,
            ));
            _messages[liveIdx] = ChatMessage(
              text: 'Executing ($eventCount events)...\n\n$latestEvent',
              isUser: false,
              timestamp: _messages[liveIdx].timestamp,
            );
            notifyListeners();
          }

          if (state == 'complete') {
            timer.cancel();
            _events.add(const JobEvent(
              eventType: EventType.done,
              data: 'Execution complete',
            ));
            _phase = JobPhase.complete;
            _addBotMessage('Execution complete!');
            notifyListeners();
          } else if (state == 'failed') {
            timer.cancel();
            _events.add(JobEvent(
              eventType: EventType.error,
              data: 'Execution failed: $latestEvent',
            ));
            _phase = JobPhase.failed;
            _addBotMessage('Execution failed: $latestEvent');
            notifyListeners();
          }
        } catch (_) {
          // Polling errors are transient -- keep trying
        }
      });
    } catch (e) {
      _errorMessage = 'Execute failed: $e';
      _phase = JobPhase.failed;
      _addBotMessage('Error: $e', isError: true);
      notifyListeners();
    }
  }

  void _addUserMessage(String text) {
    _messages.add(ChatMessage(text: text, isUser: true));
  }

  void _addBotMessage(
    String text, {
    bool isError = false,
    MessageAction action = MessageAction.none,
  }) {
    _messages.add(ChatMessage(
      text: text,
      isUser: false,
      isError: isError,
      action: action,
    ));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
