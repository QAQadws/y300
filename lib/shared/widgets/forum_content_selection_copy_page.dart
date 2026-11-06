import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:y300/app/navigation/forum_selected_link_policy.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/core/clipboard/clipboard_text_writer.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart'
    show
        ForumBodyFlowSelectionScope,
        ForumBodyFlowSelectionScopeState,
        ForumBodySelectionCopyCursor,
        ForumBodySourceRange,
        ForumBodyTextPageSession;
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/forum_native_surface.dart';
import 'package:y300/shared/widgets/transient_feedback.dart';

/// The caller owns navigation/failure feedback and checks `isCurrent` before
/// applying asynchronous results to this selection's source page.
typedef ForumSelectionLinkOpener = Future<void> Function(
  String url,
  bool Function() isCurrent,
);

typedef ForumSelectionRangeAction = ({
  String label,
  bool Function(ForumBodySourceRange) apply,
});

class ForumContentSelectionCopyPage extends StatelessWidget {
  const ForumContentSelectionCopyPage({
    super.key,
    required this.title,
    this.bodyKey,
    required this.child,
    this.resolveForumLink,
    this.onOpenForumLink,
    this.clipboardTextWriter,
    this.isCurrent,
    this.childOwnsSelection = false,
  }) : assert((resolveForumLink == null) == (onOpenForumLink == null));

  final String title;
  final Key? bodyKey;
  final Widget child;

  /// Synchronous local eligibility, including proof that the source URL is
  /// complete. Return its original text, or null to retain the default menu.
  final String? Function(String selectedText)? resolveForumLink;
  final ForumSelectionLinkOpener? onOpenForumLink;
  final ClipboardTextWriter? clipboardTextWriter;
  final bool Function()? isCurrent;
  final bool childOwnsSelection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final native = theme.y300NativeContent;
    final body = ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
      children: [
        Container(
          key: bodyKey,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: native.card,
            borderRadius: BorderRadius.circular(12),
            boxShadow: ForumNativeSurfaceShadows.card(native.stateLayer),
          ),
          child: DefaultTextStyle.merge(
            style: theme.textTheme.bodyMedium?.copyWith(
              color: native.body,
              height: 1.5,
            ),
            child: child,
          ),
        ),
      ],
    );
    return Scaffold(
      backgroundColor: native.background,
      appBar: AppBar(centerTitle: false, title: Text(title)),
      body: childOwnsSelection
          ? body
          : ForumContentSelectionRegion(
              resolveForumLink: resolveForumLink,
              onOpenForumLink: onOpenForumLink,
              clipboardTextWriter: clipboardTextWriter,
              isCurrent: isCurrent,
              child: body,
            ),
    );
  }
}

/// Platform selection controls with the App clipboard and current-source guard.
class ForumContentSelectionRegion extends StatefulWidget {
  const ForumContentSelectionRegion({
    super.key,
    required this.child,
    this.clipboardTextWriter,
    this.resolveForumLink,
    this.onOpenForumLink,
    this.isCurrent,
    this.selectionIdentity,
    this.readSelectionAuthority,
    this.onSelectionStarted,
    this.rangeAction,
    this.wholeBodySelection,
    this.nativeFlow = false,
  }) : assert(rangeAction == null || nativeFlow),
       assert(wholeBodySelection == null || nativeFlow),
       assert(
         nativeFlow
             ? resolveForumLink == null
             : (resolveForumLink == null) == (onOpenForumLink == null),
       );

  final Widget child;
  final ClipboardTextWriter? clipboardTextWriter;
  final String? Function(String selectedText)? resolveForumLink;
  final ForumSelectionLinkOpener? onOpenForumLink;
  final bool Function()? isCurrent;
  final Object? selectionIdentity;

  /// Current delivery identity when the same source can reflow independently.
  final Object? Function()? readSelectionAuthority;
  final VoidCallback? onSelectionStarted;
  final ForumSelectionRangeAction? rangeAction;
  final ({ForumBodyTextPageSession session, bool complete})? wholeBodySelection;
  final bool nativeFlow;

  @override
  State<ForumContentSelectionRegion> createState() =>
      _ForumContentSelectionRegionState();
}

class _ForumContentSelectionRegionState
    extends State<ForumContentSelectionRegion> {
  final _areaKey = GlobalKey<SelectionAreaState>();
  final _flowKey = GlobalKey<ForumBodyFlowSelectionScopeState>();
  final _selectionDetails = SelectionListenerNotifier();
  final _toolbarRevision = ValueNotifier<int>(0);
  String? _selectedText;
  int _selectionGeneration = 0;
  int _actionGeneration = 0;
  int? _pendingCopyGeneration;
  ForumBodySelectionCopyCursor? _wholeCopy;
  bool _refreshScheduled = false;
  bool _closingForOpen = false;

  bool get _canInteract =>
      mounted &&
      (widget.isCurrent?.call() ?? true) &&
      ModalRoute.of(context)?.isCurrent != false;

  String? get _liveText =>
      widget.nativeFlow ? _flowKey.currentState?.selectedText : _selectedText;

  ({ForumBodyTextPageSession session, bool complete})? get _selectedWholeBody =>
      _flowKey.currentState?.isWholeBodySelected == true
      ? widget.wholeBodySelection
      : null;

  String? _resolveLink(String text) {
    if (!widget.nativeFlow) return widget.resolveForumLink?.call(text);
    if (widget.onOpenForumLink == null) return null;
    final whole = _selectedWholeBody;
    if (whole != null) {
      final prefix = whole.session.snapshot;
      // A virtualized Select All may include other URLs outside the live
      // selection. Only offer link navigation when the full slice is present.
      if (!whole.complete ||
          prefix.length != 1 ||
          prefix.single.tableFrames.isNotEmpty) {
        return null;
      }
    }
    final occurrence = const ForumSelectedLinkPolicy().resolveOccurrence(text);
    return occurrence != null &&
            _flowKey.currentState?.confirmsSelectedLink(occurrence) == true
        ? occurrence.text
        : null;
  }

  @override
  void initState() {
    super.initState();
    _selectionDetails.addListener(_rangeChanged);
  }

  @override
  void didUpdateWidget(ForumContentSelectionRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionIdentity != widget.selectionIdentity) {
      _selectedText = null;
      _invalidateSelection();
      final identity = widget.selectionIdentity;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.selectionIdentity == identity) {
          // Replacing native deliveries already retires their selectables.
          // Clearing through a registrar while its children are retiring
          // can mutate Flutter's dispatch list during iteration.
          _areaKey.currentState?.selectableRegion.hideToolbar();
        }
      });
    }
    if (oldWidget.resolveForumLink != widget.resolveForumLink ||
        oldWidget.onOpenForumLink != widget.onOpenForumLink ||
        oldWidget.rangeAction != widget.rangeAction ||
        oldWidget.wholeBodySelection != widget.wholeBodySelection ||
        oldWidget.clipboardTextWriter != widget.clipboardTextWriter) {
      _invalidateSelection();
    }
  }

  @override
  void dispose() {
    _wholeCopy?.close();
    _selectionDetails.removeListener(_rangeChanged);
    _selectionDetails.dispose();
    _toolbarRevision.dispose();
    super.dispose();
  }

  // The delegate may still be removing old geometry during its notification.
  // Retire commands immediately without querying its intermediate range.
  void _rangeChanged() => _invalidateSelection();

  void _textChanged(SelectedContent? content) {
    if (_selectedText == content?.plainText) return;
    _selectedText = content?.plainText;
    if (_selectedText?.isNotEmpty == true) widget.onSelectionStarted?.call();
    _invalidateSelection();
  }

  void _invalidateSelection() {
    _wholeCopy?.close();
    _wholeCopy = null;
    _selectionGeneration++;
    if (!_closingForOpen) _actionGeneration++;
    // Selection notifications can arrive during layout. Retire old callbacks
    // immediately, but rebuild the toolbar overlay after the current frame.
    if (_refreshScheduled) return;
    _refreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshScheduled = false;
      if (mounted) _toolbarRevision.value++;
    });
  }

  bool _menuCurrent(int generation, SelectableRegionState region) =>
      _canInteract && region.mounted && generation == _selectionGeneration;

  Widget _buildToolbar(BuildContext context, SelectableRegionState region) =>
      ValueListenableBuilder<int>(
        valueListenable: _toolbarRevision,
        builder: (context, _, _) {
          final selectedText = _liveText;
          if (!_canInteract ||
              (widget.selectionIdentity != null && selectedText == null)) {
            return const SizedBox.shrink();
          }
          final generation = _selectionGeneration;
          final selectedUrl = selectedText == null
              ? null
              : _resolveLink(selectedText);
          final items = region.contextMenuButtonItems.map((item) {
            if (item.type != ContextMenuButtonType.copy ||
                widget.clipboardTextWriter == null) {
              return item;
            }
            if (_selectedWholeBody?.complete == false) {
              return const ContextMenuButtonItem(
                type: ContextMenuButtonType.copy,
                onPressed: null,
              );
            }
            return item.copyWith(
              onPressed: () => unawaited(_copy(region, generation)),
            );
          }).toList();
          if (selectedUrl != null) {
            items.add(
              ContextMenuButtonItem(
                label: AppLocalizations.of(context).selectionOpenForumLink,
                onPressed: () => unawaited(
                  _open(region, generation, selectedText!, selectedUrl),
                ),
              ),
            );
          }
          final action = widget.rangeAction;
          final range = action == null
              ? null
              : _flowKey.currentState?.selectedSourceRange;
          if (action != null && range != null) {
            final authority = widget.readSelectionAuthority?.call();
            items.add(
              ContextMenuButtonItem(
                label: action.label,
                onPressed: () {
                  if (_menuCurrent(generation, region) &&
                      action == widget.rangeAction &&
                      widget.readSelectionAuthority?.call() == authority &&
                      _flowKey.currentState?.selectedSourceRange == range &&
                      action.apply(range)) {
                    region.hideToolbar();
                    region.clearSelection();
                  }
                },
              ),
            );
          }
          return AdaptiveTextSelectionToolbar.buttonItems(
            anchors: region.contextMenuAnchors,
            buttonItems: items,
          );
        },
      );

  Future<void> _copy(
    SelectableRegionState region,
    int generation, {
    bool fromToolbar = true,
  }) async {
    final whole = _selectedWholeBody;
    final liveText = _liveText;
    final writer = widget.clipboardTextWriter;
    if (!_menuCurrent(generation, region) ||
        (whole == null && (liveText == null || liveText.isEmpty)) ||
        whole?.complete == false ||
        writer == null ||
        _pendingCopyGeneration == generation) {
      return;
    }
    _pendingCopyGeneration = generation;
    bool current() =>
        _menuCurrent(generation, region) && _selectedWholeBody == whole;
    try {
      final text = whole == null
          ? liveText
          : await _readWholeBody(whole.session, current);
      if (!current()) return;
      if (text == null || text.isEmpty) {
        if (whole != null) _showWholeCopyFailure();
        return;
      }
      await writer.writeText(text);
      if (!fromToolbar || !current()) return;
      // Match Flutter's public toolbar behavior without invoking its default
      // Copy callback, which would write to the clipboard a second time.
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
        case TargetPlatform.fuchsia:
          region.clearSelection();
        case TargetPlatform.iOS:
          region.hideToolbar(false);
        case TargetPlatform.linux:
        case TargetPlatform.macOS:
        case TargetPlatform.windows:
          region.hideToolbar();
      }
    } on Object {
      // Keep the selection and menu available for an explicit retry. Failed
      // writes never produce self-copy evidence in the injected adapter.
      if (whole != null && current()) _showWholeCopyFailure();
    } finally {
      if (_pendingCopyGeneration == generation) _pendingCopyGeneration = null;
    }
  }

  Future<String?> _readWholeBody(
    ForumBodyTextPageSession session,
    bool Function() current,
  ) async {
    final cursor = session.openWholeBodyCopy(
      maxCodeUnits:
          session.limits.maxTextCodeUnits + session.limits.maxFragments,
      maxWork: 8 * session.limits.maxParagraphs,
    );
    if (cursor == null) return null;
    _wholeCopy = cursor;
    try {
      while (current() && !cursor.isDone) {
        final clock = Stopwatch()..start();
        do {
          cursor.advance(maxWork: 16);
        } while (!cursor.isDone && clock.elapsedMicroseconds < 2500);
        if (!cursor.isDone) await WidgetsBinding.instance.endOfFrame;
      }
      return cursor.text;
    } finally {
      cursor.close();
      if (identical(_wholeCopy, cursor)) _wholeCopy = null;
    }
  }

  void _showWholeCopyFailure() => showTransientSnackBar(
    context,
    AppLocalizations.of(context).selectionCopyAllFailed,
  );

  Future<void> _open(
    SelectableRegionState region,
    int generation,
    String selectedText,
    String url,
  ) async {
    final open = widget.onOpenForumLink;
    if (!_menuCurrent(generation, region) ||
        _liveText != selectedText ||
        _resolveLink(selectedText) != url ||
        open == null) {
      return;
    }
    final action = ++_actionGeneration;
    final authority = widget.readSelectionAuthority?.call();
    // Clearing the selection is part of this committed action; only a later
    // user selection change should cancel its pending navigation.
    _closingForOpen = true;
    try {
      region.hideToolbar();
      region.clearSelection();
    } finally {
      _closingForOpen = false;
    }
    await open(
      url,
      () =>
          _canInteract &&
          action == _actionGeneration &&
          widget.readSelectionAuthority?.call() == authority,
    );
  }

  @override
  Widget build(BuildContext context) {
    final customMenu =
        widget.onOpenForumLink != null ||
        widget.clipboardTextWriter != null ||
        widget.rangeAction != null;
    final child = widget.nativeFlow
        ? ForumBodyFlowSelectionScope(key: _flowKey, child: widget.child)
        : widget.child;
    final region = SelectionArea(
      key: _areaKey,
      onSelectionChanged: customMenu ? _textChanged : null,
      contextMenuBuilder: customMenu
          ? _buildToolbar
          : (context, region) => AdaptiveTextSelectionToolbar.selectableRegion(
              selectableRegionState: region,
            ),
      child: customMenu
          ? SelectionListener(
              selectionNotifier: _selectionDetails,
              child: child,
            )
          : child,
    );
    return Actions(
      actions: {
        if (widget.clipboardTextWriter != null)
          CopySelectionTextIntent: CallbackAction<CopySelectionTextIntent>(
            onInvoke: (_) {
              final area = _areaKey.currentState;
              if (area != null) {
                unawaited(
                  _copy(
                    area.selectableRegion,
                    _selectionGeneration,
                    fromToolbar: false,
                  ),
                );
              }
              return null;
            },
          ),
      },
      child: region,
    );
  }
}
