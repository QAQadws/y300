part of 'thread_detail_widgets.dart';

class ThreadPollCard extends StatefulWidget {
  const ThreadPollCard({
    super.key,
    required this.poll,
    required this.selectedOptionIds,
    required this.isSubmitting,
    required this.commandAvailable,
    required this.hint,
    required this.onToggleOption,
    required this.onSubmit,
    required this.palette,
    this.notice,
  });

  final ThreadPoll poll;
  final Set<String> selectedOptionIds;
  final bool isSubmitting;
  final bool commandAvailable;
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
    final l10n = AppLocalizations.of(context);
    final canSubmit =
        widget.poll.canVote &&
        widget.commandAvailable &&
        widget.selectedOptionIds.isNotEmpty &&
        !widget.isSubmitting;
    final rules = (widget.poll.rulesText ?? widget.poll.summary).trim();
    final statusText = widget.poll.statusText?.trim();
    final localizedHint = widget.notice == null
        ? widget.hint?.trim()
        : ThreadTextResolver.actionNotice(l10n, widget.notice!);
    return Container(
      key: const Key('thread-poll-card'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: widget.palette.panelBackground,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ThreadPollHeader(
            poll: widget.poll,
            palette: widget.palette,
            expanded: _expanded,
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          if (_expanded)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (rules.isNotEmpty)
                  Text(
                    rules,
                    key: const Key('thread-poll-rules'),
                    style: textTheme.labelMedium?.copyWith(
                      color: widget.palette.muted,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                const SizedBox(height: 4),
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
                ],
                if (statusText != null && statusText.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    statusText,
                    key: const Key('thread-poll-status-text'),
                    style: textTheme.labelMedium?.copyWith(
                      color: widget.palette.muted,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
                if (localizedHint?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      localizedHint!,
                      key: const Key('thread-poll-vote-hint'),
                      style: textTheme.labelMedium?.copyWith(
                        color: widget.palette.muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
                if (widget.poll.canVote ||
                    widget.poll.deadlineText?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  _ThreadPollFooter(
                    poll: widget.poll,
                    palette: widget.palette,
                    selectedCount: widget.selectedOptionIds.length,
                    canSubmit: canSubmit,
                    isSubmitting: widget.isSubmitting,
                    onSubmit: widget.onSubmit,
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _ThreadPollHeader extends StatelessWidget {
  const _ThreadPollHeader({
    required this.poll,
    required this.palette,
    required this.expanded,
    required this.onTap,
  });

  final ThreadPoll poll;
  final ThreadDetailNativePalette palette;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    final participants = poll.participantCount;
    // Keep the expanded state on the button's single accessible node.
    return MergeSemantics(
      child: Semantics(
        button: true,
        expanded: expanded,
        child: TextButton(
          key: const Key('thread-poll-header'),
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: palette.title,
            backgroundColor: Colors.transparent,
            minimumSize: const Size(0, 36),
            visualDensity: const VisualDensity(vertical: -1),
            tapTargetSize: MaterialTapTargetSize.padded,
            padding: const EdgeInsets.symmetric(vertical: 4),
            alignment: AlignmentDirectional.centerStart,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          // Keep the heading independent of content removed by collapsing.
          child: Row(
            children: [
              Icon(Icons.bar_chart_rounded, size: 18, color: palette.title),
              const SizedBox(width: 6),
              Expanded(
                child: OverflowBar(
                  alignment: MainAxisAlignment.spaceBetween,
                  overflowAlignment: OverflowBarAlignment.end,
                  spacing: 12,
                  overflowSpacing: 4,
                  children: [
                    Text(
                      l10n.threadPollVote,
                      style: textTheme.titleSmall?.copyWith(
                        color: palette.title,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (participants != null && participants >= 0)
                      Text(
                        l10n.threadPollParticipants(participants),
                        key: const Key('thread-poll-participants'),
                        style: textTheme.labelMedium?.copyWith(
                          color: palette.muted,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                size: 18,
                color: palette.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThreadPollFooter extends StatelessWidget {
  const _ThreadPollFooter({
    required this.poll,
    required this.palette,
    required this.selectedCount,
    required this.canSubmit,
    required this.isSubmitting,
    required this.onSubmit,
  });

  final ThreadPoll poll;
  final ThreadDetailNativePalette palette;
  final int selectedCount;
  final bool canSubmit;
  final bool isSubmitting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final deadline = poll.deadlineText?.trim();
    final showSelectionCount =
        poll.canVote && poll.isMultipleChoice && selectedCount > 0;
    final hasInfo = showSelectionCount || deadline?.isNotEmpty == true;
    final style = Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(color: palette.muted);
    final info = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showSelectionCount)
          Semantics(
            liveRegion: true,
            child: Text(
              l10n.threadPollSelectedCount(selectedCount),
              key: const Key('thread-poll-selection-status'),
              style: style,
            ),
          ),
        if (deadline?.isNotEmpty == true) ...[
          if (showSelectionCount) const SizedBox(height: 4),
          Text(deadline!, style: style),
        ],
      ],
    );
    if (!poll.canVote) return info;
    // Let long deadlines and large text put the action on its own trailing row.
    return OverflowBar(
      alignment: hasInfo
          ? MainAxisAlignment.spaceBetween
          : MainAxisAlignment.end,
      overflowAlignment: OverflowBarAlignment.end,
      spacing: 12,
      overflowSpacing: 6,
      children: [
        if (hasInfo) info,
        FilledButton(
          key: const Key('thread-poll-submit-button'),
          onPressed: canSubmit ? onSubmit : null,
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isSubmitting ? l10n.threadPollSubmitting : l10n.threadPollVote,
              ),
              const SizedBox(width: 8),
              if (isSubmitting)
                SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: palette.muted,
                  ),
                )
              else
                const Icon(Icons.arrow_forward, size: 16),
            ],
          ),
        ),
      ],
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
    final sourcePercent = option.percent;
    final percent = sourcePercent?.isFinite == true ? sourcePercent : null;
    final color = _parseColor(option.colorHex) ?? palette.accent;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
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
                size: 20,
                color: selected ? palette.accent : palette.softText,
              ),
              const SizedBox(width: 10),
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
          ],
        ),
        if (percent != null || option.voteCount != null) ...[
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 8,
              runSpacing: 4,
              children: [
                if (option.voteCount != null)
                  Text(
                    AppLocalizations.of(
                      context,
                    ).threadPollVotes(option.voteCount!),
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: palette.muted),
                  ),
                if (percent != null)
                  Text(
                    '${percent.toStringAsFixed(percent.truncateToDouble() == percent ? 0 : 2)}%',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: palette.muted,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (percent != null) ...[
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (percent / 100).clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: palette.pollTrack,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ],
    );
    if (!showSelector) {
      return Padding(
        key: Key('thread-poll-option-${option.id}'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: content,
      );
    }
    return MergeSemantics(
      child: Semantics(
        checked: selected,
        enabled: enabled,
        inMutuallyExclusiveGroup: !isMultipleChoice,
        child: TextButton(
          key: Key('thread-poll-option-${option.id}'),
          onPressed: enabled ? onTap : null,
          style: TextButton.styleFrom(
            foregroundColor: palette.accent,
            backgroundColor: selected
                ? palette.accent.withValues(alpha: 0.07)
                : Colors.transparent,
            // Keep the 32px highlight with a denser 36px padded row.
            minimumSize: const Size(0, 44),
            visualDensity: const VisualDensity(vertical: -3),
            tapTargetSize: MaterialTapTargetSize.padded,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            alignment: AlignmentDirectional.centerStart,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: content,
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
      final parsed = int.tryParse('FF$expanded', radix: 16);
      return parsed == null ? null : Color(parsed);
    }
    if (hex.length == 6) {
      final parsed = int.tryParse('FF$hex', radix: 16);
      return parsed == null ? null : Color(parsed);
    }
    if (hex.length == 8) {
      final parsed = int.tryParse(hex, radix: 16);
      return parsed == null ? null : Color(parsed);
    }
    return null;
  }
}
