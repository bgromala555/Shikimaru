import 'ask_models.dart';

/// Response from POST /plan.
class PlanResponse {
  final String jobId;
  final String planId;
  final String planMarkdown;
  final String sessionId;
  final List<ClarificationQuestion> questions;

  const PlanResponse({
    required this.jobId,
    required this.planId,
    required this.planMarkdown,
    this.sessionId = '',
    this.questions = const [],
  });

  factory PlanResponse.fromJson(Map<String, dynamic> json) {
    return PlanResponse(
      jobId: json['job_id'] as String,
      planId: json['plan_id'] as String,
      planMarkdown: json['plan_markdown'] as String,
      sessionId: json['session_id'] as String? ?? '',
      questions: (json['questions'] as List<dynamic>?)
              ?.map(
                  (e) => ClarificationQuestion.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// Response from POST /approve.
class ApproveResponse {
  final String jobId;
  final String status;

  const ApproveResponse({required this.jobId, required this.status});

  factory ApproveResponse.fromJson(Map<String, dynamic> json) {
    return ApproveResponse(
      jobId: json['job_id'] as String,
      status: json['status'] as String,
    );
  }
}

/// Response from POST /execute.
class ExecuteResponse {
  final String jobId;

  const ExecuteResponse({required this.jobId});

  factory ExecuteResponse.fromJson(Map<String, dynamic> json) {
    return ExecuteResponse(jobId: json['job_id'] as String);
  }
}
