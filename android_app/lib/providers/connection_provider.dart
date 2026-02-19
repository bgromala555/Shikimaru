import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/runner_api.dart';

/// Manages the connection state between the Android app and the desktop runner.
///
/// Tracks whether the runner is reachable, what Cursor CLI version it reports,
/// and allows the user to change the runner URL from settings.
///
/// The runner URL is persisted to local storage so it survives app restarts.
/// A periodic health check runs every [_healthIntervalSeconds] seconds so that
/// connection drops and recoveries are detected automatically.
class ConnectionProvider extends ChangeNotifier {
  final RunnerApi _api;

  bool _isConnected = false;
  bool _isChecking = false;
  String _cursorVersion = '';
  String _errorMessage = '';
  Timer? _healthTimer;
  bool _hasLoadedSavedUrl = false;

  static const int _healthIntervalSeconds = 30;
  static const String _urlStorageKey = 'runner_base_url';

  ConnectionProvider(this._api);

  bool get isConnected => _isConnected;
  bool get isChecking => _isChecking;
  String get cursorVersion => _cursorVersion;
  String get errorMessage => _errorMessage;
  String get baseUrl => _api.baseUrl;
  bool get hasLoadedSavedUrl => _hasLoadedSavedUrl;

  /// Load the previously saved runner URL from local storage, then check
  /// connectivity. Call this once at app startup before [checkConnection].
  Future<void> loadSavedUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString(_urlStorageKey);
    if (savedUrl != null && savedUrl.isNotEmpty) {
      _api.setBaseUrl(savedUrl);
    }
    _hasLoadedSavedUrl = true;
    notifyListeners();
  }

  /// Update the runner URL, persist it to local storage, and re-check
  /// connectivity.
  Future<void> setBaseUrl(String url) async {
    _api.setBaseUrl(url);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_urlStorageKey, _api.baseUrl);
    await checkConnection();
  }

  /// Ping the runner's /health endpoint to verify connectivity.
  ///
  /// Also starts the periodic health check timer if it is not yet running.
  Future<void> checkConnection() async {
    _isChecking = true;
    _errorMessage = '';
    notifyListeners();

    try {
      final health = await _api.getHealth();
      _isConnected = health.isHealthy;
      _cursorVersion = health.cursorCliVersion;
      _errorMessage = health.isHealthy ? '' : 'Runner is degraded';
    } catch (e) {
      _isConnected = false;
      _cursorVersion = '';
      _errorMessage = 'Cannot reach runner: $e';
    }

    _isChecking = false;
    notifyListeners();

    _ensureHealthTimer();
  }

  /// Start the background health-check timer if it isn't already running.
  void _ensureHealthTimer() {
    if (_healthTimer != null && _healthTimer!.isActive) return;

    _healthTimer = Timer.periodic(
      const Duration(seconds: _healthIntervalSeconds),
      (_) => _silentHealthCheck(),
    );
  }

  /// Background health check that does not set [_isChecking] so it doesn't
  /// show a loading indicator on the UI.
  Future<void> _silentHealthCheck() async {
    try {
      final health = await _api.getHealth();
      final wasConnected = _isConnected;
      _isConnected = health.isHealthy;
      _cursorVersion = health.cursorCliVersion;
      _errorMessage = health.isHealthy ? '' : 'Runner is degraded';

      if (_isConnected != wasConnected) {
        notifyListeners();
      }
    } catch (_) {
      if (_isConnected) {
        _isConnected = false;
        _errorMessage = 'Connection lost';
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _healthTimer?.cancel();
    super.dispose();
  }
}
