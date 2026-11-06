import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:y300/core/clipboard/clipboard_text_writer.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_tap_zones.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/forum_content_selection_copy_page.dart';

import '../models/novel_reader_logical_selection_source.dart';
import '../services/novel_reader_native_work_scheduler.dart';
import '../services/novel_reader_pagination_cancellation.dart';

/// Retains source endpoints while Flutter owns the live selection and handles.
final class NovelReaderLogicalSelectionRegion extends StatefulWidget {
  const NovelReaderLogicalSelectionRegion({
    super.key,
    required this.surfaceIdentity,
    required this.readSource,
    required this.activity,
    required this.writer,
    required this.onFeedback,
    required this.buildSelection,
    required this.child,
  });

  final Object surfaceIdentity;
  final NovelReaderLogicalSelectionSource? Function() readSource;
  final ValueListenable<bool> activity;
  final ClipboardTextWriter writer;
  final ValueChanged<String> onFeedback;
  final Widget Function(ForumSelectionRangeAction, Widget) buildSelection;
  final Widget child;

  static ForumBodySourceRange? rangeFor(
    BuildContext context,
    ForumBodyTextPageSession session,
  ) {
    final mark = context
        .dependOnInheritedWidgetOfExactType<_LogicalSelectionMark>();
    return identical(mark?.session, session) ? mark?.range : null;
  }

  @override
  State<NovelReaderLogicalSelectionRegion> createState() =>
      _NovelReaderLogicalSelectionRegionState();
}

final class _NovelReaderLogicalSelectionRegionState
    extends State<NovelReaderLogicalSelectionRegion> {
  ForumBodyTextPageSession? _session;
  ForumBodySourceRange? _start, _range;
  VoidCallback? _stopListening;
  NovelReaderPaginationCancellationToken? _copy;

  @override
  void initState() {
    super.initState();
    widget.activity.addListener(_activityChanged);
  }

  @override
  void didUpdateWidget(NovelReaderLogicalSelectionRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activity != widget.activity) {
      oldWidget.activity.removeListener(_activityChanged);
      widget.activity.addListener(_activityChanged);
      _activityChanged();
    }
    final current = widget.readSource()?.session;
    if (oldWidget.surfaceIdentity != widget.surfaceIdentity ||
        (current != null &&
            _session != null &&
            !identical(current, _session))) {
      _release();
    }
  }

  void _activityChanged() {
    if (!widget.activity.value) _cancelCopy();
  }

  void _cancelCopy() {
    _copy?.cancel();
    _copy = null;
  }

  void _release() {
    _stopListening?.call();
    _stopListening = null;
    _cancelCopy();
    _session = null;
    _start = _range = null;
  }

  void _retire() {
    _release();
    // A child host can retire its layout during build. Update this ancestor
    // after the frame while revoking copy authority immediately.
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
    binding.ensureVisualUpdate();
  }

  bool _apply(ForumBodySourceRange selected) {
    final source = widget.readSource();
    if (!widget.activity.value ||
        source == null ||
        source.session.snapshot.identity != selected.identity) {
      return false;
    }
    setState(() {
      if (!identical(_session, source.session)) _release();
      _cancelCopy();
      final start = _start;
      if (start == null) {
        _session = source.session;
        _start = selected;
        _stopListening = source.onRetired(_retire);
      } else {
        _range = ForumBodySourceRange(
          selected.identity,
          math.min(start.startRune, selected.startRune),
          math.max(start.endRune, selected.endRune),
        );
      }
    });
    return true;
  }

  bool _canUse(ForumBodyTextPageSession session) =>
      widget.activity.value && identical(widget.readSource()?.session, session);

  Future<void> _copyRange(
    ForumBodyTextPageSession session,
    ForumBodySourceRange range,
  ) async {
    if (!mounted ||
        !identical(_session, session) ||
        !identical(_range, range) ||
        _copy != null ||
        !_canUse(session)) {
      return;
    }
    final token = NovelReaderPaginationCancellationToken();
    setState(() => _copy = token);
    bool current() => mounted && identical(_copy, token) && _canUse(session);
    final writer = widget.writer;
    ForumBodySelectionCopyCursor? cursor;
    var copied = false;
    var unavailable = false;
    try {
      cursor = session.openSelectionCopy(range);
      const scheduler = NovelReaderNativeWorkScheduler();
      while (current() && !cursor.isDone) {
        final clock = Stopwatch()..start();
        do {
          cursor.advance(maxWork: 16);
        } while (!cursor.isDone && clock.elapsedMicroseconds < 2500);
        if (!cursor.isDone) await scheduler.nextFrame(token);
      }
      final text = cursor.text;
      cursor.close();
      unavailable = text == null;
      if (current() && text != null) {
        await writer.writeText(text);
        copied = true;
      }
    } on Object {
      // A current selection stays available for an explicit retry.
    } finally {
      cursor?.close();
      if (mounted && current()) {
        final l10n = AppLocalizations.of(context);
        setState(() {
          if (copied) _release();
          _copy = null;
        });
        widget.onFeedback(switch ((copied, unavailable)) {
          (true, _) => l10n.novelSelectionCopied,
          (_, true) => l10n.novelSelectionCopyUnavailable,
          _ => l10n.novelSelectionCopyFailed,
        });
      } else if (identical(_copy, token)) {
        _copy = null;
      }
      token.cancel();
    }
  }

  @override
  void dispose() {
    widget.activity.removeListener(_activityChanged);
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final action = (
      label: _start == null ? l10n.novelSelectionStart : l10n.novelSelectionEnd,
      apply: _apply,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        _LogicalSelectionMark(
          session: _session,
          range: _range ?? _start,
          child: widget.buildSelection(action, widget.child),
        ),
        if (_start != null)
          Positioned(
            bottom: 8,
            left: 8,
            right: 8,
            child: ValueListenableBuilder<bool>(
              valueListenable: widget.activity,
              builder: (context, active, _) {
                final session = _session;
                return active && session != null && _canUse(session)
                    ? _controls(l10n, session, _start!, _range)
                    : const SizedBox.shrink();
              },
            ),
          ),
      ],
    );
  }

  Widget _controls(
    AppLocalizations l10n,
    ForumBodyTextPageSession session,
    ForumBodySourceRange start,
    ForumBodySourceRange? range,
  ) => SafeArea(
    top: false,
    child: Align(
      alignment: Alignment.bottomCenter,
      child: ReaderOwnedTapRegion(
        child: Material(
          key: const Key('novel-logical-selection-controls'),
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          shape: const StadiumBorder(),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.only(left: 12, right: 4),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (range == null)
                  Text(l10n.novelSelectionChooseEnd)
                else
                  TextButton.icon(
                    onPressed: _copy == null
                        ? () => _copyRange(session, range)
                        : null,
                    icon: const Icon(Icons.copy),
                    label: Text(l10n.novelSelectionCopy),
                  ),
                IconButton(
                  tooltip: l10n.novelSelectionClear,
                  onPressed: () {
                    if (mounted &&
                        identical(_session, session) &&
                        identical(_start, start)) {
                      setState(_release);
                    }
                  },
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

final class _LogicalSelectionMark extends InheritedWidget {
  const _LogicalSelectionMark({
    required this.session,
    required this.range,
    required super.child,
  });

  final ForumBodyTextPageSession? session;
  final ForumBodySourceRange? range;

  @override
  bool updateShouldNotify(_LogicalSelectionMark oldWidget) =>
      !identical(session, oldWidget.session) || range != oldWidget.range;
}
