import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/project_provider.dart';
import '../theme.dart';

/// Screen for selecting or creating a project folder.
///
/// Displays existing projects sorted by most recently modified.
/// A floating action button lets the user create a new project.
///
/// When [isOnboarding] is true the screen is shown as part of the guided
/// first-launch flow -- there is no back arrow and the header prompts the
/// user to pick a project before proceeding.
class ProjectPickerScreen extends StatefulWidget {
  /// Whether the screen is shown as part of the guided onboarding flow.
  final bool isOnboarding;

  const ProjectPickerScreen({super.key, this.isOnboarding = false});

  @override
  State<ProjectPickerScreen> createState() => _ProjectPickerScreenState();
}

class _ProjectPickerScreenState extends State<ProjectPickerScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProjectProvider>().loadProjects();
    });
  }

  Future<void> _showCreateDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Project'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Project name',
          ),
          onSubmitted: (val) => Navigator.of(ctx).pop(val.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty || !mounted) return;

    try {
      final api = context.read<ProjectProvider>().api;
      await api.postCreateProject(name: name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Created "$name"')),
        );
        await context.read<ProjectProvider>().loadProjects();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: widget.isOnboarding
          ? null
          : AppBar(title: const Text('Select Project'), centerTitle: true),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('New Project'),
      ),
      body: SafeArea(
        child: Consumer<ProjectProvider>(
          builder: (context, provider, _) {
            if (provider.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (provider.errorMessage.isNotEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline,
                          size: 48, color: theme.colorScheme.error),
                      const SizedBox(height: 16),
                      Text(provider.errorMessage,
                          textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => provider.loadProjects(),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final showHeader = widget.isOnboarding;
            final itemOffset = showHeader ? 1 : 0;
            final totalCount = provider.projects.length + itemOffset;

            if (provider.projects.isEmpty) {
              return _buildEmptyState(theme);
            }

            return RefreshIndicator(
              onRefresh: () => provider.loadProjects(),
              child: ListView.builder(
                itemCount: totalCount,
                padding: const EdgeInsets.only(top: 8, bottom: 80),
                itemBuilder: (context, index) {
                  if (showHeader && index == 0) {
                    return _buildOnboardingHeader(theme);
                  }

                  final project =
                      provider.projects[index - itemOffset];
                  final isSelected =
                      provider.selectedProject?.path == project.path;

                  return ListTile(
                    leading: Icon(
                      Icons.folder_outlined,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline,
                    ),
                    title: Text(
                      project.name,
                      style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                      '${project.fileCount} files  •  ${_formatDate(project.lastModified)}',
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check_circle,
                            color: theme.colorScheme.primary)
                        : null,
                    onTap: () {
                      provider.selectProject(project);
                      if (!widget.isOnboarding) {
                        Navigator.of(context).pop();
                      }
                    },
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildOnboardingHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 16),
      child: Column(
        children: [
          Icon(Icons.folder_open_outlined,
              size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'Choose a Project',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Select a project folder to start chatting and building plans.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppTheme.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.isOnboarding) ...[
              Icon(Icons.folder_open_outlined,
                  size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                'Choose a Project',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Icon(Icons.folder_off_outlined,
                size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            const Text(
              'No projects found.\n'
              'Tap "New Project" below to create one.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${date.month}/${date.day}/${date.year}';
  }
}
