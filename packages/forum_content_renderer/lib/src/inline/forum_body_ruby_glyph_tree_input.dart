part of 'forum_body_ruby_tree_input.dart';

/// One explicit author -> current window -> glyph association. IDs retain the
/// source tree's context namespace; negative IDs belong to real inline children.
/// This value does not qualify a visible source or a complete emphasis format.
final class ForumBodyRubyGlyphTreeSource {
  const ForumBodyRubyGlyphTreeSource._({
    required this.id,
    required this.original,
    required this.content,
    required this.glyphs,
    required this.emphasis,
    required this.needsNative,
  });
  final int id;
  final ForumBodyParagraphContent original;
  final ForumBodyParagraphContent content;
  final ForumBodyParagraphContent glyphs;
  final ForumBodyEmphasisTextInput? emphasis;

  /// Empty base struts need a glyph-plane leaf; empty RTs and inline contexts
  /// do not own one. Annotation font reservations are a separate format input.
  final bool needsNative;
}

/// A source-preserving glyph projection for measurement, deliberately distinct
/// from the original tree and from a ready render plan. The private projected
/// graph cannot be passed off as a complete visible tree with missing markers.
final class ForumBodyRubyGlyphTreeInput {
  ForumBodyRubyGlyphTreeInput._(
    this.sourceTree,
    this._glyphTree,
    List<ForumBodyRubyGlyphTreeSource> sources,
    Map<int, ForumBodyRubyGlyphTreeSource> byId,
  ) : sources = UnmodifiableListView(sources),
      _byId = UnmodifiableMapView(byId);
  final ForumBodyRubyTreeInput sourceTree;
  final ForumBodyRubyTreeInput _glyphTree;
  final List<ForumBodyRubyGlyphTreeSource> sources;
  final Map<int, ForumBodyRubyGlyphTreeSource> _byId;
  double get maxWidth => sourceTree.maxWidth;
  List<ForumBodyTextRequest> get glyphRequests => _glyphTree.nativeRequests;
  ForumBodyRubyGlyphTreeSource sourceForId(int id) =>
      _byId[id] ?? (throw ArgumentError.value(id, 'id'));
  ForumBodyTextRequest requestForSource(int id) {
    final source = sourceForId(id);
    if (!source.needsNative) {
      throw ArgumentError('Source context has no independent glyph request');
    }
    return (_glyphTree.nodes[id] as ForumBodyRubyTreeText).request;
  }

  /// Keep original source bindings while mapping real glyph requests, including
  /// an actual band alias. Geometry must be measured again for the new input;
  /// this method never carries old opaque font keys or rendering readiness.
  ForumBodyRubyGlyphTreeInput mapGlyphRequests(
    ForumBodyTextRequest Function(ForumBodyTextRequest) map,
  ) => ForumBodyRubyGlyphTreeInput._(
    sourceTree,
    _glyphTree.mapRequests(map),
    sources,
    _byId,
  );
}

enum _GlyphTreePhase {
  tree,
  nodes,
  sources,
  publish,
  ready,
  transferred,
  closed,
}

/// Build the original graph first, then project actual leaf styles and source
/// units cooperatively. Empty source-free struts suppress only the non-font
/// emphasis flag; their author input and native font settings remain separate.
final class ForumBodyRubyGlyphTreeInputPreparation {
  ForumBodyRubyGlyphTreeInputPreparation({
    required ForumBodyRubyGroupContent group,
    required double maxWidth,
    required void Function() ensureOwner,
  }) : _builder = ForumBodyRubyTreeInputPreparation(
         group: group,
         maxWidth: maxWidth,
       ),
       _ensureOwner = ensureOwner;
  ForumBodyRubyTreeInputPreparation? _builder;
  ForumBodyRubyTreeInput? _sourceTree;
  void Function()? _ensureOwner;
  List<ForumBodyRubyTreeNode> _nodes = [];
  List<ForumBodyTextRequest> _requests = [];
  List<ForumBodyRubyTreeSource> _glyphSources = [];
  List<ForumBodyRubyGlyphTreeSource> _sources = [];
  Map<int, ForumBodyRubyGlyphTreeSource> _byId = {};
  final Map<ForumBodyRubyRootBoxInput, ForumBodyRubyRootBoxInput> _fonts =
      Map.identity();
  ForumBodyEmphasisGlyphPreparation? _glyphJob;
  ForumBodyEmphasisGlyphInput? _glyphInput;
  ForumBodyEmphasisTextPreparation? _textJob;
  Iterator<ForumBodyResolvedStyle>? _inlineStyles;
  ForumBodyRubyGlyphTreeInput? _result;
  var _phase = _GlyphTreePhase.tree;
  int _node = 0, _source = 0;
  bool _operating = false;
  bool get isReady => _phase == _GlyphTreePhase.ready;

  int advance({int maxParts = 32}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) {
      throw StateError('Ruby glyph source preparation is reentrant');
    }
    _operating = true;
    var parts = 0;
    try {
      _guard();
      while (!isReady && parts < maxParts) {
        switch (_phase) {
          case _GlyphTreePhase.tree:
            _builder!.advance(maxParts: 1);
            _guard();
            if (_builder!.isReady) {
              _sourceTree = _builder!.takeInput();
              _builder = null;
              _phase = _GlyphTreePhase.nodes;
            }
          case _GlyphTreePhase.nodes:
            if (_node < _sourceTree!.nodes.length) {
              final node = _sourceTree!.nodes[_node];
              if (node is ForumBodyRubyTreeText) {
                _projectText(node);
              } else {
                _projectContainer(node as ForumBodyRubyTreeContainer);
                _node++;
              }
            } else {
              _phase = _GlyphTreePhase.sources;
            }
          case _GlyphTreePhase.sources:
            if (_source < _sourceTree!.sources.length) {
              final source = _sourceTree!.sources[_source];
              final binding = _byId[source.id];
              if (binding != null) {
                _publishSource(binding);
              } else {
                // A mixed inline subtree owns its actual parent/placeholder
                // format. Never rewrite its text behind that parent's back.
                final styles = _inlineStyles ??= _styles(
                  source.content,
                ).iterator;
                if (styles.moveNext()) {
                  if (styles.current.textEmphasis.isEnabled) {
                    _unsupported(source.content.path);
                  }
                } else {
                  _inlineStyles = null;
                  _publishSource(
                    ForumBodyRubyGlyphTreeSource._(
                      id: source.id,
                      original: source.content,
                      content: source.content,
                      glyphs: source.content,
                      emphasis: null,
                      needsNative: false,
                    ),
                  );
                }
              }
            } else {
              _phase = _GlyphTreePhase.publish;
            }
          case _GlyphTreePhase.publish:
            final source = _sourceTree!;
            final glyphTree = ForumBodyRubyTreeInput._(
              _nodes,
              _requests,
              _glyphSources,
              source.maxWidth,
              source._structure,
            );
            _result = ForumBodyRubyGlyphTreeInput._(
              source,
              glyphTree,
              _sources,
              _byId,
            );
            _nodes = [];
            _requests = [];
            _glyphSources = [];
            _sources = [];
            _byId = {};
            _phase = _GlyphTreePhase.ready;
          case _GlyphTreePhase.ready:
          case _GlyphTreePhase.transferred:
          case _GlyphTreePhase.closed:
            throw StateError('Ruby glyph source preparation is retired');
        }
        parts++;
        _guard();
      }
      return parts;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _projectText(ForumBodyRubyTreeText node) {
    final content = node.content;
    if (content.isSourceFree) {
      final glyphs = content.style.textEmphasis.isEnabled
          ? ForumBodyParagraphContent.anonymousInline(
              identity: content.identity,
              fontRevision: content.fontRevision,
              styleRevision: content.styleRevision,
              style: content.style.withTextEmphasis(
                const ForumBodyTextEmphasis(),
              ),
            )
          : content;
      _finishText(node, glyphs, null);
    } else if (_glyphInput == null) {
      final job = _glyphJob ??= ForumBodyEmphasisGlyphPreparation(
        content: content,
      );
      job.advance(maxParts: 1);
      if (job.isReady) {
        _glyphInput = job.takeInput();
        _glyphJob = null;
      }
    } else if (identical(_glyphInput!.glyphs, content)) {
      _finishText(node, content, null);
    } else {
      final job = _textJob ??= ForumBodyEmphasisTextPreparation.fromGlyphInput(
        glyphInput: _glyphInput!,
      );
      job.advance(maxParts: 1);
      if (job.isReady) {
        final emphasis = job.takeInput();
        _textJob = null;
        _finishText(node, emphasis.glyphInput.glyphs, emphasis);
      }
    }
  }

  void _finishText(
    ForumBodyRubyTreeText node,
    ForumBodyParagraphContent glyphs,
    ForumBodyEmphasisTextInput? emphasis,
  ) {
    final request = identical(glyphs, node.content)
        ? node.request
        : ForumBodyTextRequest.paragraph(glyphs);
    _nodes.add(
      identical(glyphs, node.content)
          ? node
          : node.needsNative
          ? ForumBodyRubyTreeText._request(node.original, glyphs, request)
          : ForumBodyRubyTreeText._(node.original, glyphs, false),
    );
    if (node.needsNative) _requests.add(request);
    _byId[_node] = ForumBodyRubyGlyphTreeSource._(
      id: _node,
      original: node.original,
      content: node.content,
      glyphs: glyphs,
      emphasis: emphasis,
      needsNative: node.needsNative,
    );
    _glyphInput = null;
    _node++;
  }

  ForumBodyRubyRootBoxInput _font(ForumBodyRubyRootBoxInput input) {
    if (!input.fontStrut.style.textEmphasis.isEnabled) return input;
    return _fonts.putIfAbsent(input, () {
      final strut = input.fontStrut;
      return ForumBodyRubyRootBoxInput(
        rootPath: input.rootPath,
        fontStrut: ForumBodyParagraphContent.anonymousInline(
          identity: strut.identity,
          fontRevision: strut.fontRevision,
          styleRevision: strut.styleRevision,
          style: strut.style.withTextEmphasis(const ForumBodyTextEmphasis()),
        ),
      );
    });
  }

  void _projectContainer(ForumBodyRubyTreeContainer node) {
    if (node is ForumBodyRubyTreeInline &&
        node.input.content.style.textEmphasis.isEnabled) {
      _unsupported(node.input.content.path);
    }
    final font = _font(node.font);
    _nodes.add(
      identical(font, node.font)
          ? node
          : switch (node) {
              ForumBodyRubyTreeGroup() => ForumBodyRubyTreeGroup._withFont(
                font,
                node,
              ),
              ForumBodyRubyTreeSegment() => ForumBodyRubyTreeSegment._withFont(
                font,
                node,
              ),
              ForumBodyRubyTreeFrame() => ForumBodyRubyTreeFrame._(
                font,
                node.background,
                node.input,
                node.child,
              ),
              ForumBodyRubyTreeInline() => ForumBodyRubyTreeInline._(
                font,
                node.background,
                node.input,
                node.sources,
              ),
            },
    );
  }

  void _publishSource(ForumBodyRubyGlyphTreeSource binding) {
    _sources.add(binding);
    _byId[binding.id] = binding;
    _glyphSources.add(ForumBodyRubyTreeSource(binding.id, binding.glyphs));
    _source++;
  }

  static Iterable<ForumBodyResolvedStyle> _styles(
    ForumBodyParagraphContent content,
  ) sync* {
    yield content.style;
    for (final run in content.runs) {
      yield run.style;
    }
  }

  ForumBodyRubyGlyphTreeInput takeInput() {
    if (_operating) {
      throw StateError('Ruby glyph source preparation is reentrant');
    }
    _operating = true;
    try {
      _guard();
      if (!isReady) throw StateError('Ruby glyph source input is incomplete');
      final result = _result!;
      _result = null;
      _phase = _GlyphTreePhase.transferred;
      _drop();
      return result;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _guard() {
    if (_phase == _GlyphTreePhase.closed ||
        _phase == _GlyphTreePhase.transferred) {
      throw StateError('Ruby glyph source preparation is retired');
    }
    _ensureOwner!();
    if (_phase == _GlyphTreePhase.closed) {
      throw StateError('Ruby glyph source owner is retired');
    }
  }

  void _drop() {
    _builder?.close();
    _builder = null;
    _glyphJob?.close();
    _glyphJob = null;
    _textJob?.close();
    _textJob = null;
    _glyphInput = null;
    _sourceTree = null;
    _inlineStyles = null;
    _ensureOwner = null;
    _fonts.clear();
    _nodes = [];
    _requests = [];
    _glyphSources = [];
    _sources = [];
    _byId = {};
  }

  void close() {
    if (_phase == _GlyphTreePhase.closed ||
        _phase == _GlyphTreePhase.transferred) {
      return;
    }
    _phase = _GlyphTreePhase.closed;
    _result = null;
    _drop();
  }
}
