import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../domain/models/novel_reader_preferences.dart';

enum _WidthChoice { original, limited, available }

class NovelReaderViewportSettingsPanel extends StatelessWidget {
  const NovelReaderViewportSettingsPanel({
    super.key,
    required this.value,
    required this.legacyPadding,
    required this.legacyMaximumWidth,
    required this.enabled,
    required this.onChanged,
  });
  final NovelReaderViewportOverrides value;
  final double legacyPadding;
  final double legacyMaximumWidth;
  final bool enabled;
  final ValueChanged<NovelReaderViewportOverrides> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final width = value.contentWidth?.isValid == true
        ? value.contentWidth
        : null;
    final rememberedLimit =
        width?.logicalPixels ??
        (legacyMaximumWidth.isFinite
            ? legacyMaximumWidth
                  .clamp(
                    NovelReaderContentWidth.minimum,
                    NovelReaderContentWidth.maximum,
                  )
                  .toDouble()
            : NovelReaderContentWidth.initial);
    final defaultMargin = legacyPadding.clamp(0.0, 96.0).toDouble();
    String pixels(double v) => l10n.novelViewportPixels(v.toStringAsFixed(0));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Text(
            enabled ? l10n.novelViewportHint : l10n.novelViewportUnavailable,
          ),
        ),
        ReaderSegmentControl<NovelReaderColumnCount>(
          key: const Key('novel-reader-viewport-columns'),
          label: l10n.novelViewportColumns,
          value: value.columns ?? NovelReaderColumnCount.single,
          values: NovelReaderColumnCount.values,
          enabled: enabled,
          labelBuilder: (count) => switch (count) {
            NovelReaderColumnCount.single => l10n.novelViewportSingleColumn,
            NovelReaderColumnCount.double => l10n.novelViewportDoubleColumn,
            NovelReaderColumnCount.triple => l10n.novelViewportTripleColumn,
          },
          onChanged: (count) => onChanged(value.withColumns(count)),
        ),
        if (enabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(l10n.novelViewportColumnsHint),
          ),
        for (final edge in NovelReaderViewportEdge.values)
          _ViewportMarginControl(
            keyPrefix: 'novel-reader-viewport-${edge.name}',
            label: switch (edge) {
              NovelReaderViewportEdge.left => l10n.novelViewportLeft,
              NovelReaderViewportEdge.top => l10n.novelViewportTop,
              NovelReaderViewportEdge.right => l10n.novelViewportRight,
              NovelReaderViewportEdge.bottom => l10n.novelViewportBottom,
            },
            value: value.marginFor(edge),
            defaultValue: defaultMargin,
            enabled: enabled,
            onChanged: (next) => onChanged(value.withMargin(edge, next)),
          ),
        ReaderSegmentControl<_WidthChoice>(
          key: const Key('novel-reader-viewport-width-mode'),
          label: l10n.novelViewportWidth,
          value: width == null
              ? _WidthChoice.original
              : width.mode == NovelReaderContentWidthMode.limited
              ? _WidthChoice.limited
              : _WidthChoice.available,
          values: _WidthChoice.values,
          enabled: enabled,
          labelBuilder: (v) => switch (v) {
            _WidthChoice.original => l10n.novelViewportWidthOriginal,
            _WidthChoice.limited => l10n.novelViewportWidthLimited,
            _WidthChoice.available => l10n.novelViewportWidthAvailable,
          },
          onChanged: (v) => onChanged(
            value.withContentWidth(switch (v) {
              _WidthChoice.original => null,
              _WidthChoice.limited => NovelReaderContentWidth.limited(
                rememberedLimit,
              ),
              _WidthChoice.available => NovelReaderContentWidth.available(
                logicalPixels: rememberedLimit,
              ),
            }),
          ),
        ),
        if (width?.mode == NovelReaderContentWidthMode.limited)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(pixels(width!.logicalPixels)),
            ),
          ),
        if (width?.mode == NovelReaderContentWidthMode.limited)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Semantics(
              label: l10n.novelViewportWidth,
              child: Slider(
                key: const Key('novel-reader-viewport-width-slider'),
                value: width!.logicalPixels,
                min: NovelReaderContentWidth.minimum,
                max: NovelReaderContentWidth.maximum,
                divisions:
                    ((NovelReaderContentWidth.maximum -
                                NovelReaderContentWidth.minimum) /
                            NovelReaderContentWidth.step)
                        .round(),
                label: pixels(width.logicalPixels),
                semanticFormatterCallback: pixels,
                onChanged: enabled
                    ? (v) => onChanged(
                        value.withContentWidth(
                          NovelReaderContentWidth.limited(
                            (v / NovelReaderContentWidth.step).round() *
                                NovelReaderContentWidth.step,
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            key: const Key('novel-reader-viewport-width-reset'),
            onPressed: value.contentWidth == null
                ? null
                : () => onChanged(value.withContentWidth(null)),
            child: Text(l10n.novelViewportWidthReset),
          ),
        ),
      ],
    );
  }
}

class _ViewportMarginControl extends StatelessWidget {
  const _ViewportMarginControl({
    required this.keyPrefix,
    required this.label,
    required this.value,
    required this.defaultValue,
    required this.enabled,
    required this.onChanged,
  });
  final String keyPrefix;
  final String label;
  final double? value;
  final double defaultValue;
  final bool enabled;
  final ValueChanged<double?> onChanged;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final number =
        value != null && NovelReaderViewportOverrides.validMargin(value!)
        ? value
        : null;
    String pixels(double v) => l10n.novelViewportPixels(v.toStringAsFixed(0));
    return Column(
      children: [
        SwitchListTile(
          key: Key('$keyPrefix-enabled'),
          title: Text(label),
          subtitle: Text(
            number == null
                ? l10n.novelViewportInheritedPixels(
                    defaultValue.toStringAsFixed(0),
                  )
                : pixels(number),
          ),
          value: number != null,
          onChanged: enabled
              ? (on) => onChanged(on ? (number ?? defaultValue) : null)
              : null,
        ),
        if (value != null)
          Row(
            children: [
              if (number == null)
                const Spacer()
              else
                Expanded(
                  child: Semantics(
                    label: label,
                    child: Slider(
                      key: Key('$keyPrefix-slider'),
                      value: number,
                      min: NovelReaderViewportOverrides.minimumMargin,
                      max: NovelReaderViewportOverrides.maximumMargin,
                      divisions:
                          ((NovelReaderViewportOverrides.maximumMargin -
                                      NovelReaderViewportOverrides
                                          .minimumMargin) /
                                  NovelReaderViewportOverrides.marginStep)
                              .round(),
                      semanticFormatterCallback: pixels,
                      onChanged: enabled
                          ? (v) => onChanged(v.roundToDouble())
                          : null,
                    ),
                  ),
                ),
              Tooltip(
                message: l10n.novelViewportResetMargin(label),
                child: IconButton(
                  key: Key('$keyPrefix-reset'),
                  icon: const Icon(Icons.restart_alt),
                  onPressed: () => onChanged(null),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
