part of 'forum_body_inline_paragraph_view.dart';

enum _ViewAssemblyState { active, ready, transferred, failed, closed }

/// Consumes only the supplied parent/children. Pure parent indexing, every atom
/// scan, each actual member/missing rank and final publication are bounded units.
/// The synchronous View factory drives this SAME transaction; no native work.
final class ForumBodyInlineViewAssembly {
  ForumBodyInlineViewAssembly({
    required ForumBodyParagraphCache cache,
    required ForumBodyInlineParagraphLease parent,
    required this.startLine,
    required this.endLine,
    Map<int, ForumBodyRubyGroupLayout> rubyGroups = const {},
    Map<int, ForumBodyTextBaselineLayout> baselineTexts = const {},
    Map<int, ForumBodyInlineParagraphView> intrinsicBoxes = const {},
    Map<int, ForumBodyRubySegmentLayout> rubySegments = const {},
    Map<int, ForumBodyRubySoftSpaceLayout> rubySpaces = const {},
    Map<int, ForumBodyRubyTreeLayout> rubyTrees = const {},
    Map<int, ForumBodyRubyContainerFontBox> containerBackgrounds = const {},
    Map<int, ForumBodyRubyRootFontBox> rootFonts = const {},
    void Function()? ensureOwner,
  }) : _cache = cache,
       _parent = parent,
       _groups = Map.of(rubyGroups),
       _baselines = Map.of(baselineTexts),
       _inlineBoxes = Map.of(intrinsicBoxes),
       _segments = Map.of(rubySegments),
       _spaces = Map.of(rubySpaces),
       _trees = Map.of(rubyTrees),
       _backgroundFonts = Map.of(containerBackgrounds),
       _rootFonts = Map.of(rootFonts),
       _ensureOwner = ensureOwner;
  ForumBodyParagraphCache? _cache;
  ForumBodyInlineParagraphLease? _parent;
  Map<int, ForumBodyRubyGroupLayout> _groups;
  Map<int, ForumBodyTextBaselineLayout> _baselines;
  Map<int, ForumBodyInlineParagraphView> _inlineBoxes;
  Map<int, ForumBodyRubySegmentLayout> _segments;
  Map<int, ForumBodyRubySoftSpaceLayout> _spaces;
  Map<int, ForumBodyRubyTreeLayout> _trees;
  Map<int, ForumBodyRubyContainerFontBox> _backgroundFonts;
  Map<int, ForumBodyRubyRootFontBox> _rootFonts;
  final _backgroundRegions = _RubyBackgroundRegions();
  void Function()? _ensureOwner;
  final int startLine;
  final int endLine;
  ForumBodyInlineParagraphFragment? _fragment;
  Map<int, _RubyBinding> _bindings = {};
  Map<int, ForumBodyInlineImageBinding> _images = const {};
  final _checked = Set<ForumBodyNativeParagraphLease>.identity();
  _RubyBindingWork? _binding;
  ForumBodyRubyAtomFrame? _bindingFrame;
  var _bindingIndex = -1;
  var _treeBackgroundIndex = 0;
  var _atom = 0;
  var _preparedAtoms = 0;
  var _workCount = 0;
  var _initialized = false;
  var _operating = false;
  var _state = _ViewAssemblyState.active;
  bool get isReady => _state == _ViewAssemblyState.ready;
  int get preparedAtomCount => _preparedAtoms;
  int get workCount => _workCount;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    ?_parent,
    for (final group in _groups.values) ...group.nativeLeases,
    for (final text in _baselines.values) text.lease,
    for (final view in _inlineBoxes.values) ...view.nativeLeases,
    for (final segment in _segments.values) ...segment.nativeLeases,
    for (final space in _spaces.values) ...space.nativeLeases,
    for (final tree in _trees.values) ...tree.nativeLeases,
  ];

  int advance({required int maxParts}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    return _operate(() {
      _guard();
      if (isReady) throw StateError('Inline view assembly is already ready');
      var work = 0;
      while (work < maxParts && !isReady) {
        if (!_initialized) {
          if (!_cache!.ownsLease(_parent!)) {
            _fail(ForumBodyInlineViewFailure.leases);
          }
          _checked.add(_parent!);
          final layout = _parent!.layout;
          if (layout.lines.isEmpty) {
            if (startLine != 0 ||
                endLine != 0 ||
                _groups.isNotEmpty ||
                _baselines.isNotEmpty ||
                _inlineBoxes.isNotEmpty ||
                _segments.isNotEmpty ||
                _spaces.isNotEmpty ||
                _trees.isNotEmpty) {
              _fail(ForumBodyInlineViewFailure.coverage);
            }
          } else {
            _fragment = layout.fragment(startLine, endLine);
          }
          _initialized = true;
          work++;
        } else if (_fragment == null) {
          _state = _ViewAssemblyState.ready;
          work++;
        } else if (!_parent!.content.isContextIndexReady) {
          work += _parent!.content.prepareContextIndex(
            maxContexts: maxParts - work,
          );
        } else if (_binding != null) {
          if (!_binding!.isComplete) {
            work += _binding!.advance(maxParts: maxParts - work);
          }
          if (_binding!.isComplete) {
            final backgrounds = _trees[_bindingIndex]?.backgrounds;
            if (backgrounds != null &&
                _treeBackgroundIndex < backgrounds.length) {
              if (work == maxParts) break;
              _appendTreeBackground(
                _bindingIndex,
                backgrounds[_treeBackgroundIndex++],
              );
              work++;
              if (_treeBackgroundIndex < backgrounds.length) continue;
            }
            final child = _binding!.takeBinding();
            _bindings[_bindingIndex] = switch (_bindingFrame) {
              final frame? => _RubyRootFrameBinding(
                child,
                frame,
                _rootRowAllocation(_bindingIndex),
              ),
              null => child,
            };
            _appendBackground(_bindingIndex, _bindings[_bindingIndex]!);
            _binding = null;
            _bindingFrame = null;
            _treeBackgroundIndex = 0;
            _preparedAtoms++;
          }
        } else if (_atom < _parent!.layout.projection.atoms.length) {
          final atom = _parent!.layout.projection.atoms[_atom++];
          if (atom.engineUtf16 >= _fragment!.engineCoverageStartUtf16 &&
              atom.engineUtf16 < _fragment!.engineCoverageEndUtf16 &&
              !_parent!.layout.isAtomTrimmed(atom.index)) {
            if (atom.isResource) {
              _bindImage(atom.index);
              _preparedAtoms++;
              work++;
              _guard();
              continue;
            }
            final group = _groups[atom.index];
            final baselineText = _baselines[atom.index];
            final inlineBox = _inlineBoxes[atom.index];
            final segment = _segments[atom.index];
            final space = _spaces[atom.index];
            final tree = _trees[atom.index];
            if ((group != null ? 1 : 0) +
                        (baselineText != null ? 1 : 0) +
                        (inlineBox != null ? 1 : 0) +
                        (segment != null ? 1 : 0) +
                        (space != null ? 1 : 0) +
                        (tree != null ? 1 : 0) >
                    1 ||
                atom.isSoftSpace != (space != null)) {
              _fail(ForumBodyInlineViewFailure.leases);
            }
            if (group == null &&
                baselineText == null &&
                inlineBox == null &&
                segment == null &&
                space == null &&
                tree == null) {
              _fail(ForumBodyInlineViewFailure.coverage);
            }
            final size =
                baselineText?.metrics.size ??
                (inlineBox == null
                    ? null
                    : Size(inlineBox.width, inlineBox.height)) ??
                group?.size ??
                segment?.size ??
                space?.size ??
                tree!.size;
            final baseline =
                baselineText?.metrics.baseline ??
                inlineBox?.lines.single.baseline ??
                group?.baseline ??
                segment?.baseline ??
                space?.baseline ??
                tree!.baseline;
            final root = _rootFonts[atom.index];
            if (root != null) {
              final parent = _parent!.content;
              if (root.input.fontStrut.identity != parent.identity ||
                  root.input.fontStrut.fontRevision != parent.fontRevision ||
                  root.input.fontStrut.styleRevision != parent.styleRevision) {
                _fail(ForumBodyInlineViewFailure.identity);
              }
            }
            if (tree != null &&
                (root == null ||
                    !identical(root.input, tree.metrics.root.font.input) ||
                    root.height != tree.metrics.root.font.height ||
                    root.alphabeticBaseline !=
                        tree.metrics.root.font.alphabeticBaseline)) {
              _fail(ForumBodyInlineViewFailure.identity);
            }
            _bindingFrame = root?.enclose(
              childSize: size,
              childBaseline: baseline,
            );
            final frameSize = _bindingFrame?.size ?? size;
            final frameBaseline = _bindingFrame?.baseline ?? baseline;
            if (tree == null &&
                frameSize == size &&
                frameBaseline == baseline) {
              _bindingFrame = null;
            }
            final dimension = _parent!.layout.dimensions[atom.index];
            if ((dimension.size.width - frameSize.width).abs() > 1e-4 ||
                (dimension.size.height - frameSize.height).abs() > 1e-4 ||
                (dimension.baselineOffset! - frameBaseline).abs() > 1e-4) {
              _fail(ForumBodyInlineViewFailure.geometry);
            }
            _bindingIndex = atom.index;
            _binding = _RubyBindingWork(
              baselineText: baselineText,
              intrinsicBox: inlineBox,
              content: _parent!.content,
              index: atom.index,
              group: group,
              segment: segment,
              space: space,
              tree: tree,
              own: _own,
            );
          }
          work++;
        } else {
          if (_bindings.length !=
              _groups.length +
                  _baselines.length +
                  _inlineBoxes.length +
                  _segments.length +
                  _spaces.length +
                  _trees.length) {
            _fail(ForumBodyInlineViewFailure.coverage);
          }
          _state = _ViewAssemblyState.ready;
          work++;
        }
        _guard();
      }
      _workCount += work;
      return work;
    });
  }

  void _appendTreeBackground(
    int index,
    ({Rect rect, ForumBodyRubyContainerFontBox font}) region,
  ) {
    final layout = _parent!.layout;
    final origin =
        layout.atomBoxes[index].toRect().topLeft - Offset(0, _fragment!.top);
    _backgroundRegions.add(
      region.font,
      _rowOfAtom(index),
      region.rect.shift(origin),
    );
  }

  void _bindImage(int index) {
    if (_groups.containsKey(index) ||
        _baselines.containsKey(index) ||
        _inlineBoxes.containsKey(index) ||
        _segments.containsKey(index) ||
        _spaces.containsKey(index) ||
        _trees.containsKey(index) ||
        _rootFonts.containsKey(index) ||
        _backgroundFonts.containsKey(index)) {
      _fail(ForumBodyInlineViewFailure.coverage);
    }
    final input = _parent!.content.images[index];
    if (input == null || input.identity != _parent!.content.identity) {
      _fail(ForumBodyInlineViewFailure.coverage);
    }
    final dimension = _parent!.layout.dimensions[index];
    if (dimension.size != input.dimensions.size ||
        dimension.baselineOffset != input.dimensions.baselineOffset) {
      _fail(ForumBodyInlineViewFailure.geometry);
    }
    final rect = _parent!.layout.atomBoxes[index].toRect().shift(
      Offset(0, -_fragment!.top),
    );
    if (rect.isEmpty ||
        rect.left < 0 ||
        rect.top < 0 ||
        rect.right > _parent!.layout.width ||
        rect.bottom > _fragment!.height) {
      _fail(ForumBodyInlineViewFailure.geometry);
    }
    if (_images.isEmpty) _images = {};
    _images[index] = ForumBodyInlineImageBinding._(
      input,
      index,
      _rowOfAtom(index),
      rect,
      _parent!,
    );
  }

  void _appendBackground(int index, _RubyBinding binding) {
    final font = _backgroundFonts[index];
    if (font == null) return;
    final parent = _parent!.content;
    final strut = font.background.fontStrut;
    if (strut.identity != parent.identity ||
        strut.fontRevision != parent.fontRevision ||
        strut.styleRevision != parent.styleRevision) {
      _fail(ForumBodyInlineViewFailure.identity);
    }
    final layout = _parent!.layout;
    final row = _rowOfAtom(index);
    final origin =
        layout.atomBoxes[index].toRect().topLeft - Offset(0, _fragment!.top);
    _backgroundRegions.add(
      font,
      row,
      Rect.fromLTWH(
        origin.dx,
        origin.dy + binding.baseline - font.alphabeticBaseline,
        binding.size.width,
        font.height,
      ),
    );
  }

  Rect _rootRowAllocation(int index) {
    final layout = _parent!.layout;
    final row = _rowOfAtom(index);
    // Use the published row frame: native line.top can exclude fractional
    // paragraph leading even though that strip belongs to this fragment.
    final allocation = layout.fragment(row, row + 1);
    final box = layout.atomBoxes[index];
    return Rect.fromLTRB(
      0,
      allocation.top - box.top,
      box.right - box.left,
      allocation.bottom - box.top,
    );
  }

  int _rowOfAtom(int index) {
    final layout = _parent!.layout;
    final engineOffset = layout.projection.atoms[index].engineUtf16;
    var low = startLine, high = endLine;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (layout.lines[middle].engineCoverageEndUtf16 <= engineOffset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    if (low >= endLine ||
        layout.lines[low].engineCoverageStartUtf16 > engineOffset) {
      _fail(ForumBodyInlineViewFailure.coverage);
    }
    return low;
  }

  void _own(ForumBodyNativeParagraphLease lease) {
    if (!_cache!.ownsLease(lease) ||
        (lease is ForumBodyTextLease && !lease.layout.isPaintPrepared) ||
        !_checked.add(lease)) {
      _fail(ForumBodyInlineViewFailure.leases);
    }
  }

  ForumBodyInlineParagraphView takeView() => _operate(() {
    _guard();
    if (!isReady) throw StateError('Inline view assembly is incomplete');
    final backgrounds = _backgroundRegions.take();
    final result = _fragment == null
        ? ForumBodyInlineParagraphView._empty(_parent!)
        : ForumBodyInlineParagraphView._(
            _parent!,
            _fragment!,
            UnmodifiableMapView(_bindings),
            backgrounds.surfaces,
            backgrounds.rows,
            UnmodifiableMapView(_images),
          );
    _parent = null;
    _groups = const {};
    _baselines = const {};
    _inlineBoxes = const {};
    _segments = const {};
    _spaces = const {};
    _trees = const {};
    _bindings = {};
    _images = const {};
    _state = _ViewAssemblyState.transferred;
    _dropOwner();
    return result;
  });

  T _operate<T>(T Function() action) {
    if (_operating) throw StateError('Inline view assembly is reentrant');
    _operating = true;
    try {
      return action();
    } on ForumBodyParagraphInputException catch (error) {
      _retire(_ViewAssemblyState.failed);
      _fail(
        error.failure == ForumBodyParagraphInputFailure.identity
            ? ForumBodyInlineViewFailure.identity
            : ForumBodyInlineViewFailure.coverage,
      );
    } catch (_) {
      _retire(_ViewAssemblyState.failed);
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _guard() {
    if (_state != _ViewAssemblyState.active && !isReady) {
      throw StateError('Inline view assembly is retired');
    }
    _ensureOwner?.call();
    if ((_state != _ViewAssemblyState.active && !isReady) || _cache!.isClosed) {
      throw StateError('Inline view owner is retired');
    }
    // Cheap liveness checks follow existing group/segment ownership guards;
    // only source decisions/indexing are charged as numeric member work.
    for (final lease in _checked) {
      if (!_cache!.ownsLease(lease)) {
        throw StateError('Inline view member is retired');
      }
    }
  }

  static Never _fail(ForumBodyInlineViewFailure failure) =>
      ForumBodyInlineParagraphView._fail(failure);
  void _retire(_ViewAssemblyState state) {
    if (_state != _ViewAssemblyState.active && !isReady) return;
    _state = state;
    _binding?.close();
    _binding = null;
    for (final group in _groups.values) {
      group.close();
    }
    for (final text in _baselines.values) {
      text.close();
    }
    for (final view in _inlineBoxes.values) {
      view.close();
    }
    for (final segment in _segments.values) {
      segment.close();
    }
    for (final space in _spaces.values) {
      space.close();
    }
    for (final tree in _trees.values) {
      tree.close();
    }
    _groups = const {};
    _baselines = const {};
    _inlineBoxes = const {};
    _segments = const {};
    _spaces = const {};
    _trees = const {};
    _bindings = {};
    for (final image in _images.values) {
      image._retire();
    }
    _images = const {};
    _parent?.release();
    _parent = null;
    _dropOwner();
  }

  void _dropOwner() {
    _cache = null;
    _fragment = null;
    _ensureOwner = null;
    _checked.clear();
    _backgroundFonts = const {};
    _rootFonts = const {};
    _bindingFrame = null;
    _backgroundRegions.clear();
  }

  void close() => _retire(_ViewAssemblyState.closed);
}
