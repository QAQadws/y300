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
    Map<int, ForumBodyRubySegmentLayout> rubySegments = const {},
    Map<int, ForumBodyRubySoftSpaceLayout> rubySpaces = const {},
    Map<int, ForumBodyRubyContainerFontBox> containerBackgrounds = const {},
    void Function()? ensureOwner,
  }) : _cache = cache,
       _parent = parent,
       _groups = Map.of(rubyGroups),
       _segments = Map.of(rubySegments),
       _spaces = Map.of(rubySpaces),
       _backgroundFonts = Map.of(containerBackgrounds),
       _ensureOwner = ensureOwner;
  ForumBodyParagraphCache? _cache;
  ForumBodyInlineParagraphLease? _parent;
  Map<int, ForumBodyRubyGroupLayout> _groups;
  Map<int, ForumBodyRubySegmentLayout> _segments;
  Map<int, ForumBodyRubySoftSpaceLayout> _spaces;
  Map<int, ForumBodyRubyContainerFontBox> _backgroundFonts;
  final _backgroundRegions = _RubyBackgroundRegions();
  void Function()? _ensureOwner;
  final int startLine;
  final int endLine;
  ForumBodyInlineParagraphFragment? _fragment;
  Map<int, _RubyBinding> _bindings = {};
  final _checked = Set<ForumBodyNativeParagraphLease>.identity();
  _RubyBindingWork? _binding;
  var _bindingIndex = -1;
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
    for (final segment in _segments.values) ...segment.nativeLeases,
    for (final space in _spaces.values) ...space.nativeLeases,
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
                _segments.isNotEmpty ||
                _spaces.isNotEmpty) {
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
          work += _binding!.advance(maxParts: maxParts - work);
          if (_binding!.isComplete) {
            _bindings[_bindingIndex] = _binding!.takeBinding();
            _appendBackground(_bindingIndex, _bindings[_bindingIndex]!);
            _binding = null;
            _preparedAtoms++;
          }
        } else if (_atom < _parent!.layout.projection.atoms.length) {
          final atom = _parent!.layout.projection.atoms[_atom++];
          if (atom.engineUtf16 >= _fragment!.engineCoverageStartUtf16 &&
              atom.engineUtf16 < _fragment!.engineCoverageEndUtf16 &&
              !_parent!.layout.isAtomTrimmed(atom.index)) {
            final group = _groups[atom.index];
            final segment = _segments[atom.index];
            final space = _spaces[atom.index];
            if ((group != null ? 1 : 0) +
                        (segment != null ? 1 : 0) +
                        (space != null ? 1 : 0) >
                    1 ||
                atom.isSoftSpace != (space != null)) {
              _fail(ForumBodyInlineViewFailure.leases);
            }
            if (group == null && segment == null && space == null) {
              _fail(ForumBodyInlineViewFailure.coverage);
            }
            final size = group?.size ?? segment?.size ?? space!.size;
            final baseline =
                group?.baseline ?? segment?.baseline ?? space!.baseline;
            final dimension = _parent!.layout.dimensions[atom.index];
            if ((dimension.size.width - size.width).abs() > 1e-4 ||
                (dimension.size.height - size.height).abs() > 1e-4 ||
                (dimension.baselineOffset! - baseline).abs() > 1e-4) {
              _fail(ForumBodyInlineViewFailure.geometry);
            }
            _bindingIndex = atom.index;
            _binding = _RubyBindingWork(
              content: _parent!.content,
              index: atom.index,
              group: group,
              segment: segment,
              space: space,
              own: _own,
            );
          }
          work++;
        } else {
          if (_bindings.length !=
              _groups.length + _segments.length + _spaces.length) {
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
    final origin =
        layout.atomBoxes[index].toRect().topLeft - Offset(0, _fragment!.top);
    _backgroundRegions.add(
      font,
      low,
      Rect.fromLTWH(
        origin.dx,
        origin.dy + binding.baseline - font.alphabeticBaseline,
        binding.size.width,
        font.height,
      ),
    );
  }

  void _own(ForumBodyTextLease lease) {
    if (!_cache!.ownsLease(lease) ||
        !lease.layout.isPaintPrepared ||
        !_checked.add(lease)) {
      _fail(ForumBodyInlineViewFailure.leases);
    }
  }

  ForumBodyInlineParagraphView takeView() => _operate(() {
    _guard();
    if (!isReady) throw StateError('Inline view assembly is incomplete');
    final result = _fragment == null
        ? ForumBodyInlineParagraphView._empty(_parent!)
        : ForumBodyInlineParagraphView._(
            _parent!,
            _fragment!,
            UnmodifiableMapView(_bindings),
            _backgroundRegions.take(),
          );
    _parent = null;
    _groups = const {};
    _segments = const {};
    _spaces = const {};
    _bindings = {};
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
    for (final segment in _segments.values) {
      segment.close();
    }
    for (final space in _spaces.values) {
      space.close();
    }
    _groups = const {};
    _segments = const {};
    _spaces = const {};
    _bindings = {};
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
    _backgroundRegions.clear();
  }

  void close() => _retire(_ViewAssemblyState.closed);
}
