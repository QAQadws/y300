import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:version/version.dart';
import 'package:y300/features/app_update/data/providers/app_update_providers.dart';
import 'package:y300/features/app_update/domain/models/app_release_notes_load_result.dart';
import 'package:y300/l10n/app_localizations.dart';

class AppReleaseNotesPage extends ConsumerStatefulWidget {
  const AppReleaseNotesPage({super.key, required this.installedVersion});

  final Version installedVersion;

  @override
  ConsumerState<AppReleaseNotesPage> createState() =>
      _AppReleaseNotesPageState();
}

class _AppReleaseNotesPageState extends ConsumerState<AppReleaseNotesPage> {
  AppReleaseNotesLoadResult? _result;
  bool _isLoading = true;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).moreAboutReleaseNotes),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _buildBody(context),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: SizedBox.square(
          key: Key('app-release-notes-loading'),
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }

    return switch (_result) {
      AppReleaseNotesAvailable(:final notes) =>
        notes.body.trim().isEmpty
            ? _buildEmptyState(context)
            : ListView(
                key: const Key('app-release-notes-content'),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                children: [
                  Text(
                    'Y300 ${notes.tag}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  SelectableText(
                    notes.body,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(height: 1.55),
                  ),
                ],
              ),
      AppReleaseNotesUnavailable() => _buildFailureState(context),
      _ => _buildFailureState(context),
    };
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          AppLocalizations.of(context).appUpdateReleaseNotesEmpty,
          key: const Key('app-release-notes-empty'),
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildFailureState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 36,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              AppLocalizations.of(context).appUpdateReleaseNotesUnavailable,
              key: const Key('app-release-notes-failure'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('app-release-notes-retry'),
              onPressed: _isLoading ? null : () => _load(forceRefresh: true),
              icon: const Icon(Icons.refresh),
              label: Text(AppLocalizations.of(context).commonRetry),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _load({bool forceRefresh = false}) async {
    final generation = ++_requestGeneration;
    if (mounted && !_isLoading) {
      setState(() {
        _isLoading = true;
      });
    }
    final result = await ref
        .read(appReleaseNotesServiceProvider)
        .loadCurrent(widget.installedVersion, forceRefresh: forceRefresh);
    if (!mounted || generation != _requestGeneration) {
      return;
    }
    setState(() {
      _result = result;
      _isLoading = false;
    });
  }
}
