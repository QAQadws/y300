import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/navigation/main_navigation_settings.dart';
import 'package:y300/app/navigation/main_navigation_settings_controller.dart';
import 'package:y300/app/navigation/main_shell_destination_presentation.dart';
import 'package:y300/features/more/presentation/more_text_resolver.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/transient_feedback.dart';

class NavigationManagementPage extends ConsumerWidget {
  const NavigationManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(mainNavigationSettingsControllerProvider);
    final currentState = asyncState.value;
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(
      mainNavigationSettingsControllerProvider.notifier,
    );
    return Scaffold(
      key: const Key('navigation-management-page'),
      appBar: AppBar(
        title: Text(l10n.moreNavigationManagement),
        actions: [
          IconButton(
            key: const Key('navigation-management-reset'),
            tooltip: l10n.moreNavigationRestoreDefault,
            onPressed: currentState == null || currentState.isSaving
                ? null
                : () => unawaited(
                    _runMutation(context, controller.resetToDefaults),
                  ),
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
      body: asyncState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: FilledButton.icon(
            key: const Key('navigation-management-load-retry'),
            onPressed: () =>
                ref.invalidate(mainNavigationSettingsControllerProvider),
            icon: const Icon(Icons.refresh),
            label: Text(l10n.moreNavigationRetry),
          ),
        ),
        data: (state) {
          final order = state.settings.managedOrder;
          return Stack(
            children: [
              ReorderableListView.builder(
                key: const Key('navigation-management-list'),
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: order.length,
                onReorderItem: state.isSaving
                    ? (_, _) {}
                    : (oldIndex, newIndex) => unawaited(
                        _runMutation(
                          context,
                          () => controller.reorder(oldIndex, newIndex),
                        ),
                      ),
                itemBuilder: (context, index) {
                  final destination = order[index];
                  final visible = state.settings.isVisible(destination);
                  return Column(
                    key: ValueKey<String>(
                      'navigation-management-item-${destination.name}',
                    ),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: Icon(destination.icon),
                        title: Text(
                          MoreTextResolver.navigationLabel(l10n, destination),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              key: ValueKey<String>(
                                'navigation-management-visible-${destination.name}',
                              ),
                              value: visible,
                              onChanged: state.isSaving
                                  ? null
                                  : (nextVisible) => unawaited(
                                      _runMutation(
                                        context,
                                        () => controller.setVisibility(
                                          destination,
                                          nextVisible,
                                        ),
                                      ),
                                    ),
                            ),
                            Tooltip(
                              message: l10n.moreNavigationDragToReorder,
                              child: ReorderableDragStartListener(
                                index: index,
                                enabled: !state.isSaving,
                                child: const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Icon(Icons.drag_handle),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (index != order.length - 1)
                        const Divider(height: 1, indent: 56),
                    ],
                  );
                },
              ),
              if (state.isSaving)
                const Align(
                  alignment: Alignment.topCenter,
                  child: LinearProgressIndicator(
                    key: Key('navigation-management-saving'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _runMutation(
    BuildContext context,
    Future<void> Function() mutation,
  ) async {
    try {
      await mutation();
    } on MainNavigationMinimumVisibleException {
      if (context.mounted) {
        showTransientSnackBar(
          context,
          AppLocalizations.of(context).moreNavigationMinimumOneRequired,
        );
      }
    } on MainNavigationMutationInProgressException {
      // Controls are disabled while saving; ignore a callback already queued
      // by the previous frame.
    } catch (_) {
      if (context.mounted) {
        showTransientSnackBar(
          context,
          AppLocalizations.of(context).moreNavigationSaveFailed,
        );
      }
    }
  }
}
