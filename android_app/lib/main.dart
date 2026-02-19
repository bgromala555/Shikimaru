import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/connection_provider.dart';
import 'providers/job_provider.dart';
import 'providers/project_provider.dart';
import 'screens/chat_screen.dart';
import 'screens/project_picker_screen.dart';
import 'screens/settings_screen.dart';
import 'services/runner_api.dart';
import 'theme.dart';

void main() {
  runApp(const ShikigamiApp());
}

/// Root widget for the Shikigami Android app.
///
/// Sets up Provider state management with a shared [RunnerApi] instance
/// and the three core providers: connection, project, and job.
class ShikigamiApp extends StatelessWidget {
  const ShikigamiApp({super.key});

  @override
  Widget build(BuildContext context) {
    final api = RunnerApi();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConnectionProvider(api)),
        ChangeNotifierProvider(create: (_) => ProjectProvider(api)),
        ChangeNotifierProvider(create: (_) => JobProvider(api)),
      ],
      child: MaterialApp(
        title: 'Shikigami',
        debugShowCheckedModeBanner: false,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        home: const _AppShell(),
      ),
    );
  }
}

/// Shell widget that checks runner connectivity on first launch and routes
/// the user through the onboarding flow: connection --> project --> chat.
class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ConnectionProvider>().checkConnection();
    });
  }

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionProvider>();
    final project = context.watch<ProjectProvider>();

    if (!connection.isConnected && !connection.isChecking) {
      return const SettingsScreen(isOnboarding: true);
    }

    if (connection.isConnected && project.selectedProject == null) {
      return const ProjectPickerScreen(isOnboarding: true);
    }

    return const ChatScreen();
  }
}
