part of 'thread_detail_widgets.dart';

// Poll widgets for thread detail: poll card and option tiles. Moved verbatim
// from thread_detail_widgets.dart (Phase 5b file split); keys and logic unchanged.

class ThreadPollCard extends StatefulWidget {
  const ThreadPollCard({
    super.key,
    required this.poll,
    required this.selectedOptionIds,
    required this.isSubmitting,
    required this.hint,
    required this.onToggleOption,
    required this.onSubmit,
    required this.palette,
    this.notice,
  });

  final ThreadPoll poll;
  final Set<String> selectedOptionIds;
  final bool isSubmitting;
  final String? hint;
  final ValueChanged<ThreadPollOption> onToggleOption;
  final VoidCallback onSubmit;
  final ThreadDetailNativePalette palette;
  final ThreadActionNotice? notice;

  @override
  State<ThreadPollCard> createState() => _ThreadPollCardState();
}

class _ThreadPollCardState extends State<ThreadPollCard> {
  var _expanded = true;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final canSubmit =
        widget.poll.canVote &&
        widget.selectedOptionIds.isNotEmpty &&
        !widget.isSubmitting &&
        (widget.poll.actionUrl?.trim().isNotEmpty ?? false);
    final statusText = widget.poll.statusText?.trim();
    final localizedHint = widget.notice == null
        ? widget.hint?.trim()
        : ThreadTextResolver.actionNotice(
            AppLocalizations.of(context),
            widget.notice!,
          );
    return Container(
      key: const Key('thread-poll-card'),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: widget.palette.panelBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              key: const Key('thread-poll-header'),
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.poll.summary,
                        style: textTheme.labelLarge?.copyWith(
                          color: widget.palette.title,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.poll.deadlineText?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 5),
                  Text(
                    widget.poll.deadlineText!.trim(),
                    style: textTheme.labelSmall?.copyWith(
                      color: widget.palette.muted,
                    ),
                  ),
                ],
                const SizedBox(height: 9),
                for (final option in widget.poll.options) ...[
                  ThreadPollOptionTile(
                    option: option,
                    palette: widget.palette,
                    isMultipleChoice: widget.poll.isMultipleChoice,
                    showSelector: widget.poll.canVote,
                    selected: widget.selectedOptionIds.contains(option.id),
                    enabled: widget.poll.canVote && !widget.isSubmitting,
                    onTap: () => widget.onToggleOption(option),
                  ),
                  const SizedBox(height: 8),
                ],
                if (statusText != null && statusText.isNotEmpty) ...[
                  Text(
                    statusText,
                    key: const Key('thread-poll-status-text'),
                    style: textTheme.labelSmall?.copyWith(
                      color: widget.palette.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (localizedHint?.isNotEmpty == true) ...[
                  Text(
                    localizedHint!,
                    key: const Key('thread-poll-vote-hint'),
                    style: textTheme.labelSmall?.copyWith(
                      color: widget.palette.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (widget.poll.canVote)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const Key('thread-poll-submit-button'),
                      onPressed: canSubmit ? widget.onSubmit : null,
                      child: widget.isSubmitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(AppLocalizations.of(context).threadPollSubmit),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class ThreadPollOptionTile extends StatelessWidget {
  const ThreadPollOptionTile({
    super.key,
    required this.option,
    required this.palette,
    required this.isMultipleChoice,
    required this.showSelector,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final ThreadPollOption option;
  final ThreadDetailNativePalette palette;
  final bool isMultipleChoice;
  final bool showSelector;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final percent = option.percent;
    final color = _parseColor(option.colorHex) ?? palette.accent;
    return Material(
      color: selected
          ? palette.accent.withValues(alpha: 0.07)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        key: Key('thread-poll-option-${option.id}'),
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(5, 5, 5, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (showSelector) ...[
                    Icon(
                      selected
                          ? isMultipleChoice
                                ? Icons.check_box
                                : Icons.radio_button_checked
                          : isMultipleChoice
                          ? Icons.check_box_outline_blank
                          : Icons.radio_button_unchecked,
                      size: 17,
                      color: selected ? palette.accent : palette.softText,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      option.label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.bodyText,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                  if (percent != null)
                    Text(
                      '${percent.toStringAsFixed(percent.truncateToDouble() == percent ? 0 : 2)}%',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: palette.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              if (percent != null) ...[
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: (percent / 100).clamp(0.0, 1.0),
                    minHeight: 5,
                    backgroundColor: palette.pollTrack,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                if (option.voteCount != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    AppLocalizations.of(
                      context,
                    ).threadPollVotes(option.voteCount!),
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: palette.softText),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color? _parseColor(String? value) {
    final source = value?.trim();
    if (source == null || source.isEmpty || !source.startsWith('#')) {
      return null;
    }
    final hex = source.substring(1);
    if (hex.length == 3) {
      final expanded = hex.split('').map((char) => '$char$char').join();
      return Color(int.parse('FF$expanded', radix: 16));
    }
    if (hex.length == 6) {
      return Color(int.parse('FF$hex', radix: 16));
    }
    if (hex.length == 8) {
      return Color(int.parse(hex, radix: 16));
    }
    return null;
  }
}
