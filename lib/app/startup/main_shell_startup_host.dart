import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/library_shared/data/providers/library_task_workflow_providers.dart';
import 'package:y300/features/library_shared/presentation/services/library_task_text_resolver.dart';
import 'package:y300/features/profile/presentation/account_display_controller.dart';
import 'package:y300/l10n/app_localizations.dart';

/// Keeps account display synchronization alive while library readiness waits.
class MainShellStartupHost extends ConsumerWidget {
  const MainShellStartupHost({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(accountDisplayControllerProvider);
    return child;
  }
}

/// Assembles task presentation only after the custom-cover readiness barrier.
class MainShellReadyTaskHost extends ConsumerWidget {
  const MainShellReadyTaskHost({
    required this.child,
    this.isReady = true,
    super.key,
  });

  final Widget child;
  final bool isReady;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep the foreground subtree mounted while only library task assembly
    // waits for cover recovery. Forum startup does not consume cover assets.
    if (!isReady) return child;
    final l10n = AppLocalizations.of(context);
    ref.watch(favoriteSyncTaskProgressRegistrationProvider);
    ref.watch(comicSearchQueueTaskProgressRegistrationProvider);
    ref
        .watch(libraryTaskNotificationBridgeProvider)
        .start(
          localeId: l10n.localeName,
          textResolver: (progress) =>
              LibraryTaskTextResolver.notification(l10n, progress),
        );
    // ProviderContainer retains process-wide bridge/service ownership. Rebuilds
    // update localization through the bridge's existing idempotent start.
    return child;
  }
}
