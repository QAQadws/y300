import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_sheet_widgets.dart';
import 'package:y300/features/reader_shared/domain/reader_preferences/reader_preferences.dart';
import 'package:y300/features/reader_shared/presentation/reader_text_resolver.dart';
import 'package:y300/l10n/app_localizations.dart';

/// 阅读器显示设置抽屉（阅读模式 / 页面适配 / 背景 / 页间距 / 页码浮层）。
///
/// 自原 `comic_reader_page.dart` 抽取为共享组件，供 [ImageReaderEngine] 复用。
/// 仅产出 UI 与本地预览状态，实际持久化通过回调交回上层（共享偏好 controller）。
class ReaderDisplaySettingsSheet extends StatelessWidget {
  const ReaderDisplaySettingsSheet({
    super.key,
    required this.preferences,
    required this.onModeChanged,
    required this.onPageFitChanged,
    required this.onBackgroundChanged,
    required this.onPageSpacingChanged,
    required this.onShowPageIndicatorChanged,
  });

  final ReaderPreferences preferences;
  final ValueChanged<ReaderModePreference> onModeChanged;
  final ValueChanged<ReaderPageFitPreference> onPageFitChanged;
  final ValueChanged<ReaderBackgroundPreference> onBackgroundChanged;
  final ValueChanged<double> onPageSpacingChanged;
  final ValueChanged<bool> onShowPageIndicatorChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: _ReaderDisplaySettingsContent(
        preferences: preferences,
        onModeChanged: onModeChanged,
        onPageFitChanged: onPageFitChanged,
        onBackgroundChanged: onBackgroundChanged,
        onPageSpacingChanged: onPageSpacingChanged,
        onShowPageIndicatorChanged: onShowPageIndicatorChanged,
      ),
    );
  }
}

/// 阅读模式选择抽屉（垂直 / 左到右 / 右到左）。
class ReaderModeSheet extends StatelessWidget {
  const ReaderModeSheet({super.key, required this.currentMode});

  final ReaderModePreference currentMode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: RadioGroup<ReaderModePreference>(
        groupValue: currentMode,
        onChanged: (value) {
          if (value != null) {
            Navigator.of(context).pop(value);
          }
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReaderSheetTitle(title: l10n.readerReadingMode),
            _ReaderModeTile(
              mode: ReaderModePreference.vertical,
              icon: Icons.view_stream_outlined,
              label: ReaderTextResolver.modeChoice(
                l10n,
                ReaderModePreference.vertical,
              ),
            ),
            _ReaderModeTile(
              mode: ReaderModePreference.ltr,
              icon: Icons.swipe_left_outlined,
              label: ReaderTextResolver.modeChoice(
                l10n,
                ReaderModePreference.ltr,
              ),
            ),
            _ReaderModeTile(
              mode: ReaderModePreference.rtl,
              icon: Icons.swipe_right_outlined,
              label: ReaderTextResolver.modeChoice(
                l10n,
                ReaderModePreference.rtl,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderModeTile extends StatelessWidget {
  const _ReaderModeTile({
    required this.mode,
    required this.icon,
    required this.label,
  });

  final ReaderModePreference mode;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey<String>('comic-reader-mode-${mode.name}'),
      leading: Icon(icon),
      title: Text(label),
      trailing: Radio<ReaderModePreference>(value: mode),
      onTap: () => Navigator.of(context).pop(mode),
    );
  }
}

class _ReaderDisplaySettingsContent extends StatefulWidget {
  const _ReaderDisplaySettingsContent({
    required this.preferences,
    required this.onModeChanged,
    required this.onPageFitChanged,
    required this.onBackgroundChanged,
    required this.onPageSpacingChanged,
    required this.onShowPageIndicatorChanged,
  });

  final ReaderPreferences preferences;
  final ValueChanged<ReaderModePreference> onModeChanged;
  final ValueChanged<ReaderPageFitPreference> onPageFitChanged;
  final ValueChanged<ReaderBackgroundPreference> onBackgroundChanged;
  final ValueChanged<double> onPageSpacingChanged;
  final ValueChanged<bool> onShowPageIndicatorChanged;

  @override
  State<_ReaderDisplaySettingsContent> createState() =>
      _ReaderDisplaySettingsContentState();
}

class _ReaderDisplaySettingsContentState
    extends State<_ReaderDisplaySettingsContent> {
  late ReaderPreferences _current;

  @override
  void initState() {
    super.initState();
    _current = widget.preferences;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      key: const Key('comic-reader-display-settings-sheet'),
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        ReaderSheetTitle(title: l10n.readerDisplaySettings),
        ReaderSegmentControl<ReaderModePreference>(
          label: l10n.readerReadingMode,
          value: _current.readerMode,
          values: ReaderModePreference.values,
          labelBuilder: (value) => ReaderTextResolver.mode(l10n, value),
          onChanged: (value) {
            setState(() => _current = _current.copyWith(readerMode: value));
            widget.onModeChanged(value);
          },
        ),
        ReaderSegmentControl<ReaderPageFitPreference>(
          label: l10n.readerPageFit,
          value: _current.pageFit,
          values: ReaderPageFitPreference.values,
          labelBuilder: (value) => ReaderTextResolver.pageFit(l10n, value),
          onChanged: (value) {
            setState(() => _current = _current.copyWith(pageFit: value));
            widget.onPageFitChanged(value);
          },
        ),
        ReaderSegmentControl<ReaderBackgroundPreference>(
          label: l10n.readerBackground,
          value: _current.background,
          values: ReaderBackgroundPreference.values,
          labelBuilder: (value) => ReaderTextResolver.background(l10n, value),
          onChanged: (value) {
            setState(() => _current = _current.copyWith(background: value));
            widget.onBackgroundChanged(value);
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Row(
            children: [
              SizedBox(width: 88, child: Text(l10n.readerPageSpacing)),
              Expanded(
                child: Slider(
                  key: const Key('comic-reader-page-spacing-slider'),
                  value: _current.pageSpacing.clamp(0.0, 48.0).toDouble(),
                  min: 0,
                  max: 48,
                  divisions: 12,
                  label: _current.pageSpacing.round().toString(),
                  onChanged: (value) {
                    setState(
                      () => _current = _current.copyWith(pageSpacing: value),
                    );
                    widget.onPageSpacingChanged(value);
                  },
                ),
              ),
            ],
          ),
        ),
        SwitchListTile(
          key: const Key('comic-reader-page-indicator-switch'),
          title: Text(l10n.readerPageIndicator),
          value: _current.showPageIndicator,
          onChanged: (value) {
            setState(
              () => _current = _current.copyWith(showPageIndicator: value),
            );
            widget.onShowPageIndicatorChanged(value);
          },
        ),
      ],
    );
  }
}
