import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../domain/models/novel_reader_typography_overrides.dart';

typedef NovelReaderScopedNumberValue = ({
  double number,
  NovelReaderStyleScope scope,
});
typedef NovelReaderScopedNumberLabels = ({
  String scope,
  String original,
  String missing,
  String body,
  String all,
  String amount,
  String hint,
  String unavailable,
  String reset,
  String Function(String) formatNumber,
});

enum _ScopeChoice { original, missing, body, all }

/// Shared presentation for scoped numeric settings. Typed wrappers own units,
/// ranges, labels and field-local edits; this widget never reads/writes storage.
class NovelReaderScopedNumberSettingsPanel extends StatelessWidget {
  const NovelReaderScopedNumberSettingsPanel({
    super.key,
    required this.keyPrefix,
    required this.value,
    required this.canReset,
    required this.minimum,
    required this.maximum,
    required this.step,
    required this.labels,
    required this.enabled,
    required this.onChanged,
  });
  final String keyPrefix;
  final NovelReaderScopedNumberValue? value;
  final bool canReset;
  final double minimum;
  final double maximum;
  final double step;
  final NovelReaderScopedNumberLabels labels;
  final bool enabled;
  final ValueChanged<NovelReaderScopedNumberValue?> onChanged;

  @override
  Widget build(BuildContext context) {
    final request = value;
    final choice = request == null
        ? _ScopeChoice.original
        : switch (request.scope) {
            NovelReaderStyleScope.asDefault => _ScopeChoice.missing,
            NovelReaderStyleScope.forceBody => _ScopeChoice.body,
            NovelReaderStyleScope.forceAll => _ScopeChoice.all,
          };
    String amount(double number) =>
        labels.formatNumber((number == 0 ? 0.0 : number).toStringAsFixed(2));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReaderSegmentControl<_ScopeChoice>(
          key: Key('$keyPrefix-policy'),
          label: labels.scope,
          value: choice,
          values: _ScopeChoice.values,
          enabled: enabled,
          labelBuilder: (option) => switch (option) {
            _ScopeChoice.original => labels.original,
            _ScopeChoice.missing => labels.missing,
            _ScopeChoice.body => labels.body,
            _ScopeChoice.all => labels.all,
          },
          onChanged: (next) => onChanged(
            next == _ScopeChoice.original
                ? null
                : (
                    number: request?.number ?? 0,
                    scope: switch (next) {
                      _ScopeChoice.missing => NovelReaderStyleScope.asDefault,
                      _ScopeChoice.body => NovelReaderStyleScope.forceBody,
                      _ScopeChoice.all => NovelReaderStyleScope.forceAll,
                      _ScopeChoice.original => throw StateError(
                        'Unreachable numeric style choice',
                      ),
                    },
                  ),
          ),
        ),
        if (request != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Row(
              children: [
                Expanded(child: Text(labels.amount)),
                Text(amount(request.number)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Semantics(
              label: labels.amount,
              child: Slider(
                key: Key('$keyPrefix-slider'),
                value: request.number,
                min: minimum,
                max: maximum,
                divisions: ((maximum - minimum) / step).round(),
                semanticFormatterCallback: amount,
                onChanged: enabled
                    ? (number) => onChanged((
                        number: (number / step).round() * step,
                        scope: request.scope,
                      ))
                    : null,
              ),
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Text(
            enabled ? labels.hint : labels.unavailable,
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
                onPressed: canReset ? () => onChanged(null) : null,
                child: Text(AppLocalizations.of(context).commonReset),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
