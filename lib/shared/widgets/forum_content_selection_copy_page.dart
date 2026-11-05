import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/core/clipboard/clipboard_text_writer.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/forum_native_surface.dart';

/// The caller owns navigation/failure feedback and checks `isCurrent` before
/// applying asynchronous results to this selection's source page.
typedef ForumSelectionLinkOpener = Future<void> Function(
  String url,
  bool Function() isCurrent,
);

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final native = theme.y300NativeContent;
    return Scaffold(
      backgroundColor: native.background,
      appBar: AppBar(centerTitle: false, title: Text(title)),
      body: ForumContentSelectionRegion(
        resolveForumLink: resolveForumLink,
        onOpenForumLink: onOpenForumLink,
        clipboardTextWriter: clipboardTextWriter,
        isCurrent: isCurrent,
        child: ListView(
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
        ),
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
    this.onSelectionStarted,
  }) : assert((resolveForumLink == null) == (onOpenForumLink == null));

  final Widget child;
  final ClipboardTextWriter? clipboardTextWriter;
  final String? Function(String selectedText)? resolveForumLink;
  final ForumSelectionLinkOpener? onOpenForumLink;
  final bool Function()? isCurrent;
  final Object? selectionIdentity;
  final VoidCallback? onSelectionStarted;

  @override
  State<ForumContentSelectionRegion> createState() =>
      _ForumContentSelectionRegionState();
}

class _ForumContentSelectionRegionState
    extends State<ForumContentSelectionRegion> {
  final _areaKey = GlobalKey<SelectionAreaState>();
  final _selectionDetails = SelectionListenerNotifier();
  final _toolbarRevision = ValueNotifier<int>(0);
  String? _selectedText;
  int _selectionGeneration = 0;
  int _actionGeneration = 0;
  int? _pendingCopyGeneration;
  bool _refreshScheduled = false;
  bool _closingForOpen = false;

  bool get _canInteract =>
      mounted &&
      (widget.isCurrent?.call() ?? true) &&
      ModalRoute.of(context)?.isCurrent != false;

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
        oldWidget.clipboardTextWriter != widget.clipboardTextWriter) {
      _invalidateSelection();
    }
  }

  @override
  void dispose() {
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
          if (!_canInteract ||
              (widget.selectionIdentity != null && _selectedText == null)) {
            return const SizedBox.shrink();
          }
          final generation = _selectionGeneration;
          final selectedText = _selectedText;
          final selectedUrl = selectedText == null || !_canInteract
              ? null
              : widget.resolveForumLink?.call(selectedText);
          final items = region.contextMenuButtonItems.map((item) {
            if (item.type != ContextMenuButtonType.copy ||
                widget.clipboardTextWriter == null) {
              return item;
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
    final text = _selectedText;
    final writer = widget.clipboardTextWriter;
    if (!_menuCurrent(generation, region) ||
        text == null ||
        text.isEmpty ||
        writer == null ||
        _pendingCopyGeneration == generation) {
      return;
    }
    _pendingCopyGeneration = generation;
    try {
      await writer.writeText(text);
      if (!fromToolbar || !_menuCurrent(generation, region)) return;
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
    } finally {
      if (_pendingCopyGeneration == generation) _pendingCopyGeneration = null;
    }
  }

  Future<void> _open(
    SelectableRegionState region,
    int generation,
    String selectedText,
    String url,
  ) async {
    final open = widget.onOpenForumLink;
    if (!_menuCurrent(generation, region) ||
        _selectedText != selectedText ||
        widget.resolveForumLink?.call(selectedText) != url ||
        open == null) {
      return;
    }
    final action = ++_actionGeneration;
    // Clearing the selection is part of this committed action; only a later
    // user selection change should cancel its pending navigation.
    _closingForOpen = true;
    try {
      region.hideToolbar();
      region.clearSelection();
    } finally {
      _closingForOpen = false;
    }
    await open(url, () => _canInteract && action == _actionGeneration);
  }

  @override
  Widget build(BuildContext context) {
    final customMenu =
        widget.onOpenForumLink != null || widget.clipboardTextWriter != null;
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
              child: widget.child,
            )
          : widget.child,
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
