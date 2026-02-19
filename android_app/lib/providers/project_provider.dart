import 'package:flutter/foundation.dart';

import '../models/project_info.dart';
import '../services/runner_api.dart';

/// Manages the list of available projects and the currently selected project.
class ProjectProvider extends ChangeNotifier {
  final RunnerApi _api;

  List<ProjectInfo> _projects = [];
  ProjectInfo? _selectedProject;
  bool _isLoading = false;
  String _errorMessage = '';

  ProjectProvider(this._api);

  RunnerApi get api => _api;
  List<ProjectInfo> get projects => _projects;
  ProjectInfo? get selectedProject => _selectedProject;
  bool get isLoading => _isLoading;
  String get errorMessage => _errorMessage;

  /// Fetch the project list from the runner.
  Future<void> loadProjects({int days = 10}) async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      _projects = await _api.getProjects(days: days);
    } catch (e) {
      _errorMessage = 'Failed to load projects: $e';
      _projects = [];
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Select a project to work with.
  void selectProject(ProjectInfo project) {
    _selectedProject = project;
    notifyListeners();
  }

  /// Clear the current selection.
  void clearSelection() {
    _selectedProject = null;
    notifyListeners();
  }
}
