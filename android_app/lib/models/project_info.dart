/// Metadata for a single project folder discovered by the runner.
class ProjectInfo {
  final String name;
  final String path;
  final DateTime lastModified;
  final int fileCount;

  const ProjectInfo({
    required this.name,
    required this.path,
    required this.lastModified,
    required this.fileCount,
  });

  factory ProjectInfo.fromJson(Map<String, dynamic> json) {
    return ProjectInfo(
      name: json['name'] as String,
      path: json['path'] as String,
      lastModified: DateTime.parse(json['last_modified'] as String),
      fileCount: json['file_count'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'last_modified': lastModified.toIso8601String(),
        'file_count': fileCount,
      };
}
