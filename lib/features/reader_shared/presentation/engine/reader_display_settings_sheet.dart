import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_sheet_widgets.dart';
import 'package:y300/features/reader_shared/domain/reader_preferences/reader_preferences.dart';

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
    return SafeArea(
      child: RadioGroup<ReaderModePreference>(
        groupValue: currentMode,
        onChanged: (value) {
          if (value != null) {
            Navigator.of(context).pop(value);
          }
        },
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReaderSheetTitle(title: '阅读模式'),
            _ReaderModeTile(
              mode: ReaderModePreference.vertical,
              icon: Icons.view_stream_outlined,
              label: '垂直连续',
            ),
            _ReaderModeTile(
              mode: ReaderModePreference.ltr,
              icon: Icons.swipe_left_outlined,
              label: '单页 左到右',
            ),
            _ReaderModeTile(
              mode: ReaderModePreference.rtl,
              icon: Icons.swipe_right_outlined,
              label: '单页 右到左',
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
    return ListView(
      key: const Key('comic-reader-display-settings-sheet'),
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        const ReaderSheetTitle(title: '显示设置'),
        ReaderSegmentControl<ReaderModePreference>(
          label: '阅读模式',
          value: _current.readerMode,
          values: ReaderModePreference.values,
          labelBuilder: _readerModeLabel,
          onChanged: (value) {
            setState(() => _current = _current.copyWith(readerMode: value));
            widget.onModeChanged(value);
          },
        ),
        ReaderSegmentControl<ReaderPageFitPreference>(
          label: '页面适配',
          value: _current.pageFit,
          values: ReaderPageFitPreference.values,
          labelBuilder: _pageFitLabel,
          onChanged: (value) {
            setState(() => _current = _current.copyWith(pageFit: value));
            widget.onPageFitChanged(value);
          },
        ),
        ReaderSegmentControl<ReaderBackgroundPreference>(
          label: '背景色',
          value: _current.background,
          values: ReaderBackgroundPreference.values,
          labelBuilder: _backgroundLabel,
          onChanged: (value) {
            setState(() => _current = _current.copyWith(background: value));
            widget.onBackgroundChanged(value);
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Row(
            children: [
              const SizedBox(width: 88, child: Text('页间距')),
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
          title: const Text('页码浮层'),
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

  String _readerModeLabel(ReaderModePreference value) {
    switch (value) {
      case ReaderModePreference.vertical:
        return '垂直';
      case ReaderModePreference.ltr:
        return 'LTR';
      case ReaderModePreference.rtl:
        return 'RTL';
    }
  }

  String _pageFitLabel(ReaderPageFitPreference value) {
    switch (value) {
      case ReaderPageFitPreference.fitWidth:
        return '宽度';
      case ReaderPageFitPreference.fitHeight:
        return '高度';
      case ReaderPageFitPreference.contain:
        return '屏幕';
      case ReaderPageFitPreference.original:
        return '原始';
    }
  }

  String _backgroundLabel(ReaderBackgroundPreference value) {
    switch (value) {
      case ReaderBackgroundPreference.followTheme:
        return '主题';
      case ReaderBackgroundPreference.black:
        return '黑';
      case ReaderBackgroundPreference.white:
        return '白';
      case ReaderBackgroundPreference.gray:
        return '灰';
    }
  }
}
