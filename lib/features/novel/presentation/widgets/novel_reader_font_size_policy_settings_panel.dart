import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../domain/models/novel_reader_typography_overrides.dart';

enum _SizeChoice { original, author, body, all }

class NovelReaderFontSizePolicySettingsPanel extends StatelessWidget {
  const NovelReaderFontSizePolicySettingsPanel({
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
    final choice = switch (value.fontSizeScope) {
      null => _SizeChoice.original,
      NovelReaderStyleScope.asDefault => _SizeChoice.author,
      NovelReaderStyleScope.forceBody => _SizeChoice.body,
      NovelReaderStyleScope.forceAll => _SizeChoice.all,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReaderSegmentControl<_SizeChoice>(
          key: const Key('novel-reader-font-size-policy'),
          label: l10n.novelFontSizePolicy,
          value: choice,
          values: _SizeChoice.values,
          enabled: enabled,
          labelBuilder: (option) => switch (option) {
            _SizeChoice.original => l10n.novelFontSizePolicyOriginal,
            _SizeChoice.author => l10n.novelFontSizePolicyAuthor,
            _SizeChoice.body => l10n.novelFontSizePolicyBody,
            _SizeChoice.all => l10n.novelFontSizePolicyAll,
          },
          onChanged: (next) => onChanged(
            value.withFontSizeScope(switch (next) {
              _SizeChoice.original => null,
              _SizeChoice.author => NovelReaderStyleScope.asDefault,
              _SizeChoice.body => NovelReaderStyleScope.forceBody,
              _SizeChoice.all => NovelReaderStyleScope.forceAll,
            }),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Text(
            !enabled
                ? l10n.novelFontSizePolicyUnavailable
                : choice == _SizeChoice.all
                ? l10n.novelFontSizePolicyAllHint
                : l10n.novelFontSizePolicyHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: Tooltip(
              message: l10n.novelFontSizePolicyReset,
              child: TextButton(
                key: const Key('novel-reader-font-size-reset'),
                onPressed: value.fontSizeScope == null
                    ? null
                    : () => onChanged(value.withFontSizeScope(null)),
                child: Text(l10n.commonReset),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
