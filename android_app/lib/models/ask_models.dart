/// A single selectable option inside a clarification question.
class QuestionOption {
  final String label;
  final String text;

  const QuestionOption({required this.label, required this.text});

  factory QuestionOption.fromJson(Map<String, dynamic> json) {
    return QuestionOption(
      label: json['label'] as String,
      text: json['text'] as String,
    );
  }
}

/// A follow-up question from Cursor during Ask or Plan phases.
class ClarificationQuestion {
  final String questionId;
  final String text;
  final List<QuestionOption> options;

  const ClarificationQuestion({
    required this.questionId,
    required this.text,
    this.options = const [],
  });

  factory ClarificationQuestion.fromJson(Map<String, dynamic> json) {
    return ClarificationQuestion(
      questionId: json['question_id'] as String,
      text: json['text'] as String,
      options: (json['options'] as List<dynamic>?)
              ?.map((e) => QuestionOption.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// Response from POST /ask.
class AskResponse {
  final String jobId;
  final String askText;
  final String sessionId;
  final List<ClarificationQuestion> questions;

  const AskResponse({
    required this.jobId,
    required this.askText,
    this.sessionId = '',
    this.questions = const [],
  });

  factory AskResponse.fromJson(Map<String, dynamic> json) {
    return AskResponse(
      jobId: json['job_id'] as String,
      askText: json['ask_text'] as String,
      sessionId: json['session_id'] as String? ?? '',
      questions: (json['questions'] as List<dynamic>?)
              ?.map(
                  (e) => ClarificationQuestion.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
