import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/connection_provider.dart';
import '../theme.dart';

/// Settings screen for configuring the runner connection URL.
///
/// When [isOnboarding] is true the screen is displayed as the initial setup
/// flow -- there is no back button and the UI prompts the user to connect
/// before they can proceed.
class SettingsScreen extends StatefulWidget {
  /// Whether the screen is shown as part of the guided onboarding flow.
  final bool isOnboarding;

  const SettingsScreen({super.key, this.isOnboarding = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _urlController;

  @override
  void initState() {
    super.initState();
    final current = context.read<ConnectionProvider>().baseUrl;
    _urlController = TextEditingController(text: current);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connection = context.watch<ConnectionProvider>();

    return Scaffold(
      appBar: widget.isOnboarding
          ? null
          : AppBar(title: const Text('Settings'), centerTitle: true),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (widget.isOnboarding) ...[
              const SizedBox(height: 48),
              Icon(Icons.cable_outlined,
                  size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                'Connect to Runner',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Enter the local network address of your desktop runner to get started.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
            ] else ...[
              Text('Runner Connection',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
            ],

            // URL field
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: 'Runner URL',
                hintText: 'http://192.168.1.100:8422',
                prefixIcon: const Icon(Icons.link),
                border: const OutlineInputBorder(),
                helperText:
                    'The local network address of your desktop runner',
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 16),

            // Save & Test button
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      await connection
                          .setBaseUrl(_urlController.text.trim());
                    },
                    icon: const Icon(Icons.sync),
                    label: Text(
                        widget.isOnboarding ? 'Connect' : 'Save & Test'),
                  ),
                ),
                const SizedBox(width: 12),
                if (connection.isChecking)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 24),

            // Status card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          connection.isConnected
                              ? Icons.check_circle
                              : Icons.cancel,
                          color: connection.isConnected
                              ? Colors.green
                              : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          connection.isConnected
                              ? 'Connected'
                              : 'Disconnected',
                          style: theme.textTheme.titleSmall,
                        ),
                      ],
                    ),
                    if (connection.cursorVersion.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('Cursor CLI: ${connection.cursorVersion}',
                          style: theme.textTheme.bodySmall),
                    ],
                    if (connection.errorMessage.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        connection.errorMessage,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.error),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
