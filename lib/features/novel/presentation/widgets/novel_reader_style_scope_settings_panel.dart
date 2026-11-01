import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../domain/models/novel_reader_typography_overrides.dart';

typedef NovelReaderStyleScopeLabels = ({
  String title,
  String original,
  String author,
  String body,
  String all,
  String hint,
  String allHint,
  String unavailable,
  String reset,
});

enum _ScopeChoice { original, author, body, all }

/// Policy-only presentation. Typed wrappers bind each policy to its single
/// persisted value; this widget has no storage or body-layout responsibilities.
class NovelReaderStyleScopeSettingsPanel extends StatelessWidget {
  const NovelReaderStyleScopeSettingsPanel({
    super.key,
    required this.keyPrefix,
    required this.value,
    required this.enabled,
    required this.labels,
    required this.onChanged,
  });
  final String keyPrefix;
  final NovelReaderStyleScope? value;
  final bool enabled;
  final NovelReaderStyleScopeLabels labels;
  final ValueChanged<NovelReaderStyleScope?> onChanged;

  @override
  Widget build(BuildContext context) {
    final choice = switch (value) {
      null => _ScopeChoice.original,
      NovelReaderStyleScope.asDefault => _ScopeChoice.author,
      NovelReaderStyleScope.forceBody => _ScopeChoice.body,
      NovelReaderStyleScope.forceAll => _ScopeChoice.all,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReaderSegmentControl<_ScopeChoice>(
          key: Key('$keyPrefix-policy'),
          label: labels.title,
          value: choice,
          values: _ScopeChoice.values,
          enabled: enabled,
          labelBuilder: (option) => switch (option) {
            _ScopeChoice.original => labels.original,
            _ScopeChoice.author => labels.author,
            _ScopeChoice.body => labels.body,
            _ScopeChoice.all => labels.all,
          },
          onChanged: (next) => onChanged(switch (next) {
            _ScopeChoice.original => null,
            _ScopeChoice.author => NovelReaderStyleScope.asDefault,
            _ScopeChoice.body => NovelReaderStyleScope.forceBody,
            _ScopeChoice.all => NovelReaderStyleScope.forceAll,
          }),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Text(
            !enabled
                ? labels.unavailable
                : value == NovelReaderStyleScope.forceAll
                ? labels.allHint
                : labels.hint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: Tooltip(
              message: labels.reset,
              child: TextButton(
                key: Key('$keyPrefix-reset'),
                onPressed: value == null ? null : () => onChanged(null),
                child: Text(AppLocalizations.of(context).commonReset),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
