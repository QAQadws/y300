import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../domain/models/novel_reader_typography_overrides.dart';

enum _LetterChoice { original, missing, body, all }

class NovelReaderLetterSpacingSettingsPanel extends StatelessWidget {
  const NovelReaderLetterSpacingSettingsPanel({
    super.key,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });
  final NovelReaderTypographyOverrides value;
  final bool enabled;
  final ValueChanged<NovelReaderTypographyOverrides> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final stored = value.letterSpacing;
    final request = stored?.isValid == true ? stored : null;
    final choice = request == null
        ? _LetterChoice.original
        : switch (request.scope) {
            NovelReaderStyleScope.asDefault => _LetterChoice.missing,
            NovelReaderStyleScope.forceBody => _LetterChoice.body,
            NovelReaderStyleScope.forceAll => _LetterChoice.all,
          };
    String amount(double value) => l10n.novelLetterSpacingValue(
      (value == 0 ? 0.0 : value).toStringAsFixed(2),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReaderSegmentControl<_LetterChoice>(
          key: const Key('novel-reader-letter-spacing-policy'),
          label: l10n.novelLetterSpacingScope,
          value: choice,
          values: _LetterChoice.values,
          enabled: enabled,
          labelBuilder: (option) => switch (option) {
            _LetterChoice.original => l10n.novelLetterSpacingOriginal,
            _LetterChoice.missing => l10n.novelLetterSpacingMissing,
            _LetterChoice.body => l10n.novelLetterSpacingBody,
            _LetterChoice.all => l10n.novelLetterSpacingAll,
          },
          onChanged: (next) => onChanged(
            value.withLetterSpacing(
              next == _LetterChoice.original
                  ? null
                  : NovelReaderLetterSpacing(
                      logicalPixels: request?.logicalPixels ?? 0,
                      scope: switch (next) {
                        _LetterChoice.missing =>
                          NovelReaderStyleScope.asDefault,
                        _LetterChoice.body => NovelReaderStyleScope.forceBody,
                        _LetterChoice.all => NovelReaderStyleScope.forceAll,
                        _LetterChoice.original => throw StateError(
                          'Unreachable letter spacing choice',
                        ),
                      },
                    ),
            ),
          ),
        ),
        if (request != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Row(
              children: [
                Expanded(child: Text(l10n.novelLetterSpacingAmount)),
                Text(amount(request.logicalPixels)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Semantics(
              label: l10n.novelLetterSpacingAmount,
              child: Slider(
                key: const Key('novel-reader-letter-spacing-slider'),
                value: request.logicalPixels,
                min: NovelReaderLetterSpacing.minimum,
                max: NovelReaderLetterSpacing.maximum,
                divisions:
                    ((NovelReaderLetterSpacing.maximum -
                                NovelReaderLetterSpacing.minimum) /
                            NovelReaderLetterSpacing.step)
                        .round(),
                semanticFormatterCallback: amount,
                onChanged: enabled
                    ? (number) => onChanged(
                        value.withLetterSpacing(
                          NovelReaderLetterSpacing(
                            logicalPixels:
                                (number / NovelReaderLetterSpacing.step)
                                    .round() *
                                NovelReaderLetterSpacing.step,
                            scope: request.scope,
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Text(
            enabled
                ? l10n.novelLetterSpacingHint
                : l10n.novelLetterSpacingUnavailable,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: Tooltip(
              message: l10n.novelLetterSpacingReset,
              child: TextButton(
                key: const Key('novel-reader-letter-spacing-reset'),
                onPressed: stored == null
                    ? null
                    : () => onChanged(value.withLetterSpacing(null)),
                child: Text(l10n.commonReset),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
