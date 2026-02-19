import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../models/ask_models.dart';
import '../models/health_response.dart';
import '../models/job_event.dart';
import '../models/plan_models.dart';
import '../models/project_info.dart';

/// HTTP + SSE client for the Cursor Runner desktop service.
///
/// All methods throw [RunnerApiException] on non-2xx responses.
/// When running as a web app, the base URL defaults to the current origin
/// so the app can be served directly from the runner with no configuration.
class RunnerApi {
  String _baseUrl;

  RunnerApi({String baseUrl = 'http://localhost:8423'})
      : _baseUrl = kIsWeb ? Uri.base.origin : baseUrl;

  /// Update the base URL (e.g. when the user changes connection settings).
  void setBaseUrl(String url) {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  String get baseUrl => _baseUrl;

  // -----------------------------------------------------------------------
  // Health
  // -----------------------------------------------------------------------

  /// Check runner health and Cursor CLI availability.
  Future<HealthResponse> getHealth() async {
    final response = await http.get(Uri.parse('$_baseUrl/health'));
    _assertOk(response);
    return HealthResponse.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  // -----------------------------------------------------------------------
  // Projects
  // -----------------------------------------------------------------------

  /// List candidate project folders under the runner's configured root.
  Future<List<ProjectInfo>> getProjects({int days = 10}) async {
    final response =
        await http.get(Uri.parse('$_baseUrl/projects?days=$days'));
    _assertOk(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final list = body['projects'] as List<dynamic>;
    return list
        .map((e) => ProjectInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // -----------------------------------------------------------------------
  // Ask
  // -----------------------------------------------------------------------

  /// Send a read-only question to the Cursor agent.
  Future<AskResponse> postAsk({
    required String projectPath,
    required String message,
    int recentDays = 10,
    List<Map<String, String>> history = const [],
    String sessionId = '',
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/ask'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'project_path': projectPath,
        'message': message,
        'context': {'recent_days': recentDays},
        'history': history,
        'session_id': sessionId,
      }),
    );
    _assertOk(response);
    return AskResponse.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  // -----------------------------------------------------------------------
  // Plan
  // -----------------------------------------------------------------------

  /// Generate a Markdown plan via the Cursor agent.
  Future<PlanResponse> postPlan({
    required String projectPath,
    required String objective,
    List<String> constraints = const [],
    Map<String, String> answers = const {},
    List<Map<String, String>> history = const [],
    String sessionId = '',
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/plan'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'project_path': projectPath,
        'objective': objective,
        'constraints': constraints,
        'answers': answers,
        'history': history,
        'session_id': sessionId,
      }),
    );
    _assertOk(response);
    return PlanResponse.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Create a new project folder on the runner.
  Future<Map<String, dynamic>> postCreateProject({
    required String name,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/projects'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name}),
    );
    _assertOk(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // -----------------------------------------------------------------------
  // Approve
  // -----------------------------------------------------------------------

  /// Approve a plan so execution can begin.
  Future<ApproveResponse> postApprove({required String planId}) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/approve'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'plan_id': planId}),
    );
    _assertOk(response);
    return ApproveResponse.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  // -----------------------------------------------------------------------
  // Execute
  // -----------------------------------------------------------------------

  /// Start executing an approved plan.
  Future<ExecuteResponse> postExecute({required String planId}) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/execute'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'plan_id': planId}),
    );
    _assertOk(response);
    return ExecuteResponse.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  // -----------------------------------------------------------------------
  // Job Status (polling)
  // -----------------------------------------------------------------------

  /// Poll the current status of a job (lightweight alternative to SSE).
  Future<Map<String, dynamic>> getJobStatus(String jobId) async {
    final response =
        await http.get(Uri.parse('$_baseUrl/job-status?job_id=$jobId'));
    _assertOk(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // -----------------------------------------------------------------------
  // SSE Events
  // -----------------------------------------------------------------------

  /// Open an SSE stream for the given job and yield [JobEvent]s.
  ///
  /// The stream ends automatically when a terminal event (done/error) arrives.
  Stream<JobEvent> streamEvents(String jobId) async* {
    final request =
        http.Request('GET', Uri.parse('$_baseUrl/events?job_id=$jobId'));
    final client = http.Client();

    try {
      final streamedResponse = await client.send(request);

      String buffer = '';
      String currentEvent = 'log';
      String currentData = '';

      await for (final chunk
          in streamedResponse.stream.transform(utf8.decoder)) {
        buffer += chunk;

        // SSE protocol: events separated by double newlines
        while (buffer.contains('\n\n')) {
          final idx = buffer.indexOf('\n\n');
          final block = buffer.substring(0, idx);
          buffer = buffer.substring(idx + 2);

          // Parse SSE fields from the block
          currentEvent = 'log';
          currentData = '';
          for (final line in block.split('\n')) {
            if (line.startsWith('event:')) {
              currentEvent = line.substring(6).trim();
            } else if (line.startsWith('data:')) {
              currentData = line.substring(5).trim();
            }
          }

          final event = JobEvent.fromSse(currentEvent, currentData);
          yield event;

          if (event.isTerminal) {
            return;
          }
        }
      }
    } finally {
      client.close();
    }
  }

  // -----------------------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------------------

  void _assertOk(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RunnerApiException(
        statusCode: response.statusCode,
        message: response.body,
      );
    }
  }
}

/// Exception thrown when the runner API returns a non-2xx status.
class RunnerApiException implements Exception {
  final int statusCode;
  final String message;

  const RunnerApiException({required this.statusCode, required this.message});

  @override
  String toString() => 'RunnerApiException($statusCode): $message';
}
