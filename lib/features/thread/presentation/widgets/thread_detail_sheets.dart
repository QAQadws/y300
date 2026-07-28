part of 'thread_detail_widgets.dart';

// Bottom-sheet widgets for thread detail: rating sheet and comment sheet.
// Moved verbatim from thread_detail_widgets.dart (Phase 5b file split);
// keys and logic unchanged.

class ThreadPostRateSheet extends StatefulWidget {
  const ThreadPostRateSheet({super.key, required this.form});

  final ThreadPostRateForm form;

  @override
  State<ThreadPostRateSheet> createState() => _ThreadPostRateSheetState();
}

class _ThreadPostRateSheetState extends State<ThreadPostRateSheet> {
  late int _score;
  late bool _notifyAuthor;
  late final TextEditingController _reasonController;

  @override
  void initState() {
    super.initState();
    _score = widget.form.defaultScore;
    _notifyAuthor = widget.form.notifyAuthorDefault;
    _reasonController = TextEditingController();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 16 + bottomInset),
        child: Column(
          key: const Key('thread-post-rate-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  l10n.threadRatingTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                IconButton(
                  key: const Key('thread-post-rate-close-button'),
                  tooltip: l10n.commonClose,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  l10n.threadRatingScore,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                IconButton(
                  key: const Key('thread-post-rate-decrease-button'),
                  onPressed: _score > widget.form.scoreMin
                      ? () => setState(() => _score -= 1)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                SizedBox(
                  width: 54,
                  child: Text(
                    '+$_score',
                    key: const Key('thread-post-rate-score-label'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('thread-post-rate-increase-button'),
                  onPressed: _score < widget.form.scoreMax
                      ? () => setState(() => _score += 1)
                      : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            Text(_scoreHint(l10n), style: theme.textTheme.labelSmall),
            if (widget.form.reasonOptions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final reason in widget.form.reasonOptions)
                    ActionChip(
                      key: Key('thread-post-rate-reason-$reason'),
                      label: Text(reason),
                      onPressed: () {
                        _reasonController.text = reason;
                        setState(() {});
                      },
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              key: const Key('thread-post-rate-reason-input'),
              controller: _reasonController,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l10n.threadRatingReasonHint,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              key: const Key('thread-post-rate-notify-switch'),
              contentPadding: EdgeInsets.zero,
              value: _notifyAuthor,
              onChanged: (value) => setState(() => _notifyAuthor = value),
              title: Text(l10n.threadRatingNotifyAuthor),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('thread-post-rate-submit-button'),
                onPressed: _reasonController.text.trim().isEmpty
                    ? null
                    : () {
                        Navigator.of(context).pop(
                          ThreadPostRateDraft(
                            form: widget.form,
                            score: _score,
                            reason: _reasonController.text,
                            notifyAuthor: _notifyAuthor,
                          ),
                        );
                      },
                child: Text(l10n.threadRatingSubmit),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _scoreHint(AppLocalizations l10n) {
    final remaining = widget.form.todayRemaining;
    return ThreadTextResolver.ratingRange(
      l10n,
      widget.form.scoreMin,
      widget.form.scoreMax,
      remaining,
    );
  }
}

class ThreadPostCommentSheet extends StatefulWidget {
  const ThreadPostCommentSheet({super.key, required this.form});

  final ThreadPostCommentForm form;

  @override
  State<ThreadPostCommentSheet> createState() => _ThreadPostCommentSheetState();
}

class _ThreadPostCommentSheetState extends State<ThreadPostCommentSheet> {
  late final TextEditingController _messageController;

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxLength = widget.form.maxLength <= 0 ? 200 : widget.form.maxLength;
    final message = _messageController.text.trim();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 16 + bottomInset),
        child: Column(
          key: const Key('thread-post-comment-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  l10n.threadCommentTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                IconButton(
                  key: const Key('thread-post-comment-close-button'),
                  tooltip: l10n.commonClose,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('thread-post-comment-message-input'),
              controller: _messageController,
              autofocus: true,
              minLines: 2,
              maxLines: 5,
              maxLength: maxLength,
              decoration: InputDecoration(
                labelText: l10n.threadCommentContent,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('thread-post-comment-submit-button'),
                onPressed: message.isEmpty
                    ? null
                    : () {
                        Navigator.of(context).pop(
                          ThreadPostCommentDraft(
                            form: widget.form,
                            message: _messageController.text,
                          ),
                        );
                      },
                child: Text(l10n.threadCommentSubmit),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
