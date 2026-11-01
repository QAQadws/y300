import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../domain/models/novel_reader_typography_overrides.dart';

enum _IndentChoice { author, missing, body, all }

class NovelReaderIndentSettingsPanel extends StatelessWidget {
  const NovelReaderIndentSettingsPanel({
    super.key,
    required this.value,
    required this.onChanged,
    required this.enabled,
  });
  final NovelReaderTypographyOverrides value;
  final ValueChanged<NovelReaderTypographyOverrides> onChanged;
  final bool enabled;

  _IndentChoice get _choice {
    final request = value.firstLineIndent;
    if (request == null ||
        !request.isValid ||
        (request.scope == NovelReaderStyleScope.asDefault && request.em == 0)) {
      return _IndentChoice.author;
    }
    return switch (request.scope) {
      NovelReaderStyleScope.asDefault => _IndentChoice.missing,
      NovelReaderStyleScope.forceBody => _IndentChoice.body,
      NovelReaderStyleScope.forceAll => _IndentChoice.all,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final choice = _choice;
    final request = value.firstLineIndent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReaderSegmentControl<_IndentChoice>(
          key: const Key('novel-reader-indent-policy'),
          label: l10n.novelIndentScope,
          value: choice,
          values: _IndentChoice.values,
          enabled: enabled,
          labelBuilder: (option) => switch (option) {
            _IndentChoice.author => l10n.novelIndentAuthor,
            _IndentChoice.missing => l10n.novelIndentMissing,
            _IndentChoice.body => l10n.novelIndentBody,
            _IndentChoice.all => l10n.novelIndentAll,
          },
          onChanged: (next) {
            final amount = choice == _IndentChoice.author
                ? NovelReaderFirstLineIndent.initialEm
                : request!.em;
            final result = next == _IndentChoice.author
                ? const NovelReaderFirstLineIndent.followAuthor()
                : NovelReaderFirstLineIndent(
                    em: amount,
                    scope: switch (next) {
                      _IndentChoice.missing => NovelReaderStyleScope.asDefault,
                      _IndentChoice.body => NovelReaderStyleScope.forceBody,
                      _IndentChoice.all => NovelReaderStyleScope.forceAll,
                      _IndentChoice.author => throw StateError(
                        'Unreachable indent choice',
                      ),
                    },
                  );
            onChanged(value.withFirstLineIndent(result));
          },
        ),
        if (choice != _IndentChoice.author) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Row(
              children: [
                Expanded(child: Text(l10n.novelIndentAmount)),
                Text(l10n.novelIndentEmValue(request!.em.toStringAsFixed(2))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Slider(
              key: const Key('novel-reader-indent-slider'),
              value: request.em,
              min: NovelReaderFirstLineIndent.minimumEm,
              max: NovelReaderFirstLineIndent.maximumEm,
              divisions:
                  ((NovelReaderFirstLineIndent.maximumEm -
                              NovelReaderFirstLineIndent.minimumEm) /
                          NovelReaderFirstLineIndent.stepEm)
                      .round(),
              onChanged: enabled
                  ? (amount) => onChanged(
                      value.withFirstLineIndent(
                        NovelReaderFirstLineIndent(
                          em:
                              (amount / NovelReaderFirstLineIndent.stepEm)
                                  .round() *
                              NovelReaderFirstLineIndent.stepEm,
                          scope: request.scope,
                        ),
                      ),
                    )
                  : null,
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Text(
            enabled
                ? l10n.novelIndentAdaptiveHint
                : l10n.novelIndentUnavailableMode,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: Tooltip(
              message: l10n.novelIndentReset,
              child: TextButton(
                key: const Key('novel-reader-indent-reset'),
                onPressed: value.firstLineIndent == null
                    ? null
                    : () => onChanged(value.withFirstLineIndent(null)),
                child: Text(l10n.commonReset),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
