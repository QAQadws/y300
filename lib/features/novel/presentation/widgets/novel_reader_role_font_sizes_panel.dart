import 'package:flutter/material.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../domain/models/novel_reader_typography_overrides.dart';

class NovelReaderRoleFontSizesPanel extends StatelessWidget {
  const NovelReaderRoleFontSizesPanel({
    super.key,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final NovelReaderRoleFontSizes value;
  final bool enabled;
  final ValueChanged<NovelReaderRoleFontSizes> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    int percent(int? stored) =>
        NovelReaderRoleFontSizes.validPercent(stored) ??
        NovelReaderRoleFontSizes.defaultPercent;
    final labels = [
      ('heading', l10n.novelRoleFontSizeHeading, percent(value.heading)),
      ('quote', l10n.novelRoleFontSizeQuote, percent(value.quote)),
      ('code', l10n.novelRoleFontSizeCode, percent(value.code)),
      ('ruby', l10n.novelRoleFontSizeRuby, percent(value.ruby)),
    ];
    const min = NovelReaderRoleFontSizes.minimum;
    const max = NovelReaderRoleFontSizes.maximum;
    const divisions = (max - min) ~/ NovelReaderRoleFontSizes.step;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            enabled
                ? l10n.novelRoleFontSizesHint
                : l10n.novelRoleFontSizesUnavailable,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          for (final (role, title, amount) in labels) ...[
            ExcludeSemantics(
              child: Row(
                children: [
                  Expanded(child: Text(title)),
                  Text(l10n.novelRoleFontSizePercent(amount)),
                ],
              ),
            ),
            Semantics(
              label: title,
              child: Slider(
                key: ValueKey('novel-reader-role-font-size-$role'),
                min: min.toDouble(),
                max: max.toDouble(),
                divisions: divisions,
                value: amount.toDouble(),
                label: l10n.novelRoleFontSizePercent(amount),
                semanticFormatterCallback: (number) =>
                    l10n.novelRoleFontSizePercent(number.round()),
                onChanged: enabled
                    ? (number) {
                        final next = number.round();
                        onChanged(
                          NovelReaderRoleFontSizes(
                            heading: role == 'heading' ? next : value.heading,
                            quote: role == 'quote' ? next : value.quote,
                            code: role == 'code' ? next : value.code,
                            ruby: role == 'ruby' ? next : value.ruby,
                          ),
                        );
                      }
                    : null,
              ),
            ),
          ],
          if (!value.isEmpty)
            TextButton(
              key: const Key('novel-reader-role-font-sizes-reset'),
              onPressed: () => onChanged(const NovelReaderRoleFontSizes()),
              child: Text(l10n.novelRoleFontSizesReset),
            ),
        ],
      ),
    );
  }
}
