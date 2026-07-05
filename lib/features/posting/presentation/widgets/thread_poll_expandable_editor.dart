import 'package:flutter/material.dart';
import 'package:y300/features/posting/domain/models/posting_models.dart';
import 'package:y300/features/posting/presentation/widgets/thread_poll_editor.dart';

class ThreadPollExpandableEditor extends StatelessWidget {
  const ThreadPollExpandableEditor({
    super.key,
    required this.poll,
    required this.expanded,
    required this.onExpansionChanged,
    required this.onOptionsChanged,
    required this.onMultipleChanged,
    required this.onMaxChoicesChanged,
    required this.onExpirationDaysChanged,
    required this.onOvertChanged,
    required this.onVisibilityPollChanged,
    this.enabled = true,
    this.toggleKey,
    this.summaryKey,
    this.panelKey,
    this.editorKey,
    this.optionFieldKeyBuilder,
    this.optionRemoveKeyBuilder,
    this.addOptionButtonKey,
    this.multipleSwitchKey,
    this.maxChoicesFieldKey,
    this.expirationFieldKey,
    this.overtSwitchKey,
    this.visibilityPollSwitchKey,
  });

  final NewThreadPollDraft poll;
  final bool expanded;
  final ValueChanged<bool> onExpansionChanged;
  final ValueChanged<List<String>> onOptionsChanged;
  final ValueChanged<bool> onMultipleChanged;
  final ValueChanged<int> onMaxChoicesChanged;
  final ValueChanged<int> onExpirationDaysChanged;
  final ValueChanged<bool> onOvertChanged;
  final ValueChanged<bool> onVisibilityPollChanged;
  final bool enabled;

  final Key? toggleKey;
  final Key? summaryKey;
  final Key? panelKey;
  final Key? editorKey;
  final Key Function(int index)? optionFieldKeyBuilder;
  final Key Function(int index)? optionRemoveKeyBuilder;
  final Key? addOptionButtonKey;
  final Key? multipleSwitchKey;
  final Key? maxChoicesFieldKey;
  final Key? expirationFieldKey;
  final Key? overtSwitchKey;
  final Key? visibilityPollSwitchKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PollConfigHeader(
          toggleKey: toggleKey,
          summaryKey: summaryKey,
          summary: _summary,
          expanded: expanded,
          enabled: enabled,
          onTap: () => onExpansionChanged(!expanded),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: expanded
              ? Padding(
                  key: panelKey,
                  padding: const EdgeInsets.only(top: 8),
                  child: ThreadPollEditor(
                    containerKey: editorKey,
                    optionFieldKeyBuilder: optionFieldKeyBuilder,
                    optionRemoveKeyBuilder: optionRemoveKeyBuilder,
                    addOptionButtonKey: addOptionButtonKey,
                    multipleSwitchKey: multipleSwitchKey,
                    maxChoicesFieldKey: maxChoicesFieldKey,
                    expirationFieldKey: expirationFieldKey,
                    overtSwitchKey: overtSwitchKey,
                    visibilityPollSwitchKey: visibilityPollSwitchKey,
                    poll: poll,
                    enabled: enabled,
                    onOptionsChanged: onOptionsChanged,
                    onMultipleChanged: onMultipleChanged,
                    onMaxChoicesChanged: onMaxChoicesChanged,
                    onExpirationDaysChanged: onExpirationDaysChanged,
                    onOvertChanged: onOvertChanged,
                    onVisibilityPollChanged: onVisibilityPollChanged,
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  String get _summary {
    final filledCount = poll.options.where((option) {
      return option.trim().isNotEmpty;
    }).length;
    final mode = poll.multiple ? '多选' : '单选';
    return '已填 $filledCount 项 / $mode';
  }
}

class _PollConfigHeader extends StatelessWidget {
  const _PollConfigHeader({
    required this.toggleKey,
    required this.summaryKey,
    required this.summary,
    required this.expanded,
    required this.enabled,
    required this.onTap,
  });

  final Key? toggleKey;
  final Key? summaryKey;
  final String summary;
  final bool expanded;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = enabled
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurface.withValues(alpha: 0.38);
    return SizedBox(
      key: toggleKey,
      height: 44,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '投票配置',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          summary,
                          key: summaryKey,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: foreground,
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: expanded ? 0.5 : 0),
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOutCubic,
                    builder: (context, turns, child) {
                      return RotationTransition(
                        turns: AlwaysStoppedAnimation<double>(turns),
                        child: child,
                      );
                    },
                    child: Icon(Icons.keyboard_arrow_down, color: foreground),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
