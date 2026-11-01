import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../domain/models/novel_reader_typography_overrides.dart';

enum _SpacingChoice { original, missing, body, all }

class NovelReaderParagraphSpacingSettingsPanel extends StatelessWidget {
  const NovelReaderParagraphSpacingSettingsPanel({
    super.key,
    required this.value,
    required this.legacyAfter,
    required this.enabled,
    required this.onChanged,
  });
  final NovelReaderTypographyOverrides value;
  final double legacyAfter;
  final bool enabled;
  final ValueChanged<NovelReaderTypographyOverrides> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final stored = value.paragraphSpacing;
    final request = stored?.isValid == true ? stored : null;
    final choice = request == null
        ? _SpacingChoice.original
        : switch (request.scope) {
            NovelReaderStyleScope.asDefault => _SpacingChoice.missing,
            NovelReaderStyleScope.forceBody => _SpacingChoice.body,
            NovelReaderStyleScope.forceAll => _SpacingChoice.all,
          };
    final initialAfter = legacyAfter.isFinite
        ? legacyAfter
              .clamp(
                NovelReaderParagraphSpacing.minimum,
                NovelReaderParagraphSpacing.maximum,
              )
              .toDouble()
        : 10.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReaderSegmentControl<_SpacingChoice>(
          key: const Key('novel-reader-paragraph-spacing-policy'),
          label: l10n.novelParagraphSpacingScope,
          value: choice,
          values: _SpacingChoice.values,
          enabled: enabled,
          labelBuilder: (option) => switch (option) {
            _SpacingChoice.original => l10n.novelParagraphSpacingOriginal,
            _SpacingChoice.missing => l10n.novelParagraphSpacingMissing,
            _SpacingChoice.body => l10n.novelParagraphSpacingBody,
            _SpacingChoice.all => l10n.novelParagraphSpacingAll,
          },
          onChanged: (next) => onChanged(
            value.withParagraphSpacing(
              next == _SpacingChoice.original
                  ? null
                  : NovelReaderParagraphSpacing(
                      before: request?.before ?? 0,
                      after: request?.after ?? initialAfter,
                      scope: switch (next) {
                        _SpacingChoice.missing =>
                          NovelReaderStyleScope.asDefault,
                        _SpacingChoice.body => NovelReaderStyleScope.forceBody,
                        _SpacingChoice.all => NovelReaderStyleScope.forceAll,
                        _SpacingChoice.original => throw StateError(
                          'Unreachable spacing choice',
                        ),
                      },
                    ),
            ),
          ),
        ),
        if (request != null) ...[
          _SpacingSlider(
            key: const Key('novel-reader-paragraph-before'),
            label: l10n.novelParagraphBefore,
            value: request.before,
            enabled: enabled,
            onChanged: (amount) => onChanged(
              value.withParagraphSpacing(
                NovelReaderParagraphSpacing(
                  before: amount,
                  after: request.after,
                  scope: request.scope,
                ),
              ),
            ),
          ),
          _SpacingSlider(
            key: const Key('novel-reader-paragraph-after'),
            label: l10n.novelParagraphAfter,
            value: request.after,
            enabled: enabled,
            onChanged: (amount) => onChanged(
              value.withParagraphSpacing(
                NovelReaderParagraphSpacing(
                  before: request.before,
                  after: amount,
                  scope: request.scope,
                ),
              ),
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Text(
            enabled
                ? l10n.novelParagraphSpacingHint
                : l10n.novelParagraphSpacingUnavailable,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: Tooltip(
              message: l10n.novelParagraphSpacingReset,
              child: TextButton(
                key: const Key('novel-reader-paragraph-spacing-reset'),
                onPressed: stored == null
                    ? null
                    : () => onChanged(value.withParagraphSpacing(null)),
                child: Text(l10n.commonReset),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SpacingSlider extends StatelessWidget {
  const _SpacingSlider({
    super.key,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });
  final String label;
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              AppLocalizations.of(context)
                  .novelParagraphSpacingValue(value.toStringAsFixed(1)),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Semantics(
          label: label,
          child: Slider(
            value: value,
            min: NovelReaderParagraphSpacing.minimum,
            max: NovelReaderParagraphSpacing.maximum,
            divisions:
                ((NovelReaderParagraphSpacing.maximum -
                            NovelReaderParagraphSpacing.minimum) /
                        NovelReaderParagraphSpacing.step)
                    .round(),
            semanticFormatterCallback: (amount) =>
                AppLocalizations.of(context)
                    .novelParagraphSpacingValue(amount.toStringAsFixed(1)),
            onChanged: enabled
                ? (amount) => onChanged(
                    (amount / NovelReaderParagraphSpacing.step).round() *
                        NovelReaderParagraphSpacing.step,
                  )
                : null,
          ),
        ),
      ),
    ],
  );
}
