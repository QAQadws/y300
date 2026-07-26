import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_insertion_models.dart';
import 'package:y300/features/composer_shared/domain/models/sticker_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_attach_bbcode_grammar.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_attach_token_promoter.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_bbcode_codec.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_embeds.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_size_mapping.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_selection_adapter.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_typing_style_snapshot.dart';
import 'package:y300/features/composer_shared/presentation/bbcode/forum_bbcode_renderer.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_bbcode_color_picker_sheet.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_link_sheet.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_sticker_group_panel.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_sticker_image.dart';
import 'package:y300/shared/widgets/forum_content_spacing.dart';

Widget _defaultQuillAttachImageBuilder(File file, Key key) {
  return Image.file(
    file,
    key: key,
    fit: BoxFit.contain,
    errorBuilder: (_, _, _) => const SizedBox.shrink(),
  );
}

bool _defaultQuillAttachFileExists(File file) {
  return file.existsSync();
}

enum ComposerQuillToolPanel { format, align, sticker }

class ComposerQuillPrototypeEditor extends StatelessWidget {
  const ComposerQuillPrototypeEditor({
    super.key,
    this.controller,
    this.initialBbCode,
    this.onBbCodeChanged,
    this.onImagePressed,
    this.messageRevision = 0,
    this.lastMessageMutation,
    this.stickers = const <StickerItem>[],
    this.stickerGroups = const <StickerGroup>[],
    this.initialStickerGroupId,
    this.onStickerGroupChanged,
    this.imageAttachments = const <ComposerImageAttachment>[],
    this.attachImageBuilder = _defaultQuillAttachImageBuilder,
    this.attachFileExists = _defaultQuillAttachFileExists,
    this.keyPrefix = 'composer-quill-prototype',
    this.minHeight = 220,
    this.expand = false,
    this.contentPadding = const EdgeInsets.fromLTRB(
      ForumContentSpacing.composerQuillSurfaceHorizontal,
      ForumContentSpacing.composerBodyTop,
      ForumContentSpacing.composerQuillSurfaceHorizontal,
      ForumContentSpacing.composerBodyBottom,
    ),
  });

  final QuillController? controller;
  final String? initialBbCode;
  final ValueChanged<String>? onBbCodeChanged;
  final ComposerImageInsertCallback? onImagePressed;
  final int messageRevision;
  final ComposerTextMutation? lastMessageMutation;
  final List<StickerItem> stickers;
  final List<StickerGroup> stickerGroups;
  final String? initialStickerGroupId;
  final ValueChanged<String>? onStickerGroupChanged;
  final List<ComposerImageAttachment> imageAttachments;
  final ForumAttachPreviewImageBuilder? attachImageBuilder;
  final ForumAttachPreviewFileExists? attachFileExists;
  final String keyPrefix;
  final double minHeight;
  final bool expand;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    return ComposerQuillEditorSurface(
      controller: controller,
      initialBbCode: initialBbCode,
      onBbCodeChanged: onBbCodeChanged,
      onImagePressed: onImagePressed,
      messageRevision: messageRevision,
      lastMessageMutation: lastMessageMutation,
      stickers: stickers,
      stickerGroups: stickerGroups,
      initialStickerGroupId: initialStickerGroupId,
      onStickerGroupChanged: onStickerGroupChanged,
      imageAttachments: imageAttachments,
      attachImageBuilder: attachImageBuilder,
      attachFileExists: attachFileExists,
      keyPrefix: keyPrefix,
      minHeight: minHeight,
      expand: expand,
      contentPadding: contentPadding,
    );
  }
}

class ComposerQuillEditorSurface extends StatefulWidget {
  const ComposerQuillEditorSurface({
    super.key,
    this.controller,
    this.bbCode,
    this.initialBbCode,
    this.onBbCodeChanged,
    this.onImagePressed,
    this.messageRevision = 0,
    this.lastMessageMutation,
    this.stickers = const <StickerItem>[],
    this.stickerGroups = const <StickerGroup>[],
    this.initialStickerGroupId,
    this.onStickerGroupChanged,
    this.imageAttachments = const <ComposerImageAttachment>[],
    this.attachImageBuilder = _defaultQuillAttachImageBuilder,
    this.attachFileExists = _defaultQuillAttachFileExists,
    this.keyPrefix = 'composer-quill',
    this.minHeight = 220,
    this.expand = false,
    this.enabled = true,
    this.hintText = '请开始输入',
    this.contentPadding = const EdgeInsets.fromLTRB(
      ForumContentSpacing.composerQuillSurfaceHorizontal,
      ForumContentSpacing.composerBodyTop,
      ForumContentSpacing.composerQuillSurfaceHorizontal,
      ForumContentSpacing.composerBodyBottom,
    ),
  });

  final QuillController? controller;
  final String? bbCode;
  final String? initialBbCode;
  final ValueChanged<String>? onBbCodeChanged;
  final ComposerImageInsertCallback? onImagePressed;
  final int messageRevision;
  final ComposerTextMutation? lastMessageMutation;
  final List<StickerItem> stickers;
  final List<StickerGroup> stickerGroups;
  final String? initialStickerGroupId;
  final ValueChanged<String>? onStickerGroupChanged;
  final List<ComposerImageAttachment> imageAttachments;
  final ForumAttachPreviewImageBuilder? attachImageBuilder;
  final ForumAttachPreviewFileExists? attachFileExists;
  final String keyPrefix;
  final double minHeight;
  final bool expand;
  final bool enabled;
  final String hintText;
  final EdgeInsetsGeometry contentPadding;

  @override
  State<ComposerQuillEditorSurface> createState() {
    return _ComposerQuillEditorSurfaceState();
  }
}

class _ComposerQuillEditorSurfaceState
    extends State<ComposerQuillEditorSurface> {
  static const _codec = ComposerQuillBbCodeCodec();
  static const _selectionAdapter = ComposerQuillSelectionAdapter();
  static const _attachTokenPromoter = ComposerQuillAttachTokenPromoter();

  late final QuillController _controller;
  late final bool _ownsController;
  late final FocusNode _focusNode;
  late final ScrollController _scrollController;
  String _bbCodeText = '';
  bool _isApplyingExternalBbCode = false;
  bool _isPromotingAttachTokens = false;
  bool _hasScheduledAttachTokenPromotion = false;
  String? _ignoredExternalDocumentEncoding;
  ComposerQuillToolPanel? _activePanel;
  double _lastKeyboardHeight = 0;
  double? _pendingKeyboardToolbarOffset;
  ComposerQuillTypingStyleSnapshot? _pendingTypingStyleSnapshot;
  int _editorTapGeneration = 0;
  bool _isWaitingForKeyboardDismissForPanel = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      final document = _initialBbCode().isEmpty
          ? Document()
          : _codec.decodeDocument(_initialBbCode());
      final offset = (document.length - 1).clamp(0, document.length).toInt();
      _controller = QuillController(
        document: document,
        selection: TextSelection.collapsed(offset: offset),
      );
    }
    _focusNode = FocusNode();
    _focusNode.addListener(_handleEditorFocusChanged);
    _scrollController = ScrollController();
    _controller.addListener(_handleDocumentChanged);
    _bbCodeText = widget.bbCode ?? _codec.encodeDocument(_controller.document);
    // 外部直接塞进来的文档也可能带着字面 attach 代码。
    _scheduleAttachTokenPromotion();
  }

  String _initialBbCode() {
    return widget.bbCode ?? widget.initialBbCode ?? '';
  }

  @override
  void dispose() {
    _controller.removeListener(_handleDocumentChanged);
    if (_ownsController) {
      _controller.dispose();
    }
    _focusNode.removeListener(_handleEditorFocusChanged);
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
    if (keyboardHeight > 0) {
      _lastKeyboardHeight = keyboardHeight;
      if (_pendingKeyboardToolbarOffset != null) {
        _pendingKeyboardToolbarOffset = null;
      }
    }
    final visiblePanel =
        _isWaitingForKeyboardDismissForPanel && keyboardHeight > 0
        ? null
        : _activePanel;
    final panelHeight = visiblePanel == null ? 0.0 : _toolPanelHeight(context);
    final toolbarOffset = visiblePanel == null
        ? keyboardHeight > 0
              ? keyboardHeight
              : _pendingKeyboardToolbarOffset ?? 0.0
        : panelHeight;
    final toolbarHeight = _toolbarHeight(context);
    final bottomSpacer = toolbarOffset + toolbarHeight;
    final resolvedContentPadding = widget.contentPadding.resolve(
      Directionality.of(context),
    );
    final editor = ConstrainedBox(
      constraints: BoxConstraints(minHeight: widget.minHeight),
      child: QuillEditor.basic(
        key: Key('${widget.keyPrefix}-editor'),
        controller: _controller,
        focusNode: _focusNode,
        scrollController: _scrollController,
        config: QuillEditorConfig(
          placeholder: widget.hintText,
          padding: const EdgeInsets.all(12),
          onTapDown: _handleEditorTapDown,
          onTapUp: _handleEditorTapUp,
          embedBuilders: [
            _StickerEmbedBuilder(stickers: _stickerLookupItems()),
            _AttachEmbedBuilder(
              imageAttachments: _mergedImageAttachments(),
              attachImageBuilder:
                  widget.attachImageBuilder ?? _defaultQuillAttachImageBuilder,
              attachFileExists:
                  widget.attachFileExists ?? _defaultQuillAttachFileExists,
            ),
          ],
        ),
      ),
    );
    return SizedBox(
      height: widget.expand ? double.infinity : null,
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                resolvedContentPadding.left,
                resolvedContentPadding.top,
                resolvedContentPadding.right,
                resolvedContentPadding.bottom + bottomSpacer,
              ),
              child: widget.expand
                  ? editor
                  : SingleChildScrollView(child: editor),
            ),
          ),
          if (visiblePanel != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: panelHeight,
              child: _ToolPanelFrame(
                key: Key('${widget.keyPrefix}-tool-panel'),
                child: _buildToolPanel(context),
              ),
            ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            left: 0,
            right: 0,
            bottom: toolbarOffset,
            child: _PrototypeToolbar(
              keyPrefix: widget.keyPrefix,
              enabled: widget.enabled,
              onFormatPressed: () =>
                  _toggleToolPanel(ComposerQuillToolPanel.format),
              onAlignPressed: () =>
                  _toggleToolPanel(ComposerQuillToolPanel.align),
              onQuotePressed: _toggleQuote,
              onLinkPressed: () => _openLinkSheet(context),
              onStickerPressed: () =>
                  _toggleToolPanel(ComposerQuillToolPanel.sticker),
              onImagePressed: () => _handleImagePressed(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolPanel(BuildContext context) {
    return switch (_activePanel) {
      ComposerQuillToolPanel.format => _FormatSheet(
        keyPrefix: widget.keyPrefix,
        controller: _controller,
        embedded: true,
        onTypingStyleChanged: _captureTypingStyleSnapshot,
      ),
      ComposerQuillToolPanel.align => _AlignPanel(
        keyPrefix: widget.keyPrefix,
        onSelected: _applyAlign,
      ),
      ComposerQuillToolPanel.sticker => ComposerStickerGroupPanel(
        keyPrefix: widget.keyPrefix,
        groups: _visibleStickerGroups(),
        initialGroupId: widget.initialStickerGroupId,
        onGroupChanged: widget.onStickerGroupChanged ?? (_) {},
        onSelected: _insertStickerItem,
      ),
      null => const SizedBox.shrink(),
    };
  }

  List<StickerGroup> _visibleStickerGroups() {
    final groups = widget.stickerGroups
        .where((group) => group.stickers.isNotEmpty)
        .toList(growable: false);
    if (groups.isNotEmpty) {
      return groups;
    }
    return [
      if (widget.stickers.isNotEmpty)
        StickerGroup(id: 'all', title: '表情', stickers: widget.stickers),
    ];
  }

  List<StickerItem> _stickerLookupItems() {
    if (widget.stickers.isNotEmpty) {
      return widget.stickers;
    }
    return [
      for (final group in widget.stickerGroups)
        for (final sticker in group.stickers) sticker,
    ];
  }

  List<ComposerImageAttachment> _mergedImageAttachments() {
    return widget.imageAttachments;
  }

  double _toolPanelHeight(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final fallback = screenHeight * 0.32;
    if (_lastKeyboardHeight > 0) {
      return _lastKeyboardHeight.clamp(240.0, screenHeight * 0.55).toDouble();
    }
    return fallback.clamp(240.0, 360.0).toDouble();
  }

  double _toolbarHeight(BuildContext context) {
    return 56 + MediaQuery.paddingOf(context).bottom;
  }

  bool _handleEditorTapDown(
    TapDownDetails details,
    TextPosition Function(Offset offset) getPositionForOffset,
  ) {
    _editorTapGeneration += 1;
    _closeToolPanelForEditorInput();
    return false;
  }

  bool _handleEditorTapUp(
    TapUpDetails details,
    TextPosition Function(Offset offset) getPositionForOffset,
  ) {
    final generation = _editorTapGeneration;
    final snapshot = _pendingTypingStyleSnapshot;
    if (snapshot == null) {
      return false;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _editorTapGeneration) {
        return;
      }
      final selection = _controller.selection;
      final documentEnd = (_controller.document.length - 1).clamp(
        0,
        _controller.document.length,
      );
      if (selection.isCollapsed && selection.extentOffset == documentEnd) {
        snapshot.restore(_controller);
      }
      _pendingTypingStyleSnapshot = null;
    });
    return false;
  }

  void _handleEditorFocusChanged() {
    if (!_focusNode.hasFocus || _activePanel == null) {
      return;
    }
    _closeToolPanelForEditorInput();
  }

  void _captureTypingStyleSnapshot() {
    _pendingTypingStyleSnapshot = _controller.selection.isCollapsed
        ? ComposerQuillTypingStyleSnapshot.capture(_controller)
        : null;
  }

  void _restoreTypingStyleSnapshot() {
    final snapshot = _pendingTypingStyleSnapshot;
    _pendingTypingStyleSnapshot = null;
    snapshot?.restore(_controller);
  }

  void _toggleToolPanel(ComposerQuillToolPanel panel) {
    if (!widget.enabled) {
      return;
    }
    if (_activePanel == panel) {
      final panelHeight = _toolPanelHeight(context);
      setState(() {
        _activePanel = null;
        _isWaitingForKeyboardDismissForPanel = false;
        _pendingKeyboardToolbarOffset = panelHeight;
      });
      _restoreTypingStyleSnapshot();
      _focusNode.requestFocus();
      return;
    }
    _pendingKeyboardToolbarOffset = null;
    _isWaitingForKeyboardDismissForPanel =
        MediaQuery.viewInsetsOf(context).bottom > 0;
    FocusScope.of(context).unfocus();
    setState(() {
      _activePanel = panel;
    });
  }

  void _closeToolPanelForEditorInput() {
    if (_activePanel == null) {
      return;
    }
    final panelHeight = _toolPanelHeight(context);
    setState(() {
      _activePanel = null;
      _isWaitingForKeyboardDismissForPanel = false;
      _pendingKeyboardToolbarOffset = panelHeight;
    });
  }

  void _resetTransientInteractionState() {
    _editorTapGeneration += 1;
    _pendingTypingStyleSnapshot = null;
    _pendingKeyboardToolbarOffset = null;
    _isWaitingForKeyboardDismissForPanel = false;
    if (_activePanel != null) {
      setState(() => _activePanel = null);
    }
  }

  void _applyAlign(String align) {
    if (!widget.enabled) {
      return;
    }
    final attribute = switch (align) {
      'left' => Attribute.leftAlignment,
      'center' => Attribute.centerAlignment,
      'right' => Attribute.rightAlignment,
      _ => null,
    };
    if (attribute != null) {
      _runQuillMutationWithoutKeyboard(() {
        _controller.formatSelection(attribute);
      });
    }
  }

  Future<void> _openLinkSheet(BuildContext context) async {
    if (!widget.enabled) {
      return;
    }
    _closeToolPanelForEditorInput();
    FocusScope.of(context).unfocus();
    final link = await showComposerLinkSheet(
      context: context,
      keyPrefix: widget.keyPrefix,
    );
    if (!mounted) {
      return;
    }
    if (link != null) {
      _applyLink(link);
    }
    _restoreTypingStyleSnapshot();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  void _applyLink(ComposerLinkDraft link) {
    if (!widget.enabled) {
      return;
    }
    _runQuillMutationWithoutKeyboard(() {
      final selection = _controller.selection;
      if (selection.isCollapsed) {
        final offset = selection.start;
        final restoredStyle = _controller.toggledStyle.removeAll({
          Attribute.link,
        });
        _controller.toggledStyle = const Style();
        _controller.replaceText(
          offset,
          0,
          link.label,
          TextSelection(
            baseOffset: offset,
            extentOffset: offset + link.label.length,
          ),
        );
        _controller.formatSelection(Attribute.clone(Attribute.link, link.url));
        _controller.updateSelection(
          TextSelection.collapsed(offset: offset + link.label.length),
          ChangeSource.local,
        );
        _controller.toggledStyle = restoredStyle;
      } else {
        _controller.formatSelection(Attribute.clone(Attribute.link, link.url));
      }
    });
  }

  void _insertStickerItem(StickerItem sticker) {
    if (!widget.enabled) {
      return;
    }
    _runQuillMutationWithoutKeyboard(() {
      _insertEmbed(
        composerQuillStickerEmbed(sticker.code),
        requestFocus: false,
      );
    });
  }

  void _runQuillMutationWithoutKeyboard(VoidCallback mutation) {
    _controller.skipRequestKeyboard = true;
    try {
      mutation();
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        if (_controller.skipRequestKeyboard) {
          _controller.skipRequestKeyboard = false;
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
    if (keyboardHeight > 0) {
      _lastKeyboardHeight = keyboardHeight;
      if (_activePanel != null && !_isWaitingForKeyboardDismissForPanel) {
        _activePanel = null;
        _pendingKeyboardToolbarOffset = null;
      }
    } else {
      _isWaitingForKeyboardDismissForPanel = false;
    }
  }

  @override
  void didUpdateWidget(covariant ComposerQuillEditorSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _resetTransientInteractionState();
    }
    if (oldWidget.bbCode != widget.bbCode ||
        oldWidget.lastMessageMutation != widget.lastMessageMutation) {
      if (widget.bbCode != null && widget.bbCode != _bbCodeText) {
        _resetTransientInteractionState();
      }
      _syncExternalBbCode();
    }
  }

  void _handleDocumentChanged() {
    if (_isApplyingExternalBbCode) {
      return;
    }
    // 必须在下面的编码比较之前调度：剪切图片后原样打回 attach 代码时，
    // 编码结果与剪切前完全相同，会命中 `next == _bbCodeText` 的提前返回，
    // 但文档结构确实从 embed 退化成了纯文本。
    if (!_isPromotingAttachTokens) {
      _scheduleAttachTokenPromotion();
    }
    final next = _codec.encodeDocument(_controller.document);
    final ignoredEncoding = _ignoredExternalDocumentEncoding;
    if (ignoredEncoding != null) {
      if (next == ignoredEncoding) {
        return;
      }
      _ignoredExternalDocumentEncoding = null;
    }
    if (next == _bbCodeText) {
      return;
    }
    _bbCodeText = next;
    widget.onBbCodeChanged?.call(next);
    if (mounted) {
      setState(() {});
    }
  }

  /// 把手打/粘贴出来的合法 attach 代码归一成图片节点。
  ///
  /// 放到帧末执行：避免在 Quill 的变更通知里回写文档，也让输入法组词先落定。
  void _scheduleAttachTokenPromotion() {
    if (_hasScheduledAttachTokenPromotion) {
      return;
    }
    _hasScheduledAttachTokenPromotion = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hasScheduledAttachTokenPromotion = false;
      if (!mounted) {
        return;
      }
      _promoteAttachTokens();
    });
  }

  void _promoteAttachTokens() {
    final promotion = _attachTokenPromoter.buildPromotion(
      _controller.document,
    );
    if (promotion == null) {
      return;
    }
    _isPromotingAttachTokens = true;
    try {
      // compose 会用 Delta.transformPosition 把光标从被替换掉的字面文本
      // 迁移到 embed 之后，因此传入当前 selection 即可。
      _controller.compose(
        promotion,
        _controller.selection,
        ChangeSource.local,
      );
    } finally {
      _isPromotingAttachTokens = false;
    }
  }

  void _syncExternalBbCode() {
    final external = widget.bbCode;
    if (external == null || external == _bbCodeText) {
      return;
    }
    final document = _codec.decodeDocument(external);
    TextSelection? selection;
    final mutation = widget.lastMessageMutation;
    if (mutation != null && mutation.revision == widget.messageRevision) {
      selection = _selectionAdapter.toQuillSelection(
        source: external,
        document: document,
        selection: mutation.resultSelection,
      );
    }
    _applyExternalDocument(document, external, selection: selection);
  }

  void _applyExternalDocument(
    Document document,
    String bbCode, {
    TextSelection? selection,
  }) {
    _isApplyingExternalBbCode = true;
    _ignoredExternalDocumentEncoding = _codec.encodeDocument(document);
    try {
      _controller.document = document;
      final offset = document.length <= 0 ? 0 : document.length - 1;
      _controller.updateSelection(
        selection ?? TextSelection.collapsed(offset: offset),
        ChangeSource.local,
      );
      _bbCodeText = bbCode;
    } finally {
      _isApplyingExternalBbCode = false;
    }
    setState(() {});
  }

  Future<void> _insertImage() async {
    if (!widget.enabled) {
      return;
    }
    final callback = widget.onImagePressed;
    if (callback == null) {
      return;
    }
    final sourceSelection = _selectionAdapter.toSourceSelection(
      source: _bbCodeText,
      document: _controller.document,
      selection: _controller.selection,
    );
    final anchor = sourceSelection == null
        ? null
        : ComposerInsertionAnchor(
            baseRevision: widget.messageRevision,
            selection: sourceSelection,
            mode: ComposerEditorMode.quill,
          );
    await callback(anchor);
  }

  Future<void> _handleImagePressed(BuildContext context) async {
    _closeToolPanelForEditorInput();
    await _insertImage();
    if (!mounted) {
      return;
    }
    _restoreTypingStyleSnapshot();
    _focusNode.requestFocus();
  }

  void _insertEmbed(Embeddable embed, {bool requestFocus = true}) {
    if (!widget.enabled) {
      return;
    }
    final selection = _controller.selection;
    final index = selection.start.clamp(0, _controller.document.length).toInt();
    final length = selection.end - selection.start;
    _controller.replaceText(
      index,
      length < 0 ? 0 : length,
      embed,
      TextSelection.collapsed(offset: index + 1),
    );
    if (requestFocus) {
      _focusNode.requestFocus();
    }
  }

  void _toggleQuote() {
    if (!widget.enabled) {
      return;
    }
    _closeToolPanelForEditorInput();
    final line = _currentLine();
    if (line == null) {
      return;
    }
    final isQuoted = _isLineQuoted(line);
    if (!isQuoted && _isEmptyUnquotedBoundaryAfterQuote(line)) {
      _startQuoteAfterBoundaryLine(line);
      _restoreTypingStyleSnapshot();
      _focusNode.requestFocus();
      return;
    }
    if (_controller.selection.isCollapsed) {
      _formatCurrentLineQuote(line, enable: !isQuoted);
    } else {
      _controller.formatSelection(
        isQuoted
            ? Attribute.clone(Attribute.blockQuote, null)
            : Attribute.blockQuote,
      );
    }
    _restoreTypingStyleSnapshot();
    _focusNode.requestFocus();
  }

  Line? _currentLine() {
    final length = _controller.document.length;
    final selectionStart = _controller.selection.start;
    final index = selectionStart.clamp(0, length).toInt();
    final query = _controller.document.queryChild(index);
    return query.node is Line ? query.node as Line : null;
  }

  bool _isLineQuoted(Line line) {
    return line.style.attributes[Attribute.blockQuote.key]?.value == true ||
        line.parent is Block &&
            (line.parent as Block)
                    .style
                    .attributes[Attribute.blockQuote.key]
                    ?.value ==
                true;
  }

  bool _isEmptyUnquotedBoundaryAfterQuote(Line line) {
    if (_isLineQuoted(line) || line.isNotEmpty) {
      return false;
    }
    final previousLine = _previousLine(line);
    return previousLine != null && _isLineQuoted(previousLine);
  }

  Line? _previousLine(Line line) {
    final offset = line.documentOffset;
    if (offset <= 0) {
      return null;
    }
    final query = _controller.document.queryChild(offset - 1);
    return query.node is Line ? query.node as Line : null;
  }

  void _startQuoteAfterBoundaryLine(Line boundaryLine) {
    final insertOffset = boundaryLine.documentOffset;
    _controller.replaceText(
      insertOffset,
      0,
      '\n',
      TextSelection.collapsed(offset: insertOffset + 1),
    );
    final quoteLineBreakOffset = insertOffset + 1;
    _controller.formatText(quoteLineBreakOffset, 1, Attribute.blockQuote);
    _controller.updateSelection(
      TextSelection.collapsed(offset: quoteLineBreakOffset),
      ChangeSource.local,
    );
  }

  void _formatCurrentLineQuote(Line line, {required bool enable}) {
    final lineBreakOffset = line.documentOffset + line.length - 1;
    _controller.formatText(
      lineBreakOffset,
      1,
      enable
          ? Attribute.blockQuote
          : Attribute.clone(Attribute.blockQuote, null),
    );
    if (line.isEmpty) {
      _controller.updateSelection(
        TextSelection.collapsed(offset: line.documentOffset),
        ChangeSource.local,
      );
    }
  }
}

class _PrototypeToolbar extends StatelessWidget {
  const _PrototypeToolbar({
    required this.keyPrefix,
    required this.enabled,
    required this.onFormatPressed,
    required this.onAlignPressed,
    required this.onQuotePressed,
    required this.onLinkPressed,
    required this.onStickerPressed,
    required this.onImagePressed,
  });

  final String keyPrefix;
  final bool enabled;
  final VoidCallback onFormatPressed;
  final VoidCallback onAlignPressed;
  final VoidCallback onQuotePressed;
  final VoidCallback onLinkPressed;
  final VoidCallback onStickerPressed;
  final VoidCallback onImagePressed;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        height: 56,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _ToolbarButton(
                key: Key('$keyPrefix-format-button'),
                tooltip: '格式',
                icon: Icons.text_fields,
                onPressed: enabled ? onFormatPressed : null,
              ),
              _ToolbarButton(
                key: Key('$keyPrefix-align-button'),
                tooltip: '对齐',
                icon: Icons.format_align_center,
                onPressed: enabled ? onAlignPressed : null,
              ),
              _ToolbarButton(
                key: Key('$keyPrefix-quote-button'),
                tooltip: '引用',
                icon: Icons.format_quote,
                onPressed: enabled ? onQuotePressed : null,
              ),
              _ToolbarButton(
                key: Key('$keyPrefix-link-button'),
                tooltip: '链接',
                icon: Icons.add_link,
                onPressed: enabled ? onLinkPressed : null,
              ),
              _ToolbarButton(
                key: Key('$keyPrefix-sticker-button'),
                tooltip: '表情',
                icon: Icons.mood,
                onPressed: enabled ? onStickerPressed : null,
              ),
              _ToolbarButton(
                key: Key('$keyPrefix-image-button'),
                tooltip: '图片',
                icon: Icons.image_outlined,
                onPressed: enabled ? onImagePressed : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolPanelFrame extends StatelessWidget {
  const _ToolPanelFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(top: false, child: child),
    );
  }
}

class _AlignPanel extends StatelessWidget {
  const _AlignPanel({required this.keyPrefix, required this.onSelected});

  final String keyPrefix;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: Key('$keyPrefix-align-sheet'),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      children: [
        ListTile(
          key: Key('$keyPrefix-align-left'),
          leading: const Icon(Icons.format_align_left),
          title: const Text('左对齐'),
          onTap: () => onSelected('left'),
        ),
        ListTile(
          key: Key('$keyPrefix-align-center'),
          leading: const Icon(Icons.format_align_center),
          title: const Text('居中'),
          onTap: () => onSelected('center'),
        ),
        ListTile(
          key: Key('$keyPrefix-align-right'),
          leading: const Icon(Icons.format_align_right),
          title: const Text('右对齐'),
          onTap: () => onSelected('right'),
        ),
      ],
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(tooltip: tooltip, icon: Icon(icon), onPressed: onPressed);
  }
}

class _FormatSheet extends StatefulWidget {
  const _FormatSheet({
    required this.keyPrefix,
    required this.controller,
    this.embedded = false,
    this.onTypingStyleChanged,
  });

  final String keyPrefix;
  final QuillController controller;
  final bool embedded;
  final VoidCallback? onTypingStyleChanged;

  @override
  State<_FormatSheet> createState() => _FormatSheetState();
}

class _FormatSheetState extends State<_FormatSheet> {
  static final List<Attribute> _clearableAttributes = <Attribute>[
    Attribute.bold,
    Attribute.italic,
    Attribute.underline,
    Attribute.strikeThrough,
    Attribute.size,
    Attribute.color,
    Attribute.background,
  ];
  static const _textColorPalette = <Color>[
    Color(0xff000000),
    Color(0xffffffff),
    Color(0xff666666),
    Color(0xffd32f2f),
    Color(0xfff57c00),
    Color(0xfffbc02d),
    Color(0xff388e3c),
    Color(0xff0288d1),
    Color(0xff1976d2),
    Color(0xff7b1fa2),
    Color(0xffc2185b),
  ];
  static const _backgroundColorPalette = <Color>[
    Color(0xffffffff),
    Color(0xffeeeeee),
    Color(0xfffff3b0),
    Color(0xffffe0b2),
    Color(0xffffcdd2),
    Color(0xfff8bbd0),
    Color(0xffe1bee7),
    Color(0xffbbdefb),
    Color(0xffc8e6c9),
    Color(0xffb2ebf2),
  ];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = widget.embedded
        ? 0.0
        : MediaQuery.viewInsetsOf(context).bottom;
    final currentSize = composerDiscuzSizeForQuillSize(
      _attributeValue(Attribute.size),
    );
    final currentColor = _attributeValue(Attribute.color)?.toString();
    final currentBackColor = _attributeValue(Attribute.background)?.toString();
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
        child: Column(
          key: Key('${widget.keyPrefix}-format-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FormatIconToggle(
                          key: Key('${widget.keyPrefix}-format-bold-toggle'),
                          icon: Icons.format_bold,
                          tooltip: '加粗',
                          selected: _isAttributeActive(Attribute.bold),
                          onSelected: (_) => _toggleAttribute(Attribute.bold),
                        ),
                        const SizedBox(width: 8),
                        _FormatIconToggle(
                          key: Key('${widget.keyPrefix}-format-italic-toggle'),
                          icon: Icons.format_italic,
                          tooltip: '斜体',
                          selected: _isAttributeActive(Attribute.italic),
                          onSelected: (_) => _toggleAttribute(Attribute.italic),
                        ),
                        const SizedBox(width: 8),
                        _FormatIconToggle(
                          key: Key(
                            '${widget.keyPrefix}-format-underline-toggle',
                          ),
                          icon: Icons.format_underline,
                          tooltip: '下划线',
                          selected: _isAttributeActive(Attribute.underline),
                          onSelected: (_) =>
                              _toggleAttribute(Attribute.underline),
                        ),
                        const SizedBox(width: 8),
                        _FormatIconToggle(
                          key: Key('${widget.keyPrefix}-format-strike-toggle'),
                          icon: Icons.format_strikethrough,
                          tooltip: '删除线',
                          selected: _isAttributeActive(Attribute.strikeThrough),
                          onSelected: (_) =>
                              _toggleAttribute(Attribute.strikeThrough),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  key: Key('${widget.keyPrefix}-format-clear-state-button'),
                  onPressed: _hasClearableStyle ? _clearAllStyles : null,
                  child: const Text('清除状态'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '字号',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                TextButton(
                  key: Key('${widget.keyPrefix}-format-clear-size-button'),
                  onPressed: currentSize == null
                      ? null
                      : () => _clearAttribute(Attribute.size),
                  child: const Text('清除字号'),
                ),
              ],
            ),
            SingleChildScrollView(
              key: Key('${widget.keyPrefix}-format-size-row'),
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var size = 1; size <= 7; size += 1) ...[
                    _FormatSizeChip(
                      key: Key('${widget.keyPrefix}-format-size-$size'),
                      size: size,
                      selected: currentSize == size.toString(),
                      onSelected: () => _toggleSize(size),
                    ),
                    if (size != 7) const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '字体色',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                TextButton(
                  key: Key('${widget.keyPrefix}-format-clear-color-button'),
                  onPressed: _attributeValue(Attribute.color) == null
                      ? null
                      : () => _clearAttribute(Attribute.color),
                  child: const Text('清除颜色'),
                ),
              ],
            ),
            _HorizontalColorStrip(
              key: Key('${widget.keyPrefix}-format-color-strip'),
              keyPrefix: '${widget.keyPrefix}-format-color',
              colors: _textColorPalette,
              selectedHex: currentColor,
              onSelected: (color) => _setAttribute(
                Attribute.color,
                composerBbCodeColorToHex(color),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '背景色',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                TextButton(
                  key: Key('${widget.keyPrefix}-format-clear-backcolor-button'),
                  onPressed: _attributeValue(Attribute.background) == null
                      ? null
                      : () => _clearAttribute(Attribute.background),
                  child: const Text('清除背景'),
                ),
              ],
            ),
            _HorizontalColorStrip(
              key: Key('${widget.keyPrefix}-format-backcolor-strip'),
              keyPrefix: '${widget.keyPrefix}-format-backcolor',
              colors: _backgroundColorPalette,
              selectedHex: currentBackColor,
              onSelected: (color) => _setAttribute(
                Attribute.background,
                composerBbCodeColorToHex(color),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!widget.embedded)
                  TextButton(
                    key: Key('${widget.keyPrefix}-format-close-button'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('关闭'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _handleControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  bool _isAttributeActive(Attribute attribute) {
    return _attributeValue(attribute) != null;
  }

  Object? _attributeValue(Attribute attribute) {
    return widget.controller
        .getSelectionStyle()
        .attributes[attribute.key]
        ?.value;
  }

  bool get _hasClearableStyle {
    final controller = widget.controller;
    if (controller.selection.isCollapsed) {
      return _containsClearableStyle(controller.getSelectionStyle());
    }
    return controller.getAllSelectionStyles().any(_containsClearableStyle);
  }

  bool _containsClearableStyle(Style style) {
    return _clearableAttributes.any(
      (attribute) => style.attributes[attribute.key]?.value != null,
    );
  }

  void _toggleAttribute(Attribute attribute) {
    _runQuillMutationWithoutKeyboard(() {
      widget.controller.formatSelection(
        _isAttributeActive(attribute)
            ? Attribute.clone(attribute, null)
            : attribute,
      );
    });
  }

  void _toggleSize(int size) {
    final value = size.toString();
    if (composerDiscuzSizeForQuillSize(_attributeValue(Attribute.size)) ==
        value) {
      _clearAttribute(Attribute.size);
      return;
    }
    final quillSize = composerQuillSizeForDiscuzSize(size);
    if (quillSize != null) {
      _setAttribute(Attribute.size, quillSize);
    }
  }

  void _setAttribute(Attribute attribute, Object value) {
    _runQuillMutationWithoutKeyboard(() {
      widget.controller.formatSelection(Attribute.clone(attribute, value));
    });
  }

  void _clearAttribute(Attribute attribute) {
    _runQuillMutationWithoutKeyboard(() {
      widget.controller.formatSelection(Attribute.clone(attribute, null));
    });
  }

  void _clearAllStyles() {
    _runQuillMutationWithoutKeyboard(() {
      final controller = widget.controller;
      final selection = controller.selection;
      if (selection.isCollapsed) {
        var style = controller.toggledStyle;
        for (final attribute in _clearableAttributes) {
          style = style.put(Attribute.clone(attribute, null));
        }
        controller.forceToggledStyle(style);
        return;
      }

      final clearedAttributes = <String, dynamic>{
        for (final attribute in _clearableAttributes) attribute.key: null,
      };
      final delta = Delta()
        ..retain(selection.start)
        ..retain(selection.end - selection.start, clearedAttributes);
      controller.compose(delta, selection, ChangeSource.local);
    });
  }

  void _runQuillMutationWithoutKeyboard(VoidCallback mutation) {
    widget.controller.skipRequestKeyboard = true;
    try {
      mutation();
      widget.onTypingStyleChanged?.call();
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        if (widget.controller.skipRequestKeyboard) {
          widget.controller.skipRequestKeyboard = false;
        }
      });
    }
  }
}

class _FormatIconToggle extends StatelessWidget {
  const _FormatIconToggle({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onSelected,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: IconButton.filledTonal(
        isSelected: selected,
        selectedIcon: Icon(icon),
        icon: Icon(icon),
        style: IconButton.styleFrom(
          fixedSize: const Size.square(44),
          backgroundColor: selected
              ? colorScheme.secondaryContainer
              : colorScheme.surfaceContainerHighest,
          foregroundColor: selected
              ? colorScheme.onSecondaryContainer
              : colorScheme.onSurfaceVariant,
        ),
        onPressed: () => onSelected(!selected),
      ),
    );
  }
}

class _FormatSizeChip extends StatelessWidget {
  const _FormatSizeChip({
    super.key,
    required this.size,
    required this.selected,
    required this.onSelected,
  });

  final int size;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 40,
      child: ChoiceChip(
        label: Center(child: Text(size.toString())),
        selected: selected,
        onSelected: (_) => onSelected(),
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _HorizontalColorStrip extends StatelessWidget {
  const _HorizontalColorStrip({
    super.key,
    required this.keyPrefix,
    required this.colors,
    required this.selectedHex,
    required this.onSelected,
  });

  final String keyPrefix;
  final List<Color> colors;
  final String? selectedHex;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final color in colors) ...[
            _ColorSwatchButton(
              key: Key('$keyPrefix-swatch-${_hexKey(color)}'),
              color: color,
              selected: selectedHex == composerBbCodeColorToHex(color),
              onPressed: () => onSelected(color),
            ),
            if (color != colors.last) const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }

  String _hexKey(Color color) {
    return composerBbCodeColorToHex(color).substring(1);
  }
}

class _ColorSwatchButton extends StatelessWidget {
  const _ColorSwatchButton({
    super.key,
    required this.color,
    required this.selected,
    required this.onPressed,
  });

  final Color color;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = selected
        ? colorScheme.primary
        : colorScheme.outlineVariant;
    return Tooltip(
      message: composerBbCodeColorToHex(color),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onPressed,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(color: borderColor, width: selected ? 3 : 1),
          ),
          child: selected
              ? Icon(
                  Icons.check,
                  size: 18,
                  color:
                      ThemeData.estimateBrightnessForColor(color) ==
                          Brightness.dark
                      ? Colors.white
                      : Colors.black,
                )
              : null,
        ),
      ),
    );
  }
}

class _StickerEmbedBuilder extends EmbedBuilder {
  const _StickerEmbedBuilder({required this.stickers});

  final List<StickerItem> stickers;

  @override
  String get key => composerQuillStickerEmbedType;

  @override
  bool get expanded => false;

  @override
  String toPlainText(Embed node) {
    return node.value.data.toString();
  }

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final code = embedContext.node.value.data.toString();
    final sticker = stickers.cast<StickerItem?>().firstWhere(
      (item) => item?.code == code,
      orElse: () => null,
    );
    if (sticker == null) {
      return Text(code);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: ConstrainedBox(
        key: Key('composer-quill-sticker-frame-$code'),
        constraints: const BoxConstraints(maxWidth: 96, maxHeight: 96),
        child: ComposerStickerImage(
          key: Key('composer-quill-sticker-$code'),
          sticker: sticker,
          fit: BoxFit.contain,
          placeholder: const SizedBox.shrink(),
          errorPlaceholder: const Icon(Icons.broken_image_outlined, size: 20),
        ),
      ),
    );
  }
}

class _AttachEmbedBuilder extends EmbedBuilder {
  const _AttachEmbedBuilder({
    required this.imageAttachments,
    required this.attachImageBuilder,
    required this.attachFileExists,
  });

  static const _grammar = ComposerAttachBbCodeGrammar();

  final List<ComposerImageAttachment> imageAttachments;
  final ForumAttachPreviewImageBuilder attachImageBuilder;
  final ForumAttachPreviewFileExists attachFileExists;

  @override
  String get key => composerQuillAttachEmbedType;

  @override
  bool get expanded => false;

  @override
  String toPlainText(Embed node) {
    return _grammar.codeFor(node.value.data.toString());
  }

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final aid = embedContext.node.value.data.toString();
    // 与 BBCode 预览侧 `_AttachPreviewTag` 同一口径：只有可进入提交载荷的
    // 附件才渲染图片，其余（含未知 aid）退化成芯片。过期由草稿 sanitizer 统一处理。
    final attachment = imageAttachments
        .cast<ComposerImageAttachment?>()
        .firstWhere(
          (item) => item != null && item.canEnterSubmitPayload &&
              item.aid!.trim() == aid,
          orElse: () => null,
        );
    if (attachment != null) {
      final file = File(attachment.previewPath);
      if (attachFileExists(file)) {
        return Padding(
          key: Key('composer-quill-attach-$aid'),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320, maxHeight: 240),
            child: attachImageBuilder(
              file,
              Key('composer-quill-attach-image-$aid'),
            ),
          ),
        );
      }
    }
    final label = attachment == null ? '图片 $aid' : attachment.fileName;
    return Container(
      key: Key('composer-quill-attach-$aid'),
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.image_outlined,
            size: 16,
            color: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSecondaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
