/// Response from GET /health.
class HealthResponse {
  final String status;
  final bool cursorCliAvailable;
  final String cursorCliVersion;

  const HealthResponse({
    required this.status,
    required this.cursorCliAvailable,
    this.cursorCliVersion = '',
  });

  factory HealthResponse.fromJson(Map<String, dynamic> json) {
    return HealthResponse(
      status: json['status'] as String,
      cursorCliAvailable: json['cursor_cli_available'] as bool,
      cursorCliVersion: (json['cursor_cli_version'] as String?) ?? '',
    );
  }

  bool get isHealthy => status == 'ok';
}
