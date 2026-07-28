import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/app_update/data/providers/app_update_providers.dart';
import 'package:y300/features/app_update/domain/models/app_update_check_result.dart';
import 'package:y300/features/app_update/presentation/app_update_feedback_messages.dart';
import 'package:y300/features/app_update/presentation/controllers/app_update_prompt_coordinator.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/transient_feedback.dart';

class AppUpdateCheckTile extends ConsumerStatefulWidget {
  const AppUpdateCheckTile({super.key, this.showVersionSubtitle = true});

  final bool showVersionSubtitle;

  @override
  ConsumerState<AppUpdateCheckTile> createState() => _AppUpdateCheckTileState();
}

class _AppUpdateCheckTileState extends ConsumerState<AppUpdateCheckTile> {
  bool _checking = false;

  @override
  Widget build(BuildContext context) {
    final coordinator = ref.watch(appUpdatePromptCoordinatorProvider);
    final l10n = AppLocalizations.of(context);
    return StreamBuilder<String?>(
      initialData: coordinator.installedVersion,
      stream: coordinator.installedVersionStream,
      builder: (context, snapshot) {
        final version = snapshot.data?.trim();
        return ListTile(
          key: const Key('about-check-update-entry'),
          leading: const Icon(Icons.system_update_alt_outlined),
          title: Text(l10n.appUpdateCheck),
          subtitle: widget.showVersionSubtitle
              ? Text(
                  version == null || version.isEmpty
                      ? l10n.appUpdateVersionLoading
                      : l10n.appUpdateCurrentVersion(version),
                )
              : null,
          trailing: _checking
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          enabled: !_checking,
          onTap: _checking ? null : () => _checkNow(coordinator),
        );
      },
    );
  }

  Future<void> _checkNow(AppUpdatePromptCoordinator coordinator) async {
    setState(() => _checking = true);
    final result = await coordinator.checkNow();
    if (!mounted) {
      return;
    }
    setState(() => _checking = false);

    switch (result) {
      case AppUpdateCheckFailure(:final failure):
        showTransientSnackBar(
          context,
          appUpdateCheckFailureMessage(
            AppLocalizations.of(context),
            failure.code,
          ),
        );
      case AppUpdateCheckUpToDate():
        showTransientSnackBar(
          context,
          AppLocalizations.of(context).appUpdateUpToDate,
        );
      case AppUpdateCheckAvailable():
        coordinator.requestPrompt();
        return;
    }
  }
}
