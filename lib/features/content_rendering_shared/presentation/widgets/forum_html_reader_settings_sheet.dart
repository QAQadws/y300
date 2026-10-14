import 'package:y300/features/content_rendering_shared/application/forum_html_reader_preferences_controller.dart';
import 'package:y300/features/content_rendering_shared/application/forum_html_typography_preview.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/content_rendering_shared/domain/models/forum_html_reader_preferences.dart';
import 'package:y300/l10n/app_localizations.dart';

class ForumHtmlReaderSettingsSheet extends ConsumerStatefulWidget {
  const ForumHtmlReaderSettingsSheet({
    super.key,
    this.showConversionControls = false,
    this.showAuthorStyleControls = true,
    this.showResetButton = true,
  });

  final bool showConversionControls;
  final bool showAuthorStyleControls;
  final bool showResetButton;

  @override
  ConsumerState<ForumHtmlReaderSettingsSheet> createState() =>
      _ForumHtmlReaderSettingsSheetState();
}

class _ForumHtmlReaderSettingsSheetState
    extends ConsumerState<ForumHtmlReaderSettingsSheet> {
  ForumHtmlReaderPreferencesController? _controller;
  ForumHtmlTypographyPreview? _preview;

  @override
  void dispose() {
    _preview?.close();
    super.dispose();
  }

  static void _reportError(Object error, StackTrace stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'HTML reading preferences',
      ),
    );
  }

  void _observe(Future<void> future) {
    unawaited(future.catchError(_reportError));
  }

  void _replacePreview(Future<void> Function() action) {
    final future = action();
    // Reset may retire a different local draft without changing provider state.
    setState(() => _preview = null);
    _observe(future);
  }

  ForumHtmlTypographyPreview _session() {
    if (_preview?.isActive != true) {
      _preview = _controller!.beginTypographyPreview(onError: _reportError);
    }
    return _preview!;
  }

  void _changeFont(double value) {
    final session = _session();
    session.change(session.value.copyWith(fontScale: value));
    setState(() {});
  }

  void _changeLineHeight(double value) {
    final session = _session();
    session.change(session.value.copyWith(lineHeightScale: value));
    setState(() {});
  }

  void _endDrag(double _) {
    _observe(_preview?.flush() ?? Future<void>.value());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final preferenceState = ref.watch(
      forumHtmlReaderPreferencesControllerProvider,
    );
    final preferences =
        preferenceState.value ?? ForumHtmlReaderPreferences.defaults();
    final controller = ref.read(
      forumHtmlReaderPreferencesControllerProvider.notifier,
    );
    if (!identical(controller, _controller)) {
      _preview?.cancel();
      _preview = null;
      _controller = controller;
    }
    final ready = preferenceState.hasValue && !preferenceState.isLoading;
    final typography = _preview?.isActive == true
        ? _preview!.value
        : preferences.typography;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.showConversionControls) ...[
              _ConversionModeSegmentedControl(
                mode: preferences.conversionMode,
                onChanged: ready
                    ? (mode) => _replacePreview(
                        () => controller.setConversionMode(mode),
                      )
                    : null,
              ),
              const SizedBox(height: 20),
            ],
            _TypographySlider(
              key: const Key('forum-html-reader-font-scale-slider'),
              label: l10n.threadHtmlFontSize,
              value: typography.fontScale,
              min: 0.7,
              max: 2.0,
              divisions: 26,
              display: '${(typography.fontScale * 100).round()}%',
              onChanged: ready ? _changeFont : null,
              onChangeEnd: ready ? _endDrag : null,
            ),
            const SizedBox(height: 16),
            _TypographySlider(
              key: const Key('forum-html-reader-line-height-slider'),
              label: l10n.threadHtmlLineSpacing,
              value: typography.lineHeightScale,
              min: 1.0,
              max: 2.5,
              divisions: 30,
              display: '${typography.lineHeightScale.toStringAsFixed(1)}×',
              onChanged: ready ? _changeLineHeight : null,
              onChangeEnd: ready ? _endDrag : null,
            ),
            if (widget.showAuthorStyleControls) ...[
              const SizedBox(height: 16),
              SwitchListTile(
                key: const Key('forum-html-reader-preserve-font-size-switch'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.threadHtmlPreserveAuthorFontSize),
                value: preferences.preserveAuthorFontSize,
                onChanged: ready
                    ? (value) => _replacePreview(
                        () => controller.setPreserveAuthorFontSize(value),
                      )
                    : null,
              ),
            ],
            if (widget.showResetButton) ...[
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  key: const Key('forum-html-reader-reset-button'),
                  onPressed: ready
                      ? () => _replacePreview(controller.reset)
                      : null,
                  child: Text(l10n.threadHtmlReset),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConversionModeSegmentedControl extends StatelessWidget {
  const _ConversionModeSegmentedControl({
    required this.mode,
    required this.onChanged,
  });

  final TextConversionMode mode;
  final ValueChanged<TextConversionMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<TextConversionMode>(
        key: const Key('forum-html-reader-conversion-mode-control'),
        segments: [
          ButtonSegment(
            value: TextConversionMode.none,
            label: Text(
              l10n.threadHtmlConversionOriginal,
              key: const Key('forum-html-reader-conversion-none'),
            ),
          ),
          ButtonSegment(
            value: TextConversionMode.toSimplified,
            label: Text(
              l10n.threadHtmlConversionSimplified,
              key: const Key('forum-html-reader-conversion-simplified'),
            ),
          ),
          ButtonSegment(
            value: TextConversionMode.toTraditional,
            label: Text(
              l10n.threadHtmlConversionTraditional,
              key: const Key('forum-html-reader-conversion-traditional'),
            ),
          ),
        ],
        selected: {mode},
        onSelectionChanged: onChanged == null
            ? null
            : (selection) {
                onChanged!(selection.single);
              },
      ),
    );
  }
}

class _TypographySlider extends StatelessWidget {
  const _TypographySlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: '$label $display',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.labelLarge)),
              Text(
                display,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.end,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ],
      ),
    );
  }
}
