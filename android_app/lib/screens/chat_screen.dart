import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../providers/job_provider.dart';
import '../providers/project_provider.dart';
import '../theme.dart';
import '../widgets/choice_buttons.dart';
import '../widgets/message_bubble.dart';
import '../widgets/status_ribbon.dart';
import '../widgets/thinking_indicator.dart';
import 'execution_screen.dart';
import 'project_picker_screen.dart';
import 'settings_screen.dart';

/// The two send modes available in the input bar.
enum _SendMode { ask, plan }

/// Main chat screen -- the primary UI surface of the app.
///
/// Displays a message list with user/bot bubbles, a mode-aware input bar, and
/// a [StatusRibbon] that communicates the current workflow phase.  The Ask and
/// Build Plan actions are unified into a single [SegmentedButton] + send flow.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _speechAvailable = false;
  _SendMode _sendMode = _SendMode.ask;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _speech.stop();
    super.dispose();
  }

  void _scrollToBottom() {
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

  String? get _projectPath =>
      context.read<ProjectProvider>().selectedProject?.path;

  Future<void> _handleSend() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    final projectPath = _projectPath;
    if (projectPath == null) {
      _showSnackBar('Select a project first');
      return;
    }

    _inputController.clear();

    switch (_sendMode) {
      case _SendMode.ask:
        await context.read<JobProvider>().ask(projectPath, text);
      case _SendMode.plan:
        await context.read<JobProvider>().buildPlan(projectPath, text);
    }
    _scrollToBottom();
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _toggleListening() async {
    if (!_speechAvailable) {
      _showSnackBar('Speech recognition not available');
      return;
    }

    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
    } else {
      setState(() => _isListening = true);
      await _speech.listen(
        onResult: (result) {
          setState(() {
            _inputController.text = result.recognizedWords;
            _inputController.selection = TextSelection.fromPosition(
              TextPosition(offset: _inputController.text.length),
            );
          });
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        listenOptions: stt.SpeechListenOptions(partialResults: true),
      );
    }
  }

  void _handleChoice(String choiceText) {
    final projectPath = _projectPath;
    if (projectPath == null) {
      _showSnackBar('Select a project first');
      return;
    }
    context.read<JobProvider>().ask(projectPath, choiceText);
    _scrollToBottom();
  }

  void _handleRetry() {
    final projectPath = _projectPath;
    if (projectPath == null) return;
    context.read<JobProvider>().retryLast(projectPath);
    _scrollToBottom();
  }

  void _showPlanBottomSheet() {
    final job = context.read<JobProvider>();
    if (job.planMarkdown.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceContainerDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) {
          return _PlanBottomSheetContent(
            scrollController: scrollController,
            markdown: job.planMarkdown,
            canApprove: job.canApprove,
            onApprove: () async {
              Navigator.of(ctx).pop();
              await job.approveAndExecute();
              _scrollToBottom();
            },
          );
        },
      ),
    );
  }

  void _navigateToExecution() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ExecutionScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final project = context.watch<ProjectProvider>();
    final job = context.watch<JobProvider>();

    final bool isThinking =
        job.phase == JobPhase.asking || job.phase == JobPhase.planning;
    final bool canSend = _sendMode == _SendMode.ask
        ? job.canAsk
        : job.canPlan;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Shikigami'),
            if (project.selectedProject != null)
              Text(
                project.selectedProject!.name,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'New Chat',
            onPressed: () {
              job.reset();
              _inputController.clear();
            },
          ),
          IconButton(
            icon: const Icon(Icons.folder_outlined),
            tooltip: 'Select Project',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const ProjectPickerScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Status ribbon
          StatusRibbon(
            onTapSettings: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            onTapProjectPicker: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const ProjectPickerScreen()),
            ),
            onTapReviewPlan: _showPlanBottomSheet,
            onTapApprove: () async {
              await job.approveAndExecute();
              _scrollToBottom();
            },
            onTapViewExecution: _navigateToExecution,
          ),

          // Message list
          Expanded(
            child: job.messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.chat_bubble_outline,
                              size: 64,
                              color: theme.colorScheme.outline),
                          const SizedBox(height: 16),
                          Text(
                            project.selectedProject != null
                                ? 'Chat about ${project.selectedProject!.name}, or switch to Plan mode to build an execution plan.'
                                : 'Pick a project with the folder icon, or create one in the project picker.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount:
                        job.messages.length + (isThinking ? 1 : 0),
                    padding: const EdgeInsets.only(top: 8, bottom: 8),
                    itemBuilder: (context, index) {
                      // Thinking indicator as the last item
                      if (index == job.messages.length) {
                        return const ThinkingIndicator();
                      }

                      final msg = job.messages[index];
                      final isLastBotMsg = !msg.isUser &&
                          (index == job.messages.length - 1 ||
                              job.messages[index + 1].isUser);
                      final choices =
                          (!msg.isUser && isLastBotMsg && job.canAsk)
                              ? parseChoices(msg.text)
                              : <ParsedChoice>[];

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MessageBubble(
                            text: msg.text,
                            isUser: msg.isUser,
                            timestamp: msg.timestamp,
                            isError: msg.isError,
                            onRetry: msg.isError ? _handleRetry : null,
                          ),
                          if (choices.isNotEmpty)
                            ChoiceButtons(
                              choices: choices,
                              onChoice: _handleChoice,
                            ),
                        ],
                      );
                    },
                  ),
          ),

          // Input area
          _buildInputBar(theme, canSend),
        ],
      ),
    );
  }

  Widget _buildInputBar(ThemeData theme, bool canSend) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Mode selector
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SegmentedButton<_SendMode>(
                segments: const [
                  ButtonSegment(
                    value: _SendMode.ask,
                    label: Text('Ask'),
                    icon: Icon(Icons.question_answer_outlined, size: 18),
                  ),
                  ButtonSegment(
                    value: _SendMode.plan,
                    label: Text('Plan'),
                    icon: Icon(Icons.architecture_outlined, size: 18),
                  ),
                ],
                selected: {_sendMode},
                onSelectionChanged: (selection) {
                  setState(() => _sendMode = selection.first);
                },
                showSelectedIcon: false,
              ),
            ),

            // Text field row
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    maxLines: 4,
                    minLines: 1,
                    textInputAction: TextInputAction.newline,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: _sendMode == _SendMode.ask
                          ? 'Ask a question...'
                          : 'Describe an objective for the plan...',
                    ),
                  ),
                ),
                const SizedBox(width: 4),

                // Mic button
                IconButton(
                  icon: Icon(
                    _isListening ? Icons.mic : Icons.mic_none,
                    color: _isListening
                        ? AppTheme.neonGreen
                        : AppTheme.textMuted,
                  ),
                  tooltip:
                      _isListening ? 'Stop listening' : 'Voice input',
                  onPressed: _toggleListening,
                ),

                // Send button
                IconButton.filled(
                  icon: const Icon(Icons.send),
                  tooltip: _sendMode == _SendMode.ask ? 'Ask' : 'Build Plan',
                  onPressed: canSend ? _handleSend : null,
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.neonGreen,
                    foregroundColor: AppTheme.backgroundDark,
                    disabledBackgroundColor: AppTheme.surfaceContainerDark,
                    disabledForegroundColor: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The content of the plan review bottom sheet.
///
/// Shows the plan Markdown in a scrollable view with an optional approve
/// button at the bottom.
class _PlanBottomSheetContent extends StatelessWidget {
  final ScrollController scrollController;
  final String markdown;
  final bool canApprove;
  final VoidCallback? onApprove;

  const _PlanBottomSheetContent({
    required this.scrollController,
    required this.markdown,
    required this.canApprove,
    this.onApprove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // Drag handle
        Container(
          margin: const EdgeInsets.only(top: 8),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppTheme.textMuted,
            borderRadius: BorderRadius.circular(2),
          ),
        ),

        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.description_outlined,
                  color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Generated Plan',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Markdown body
        Expanded(
          child: Markdown(
            data: markdown,
            controller: scrollController,
            selectable: true,
            padding: const EdgeInsets.all(16),
            styleSheet: MarkdownStyleSheet(
              p: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 14),
              h1: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
              h2: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
              code: const TextStyle(
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

        // Approve button
        if (canApprove)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onApprove,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Approve & Execute'),
              ),
            ),
          ),
      ],
    );
  }
}
