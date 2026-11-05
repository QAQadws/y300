part of 'forum_body_text_page_session.dart';

/// Transfer only source-bound pure inputs from the completed child. The child
/// can retire before the parent starts its own visible page preparation.
List<ForumBodyTextPageContent> borrowForumBodyFloatInputs(
  ForumBodyTextPageSession session,
) {
  session._ensureUsable();
  if (!session.isComplete) throw StateError('Float body is incomplete');
  return List.unmodifiable(session._content.items);
}

final class _FloatFlowAdmission {
  _FloatFlowAdmission(this._session, this._unit)
    // Text flow reuses the already admitted source to express a trailing
    // empty row. It must not replay controls from that earlier source.
    : _next =
          _unit.paragraph.window == ForumBodyParagraphWindow.terminalEmptyLine
          ? _unit.paragraph.content.parts.length - 1
          : 0;

  final ForumBodyTextPageSession _session;
  final ForumBodyBlockFlowInline _unit;
  int _next;
  bool _cleared = false;
  bool _startedText = false;
  ForumBodyFloatBodyPreparation? _preparation;
  ForumBodyFloatBodyLayout? _layout;
  List<ForumBodyTextPageContent>? _inputs;
  _HeldFloatText? _held;

  bool get isComplete =>
      _next == _unit.paragraph.content.parts.length && _held == null;

  void hold(_HeldFloatText text) {
    if (_held != null) throw StateError('Float line is already held');
    _held = text;
  }

  /// Returns whether this work is waiting for shared native cache capacity.
  bool advance({
    required int maxEvents,
    required int maxLines,
    required int maxFormatParts,
  }) {
    final content = _unit.paragraph.content;
    if (_held != null &&
        (_next == content.parts.length ||
            content.parts[_next] is ForumBodyInlineFlowClear)) {
      _flushHeld();
      return false;
    }
    final part = content.parts[_next];
    if (_unit.listMarkers.isNotEmpty) _session._requiresFloatLineLayout();
    final following = _next + 1 < content.parts.length
        ? content.parts[_next + 1]
        : null;
    final beforeFloat = following is ForumBodyInlineFlowFloat;
    final prefix = part is ForumBodyInlineFlowText ? _heldPrefix() : null;
    final text = part is ForumBodyInlineFlowText
        ? trimForumBodyInlineText(
            part.content,
            leading:
                prefix == null ||
                prefix.projection.text.isEmpty ||
                forumBodyInlineHasCollapsibleEdge(prefix, leading: false),
            trailing: !beforeFloat,
          )
        : null;
    switch (part) {
      case ForumBodyInlineFlowClear():
        _session._composer.clearMeasuredFloats(part.event.style.clear);
        _cleared = true;
      case ForumBodyInlineFlowFloat():
        if (_layout == null) {
          final job = _preparation ??= _session._openFloat!(
            part,
            _unit.contentWidth,
            _session._remainingSubtreeLimits(),
          );
          final step = job.advance(
            maxEvents: maxEvents,
            maxLines: maxLines,
            maxFormatParts: maxFormatParts,
          );
          _session._ensureActivePlan();
          if (!step.isReady) return step.waitingForLayoutBudget;
          _layout = job.takeLayout();
          _preparation = null;
        }
        final layout = _layout!;
        final inputs = _inputs ??= layout.borrowInputs();
        var text = 0, runs = 0;
        for (final input in inputs) {
          text += input.retainedTextCodeUnits;
          runs += input.retainedRuns;
        }
        _session._content.checkCounts(text, runs, paragraphs: inputs.length);
        if (!_session._composer.placeMeasuredFloat(
          layout: layout,
          inputCount: inputs.length,
          left: _unit.contentLeft,
          containingWidth: _unit.contentWidth,
          spaceBefore: _session._margin,
          precedingLine: _held?.line,
        )) {
          if (_held != null) _flushHeld();
          return false;
        }
        for (final input in inputs) {
          _session._content.add(input);
        }
        _session._margin = 0;
        layout.close();
        _layout = null;
        _inputs = null;
      case ForumBodyInlineFlowText()
          when text!.projection.text.isEmpty && prefix == null:
        break;
      case ForumBodyInlineFlowText()
          when beforeFloat ||
              following == null ||
              following is ForumBodyInlineFlowClear:
        final terminalRow =
            _unit.paragraph.window ==
            ForumBodyParagraphWindow.terminalEmptyLine;
        final suffix = text!;
        final paragraph =
            prefix?.followedBy(suffix) ??
            suffix.withFirstLineIndent(
              content.appliesFirstLineIndent &&
                  !_startedText &&
                  !_cleared &&
                  !terminalRow,
            );
        _held = null;
        _startText(
          trimForumBodyInlineText(
            paragraph,
            leading: false,
            trailing: !beforeFloat,
          ),
          following == null
              ? _unit.paragraph.window
              : ForumBodyParagraphWindow.full,
          holdLastLine: beforeFloat,
        );
      default:
        if (_held != null ||
            !_cleared ||
            content.parts
                .skip(_next)
                .any((part) => part is ForumBodyInlineFlowExclusion)) {
          _session._requiresFloatLineLayout();
        }
        _session._ensureFloatLineAvailable();
        _session._pendingInline = _unit;
        _session._inlineContinuation = ForumBodyInlineFlowContent(
          identity: content.identity,
          path: content.path,
          fontRevision: content.fontRevision,
          styleRevision: content.styleRevision,
          style: content.style,
          layoutMode: content.layoutMode,
          appliesFirstLineIndent: false,
          trimCollapsibleEdges: content.trimCollapsibleEdges,
          parts: content.parts.sublist(_next),
          ignored: content.ignored,
          issues: content.issues,
        );
        _next = content.parts.length;
        return false;
    }
    _next++;
    return false;
  }

  ForumBodyParagraphContent? _heldPrefix() {
    final held = _held;
    if (held == null) return null;
    if (held.window != ForumBodyParagraphWindow.terminalEmptyLine) {
      return held.content;
    }
    final end = held.content.projection.text.length;
    return held.content.displayWindow(
      startUtf16: end,
      endUtf16: end,
      appliesFirstLineIndent: false,
    );
  }

  void _flushHeld() {
    final held = _held!;
    _held = null;
    _startText(
      trimForumBodyInlineText(held.content, leading: false, trailing: true),
      held.window,
    );
  }

  void _startText(
    ForumBodyParagraphContent content,
    ForumBodyParagraphWindow window, {
    bool holdLastLine = false,
  }) {
    _session._floatText = _FloatTextAdmission(
      _session,
      content,
      window,
      left: _unit.contentLeft,
      width: _unit.contentWidth,
      holdLastLine: holdLastLine,
    );
    _startedText = true;
  }

  void close() {
    _preparation?.close();
    _preparation = null;
    _layout?.close();
    _layout = null;
    _inputs = null;
  }
}
