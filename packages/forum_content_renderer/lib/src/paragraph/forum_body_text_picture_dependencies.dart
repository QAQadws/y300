part of 'forum_body_paragraph_cache.dart';

/// Own each actual alias once even when several row selectors borrow it.
/// Mutable assembly storage transfers here without a final scan or copy.
final class _TextPictureDependencies {
  _TextPictureDependencies(
    this.resources,
    this.rows,
    this.inlineRows,
    this.leases,
  );
  Map<_TextPictureDependency, ForumBodyNativeParagraphLease> resources;
  Map<_TextPictureDependency, ForumBodyParagraphRowView> rows;
  Map<_TextPictureDependency, ForumBodyInlinePaintRowView> inlineRows;
  List<ForumBodyNativeParagraphLease> leases;
  void close() {
    final owned = leases;
    resources = {};
    rows = {};
    inlineRows = {};
    leases = [];
    Object? failure;
    StackTrace? stack;
    for (final lease in owned) {
      try {
        lease.release();
      } catch (error, trace) {
        failure ??= error;
        stack ??= trace;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, stack!);
  }
}

enum _PictureDependencyPhase {
  commands,
  text,
  marks,
  pictures,
  rows,
  inlineRows,
  publish,
  ready,
  transferred,
  closed,
}

/// Shared by immediate and cooperative scene preparation. One advance indexes
/// one command, opens/advances one caller iterator, adopts one resource/row, or
/// publishes. Foreign iterators and row-owner callbacks remain guarded.
final class _TextPictureDependencyWork {
  _TextPictureDependencyWork({
    required ForumBodyParagraphCache cache,
    required ForumBodyTextPictureInput input,
    required Iterable<ForumBodyTextLease> text,
    required Iterable<ForumBodyEmphasisMarkLease> marks,
    required Iterable<ForumBodyTextPictureLease> pictures,
    required Iterable<ForumBodyParagraphRowView> rows,
    required Iterable<ForumBodyInlinePaintRowView> inlineRows,
    required void Function() ensureOwner,
  }) : _cache = cache,
       _input = input,
       _text = text,
       _marks = marks,
       _pictures = pictures,
       _rows = rows,
       _inlineRows = inlineRows,
       _ensureOwner = ensureOwner;
  ForumBodyParagraphCache? _cache;
  ForumBodyTextPictureInput? _input;
  Iterable<ForumBodyTextLease>? _text;
  Iterable<ForumBodyEmphasisMarkLease>? _marks;
  Iterable<ForumBodyTextPictureLease>? _pictures;
  Iterable<ForumBodyParagraphRowView>? _rows;
  Iterable<ForumBodyInlinePaintRowView>? _inlineRows;
  Iterator<ForumBodyNativeParagraphLease>? _iterator;
  Iterator<ForumBodyParagraphRowView>? _rowIterator;
  Iterator<ForumBodyInlinePaintRowView>? _inlineIterator;
  void Function()? _ensureOwner;
  Set<_TextPictureDependency> _wanted = {};
  Map<_TextPictureDependency, ForumBodyNativeParagraphLease> _resources = {};
  Map<_TextPictureDependency, ForumBodyParagraphRowView> _rowViews = {};
  Map<_TextPictureDependency, ForumBodyInlinePaintRowView> _inlineViews = {};
  Map<
    ({Object identity, ForumBodyInlineSpanContent content}),
    ForumBodyInlineParagraphLease
  >
  _inlineParents = {};
  Map<
    ({Object identity, ForumBodyParagraphContent content}),
    ForumBodyParagraphLease
  >
  _rowParents = {};
  List<ForumBodyNativeParagraphLease> _aliases = [];
  _TextPictureDependencies? _result;
  var _phase = _PictureDependencyPhase.commands;
  int _index = 0, _inspected = 0;
  bool get isReady => _phase == _PictureDependencyPhase.ready;
  List<ForumBodyNativeParagraphLease> get leases => _result?.leases ?? _aliases;

  void advance() {
    _guard();
    switch (_phase) {
      case _PictureDependencyPhase.commands:
        if (_index < _input!.commands.length) {
          final command = _input!.commands[_index++];
          if (!command.isFill) _wanted.add(command._dependency);
        } else {
          _phase = _PictureDependencyPhase.text;
        }
      case _PictureDependencyPhase.text:
      case _PictureDependencyPhase.marks:
      case _PictureDependencyPhase.pictures:
        _advanceResources();
      case _PictureDependencyPhase.rows:
        _advanceRows();
      case _PictureDependencyPhase.inlineRows:
        _advanceInlineRows();
      case _PictureDependencyPhase.publish:
        if (_resources.length != _wanted.length) {
          throw ArgumentError('Missing text picture dependency');
        }
        _result = _TextPictureDependencies(
          _resources,
          _rowViews,
          _inlineViews,
          _aliases,
        );
        _resources = {};
        _rowViews = {};
        _inlineViews = {};
        _aliases = [];
        _phase = _PictureDependencyPhase.ready;
        _dropInputs();
      case _PictureDependencyPhase.ready:
      case _PictureDependencyPhase.transferred:
      case _PictureDependencyPhase.closed:
        throw StateError('Text picture dependency assembly is retired');
    }
    _guard();
  }

  void _advanceResources() {
    final current = _iterator;
    if (current == null) {
      final Iterable<ForumBodyNativeParagraphLease> source = switch (_phase) {
        _PictureDependencyPhase.text => _text!,
        _PictureDependencyPhase.marks => _marks!,
        _PictureDependencyPhase.pictures => _pictures!,
        _ => throw StateError('Invalid picture dependency phase'),
      };
      final next = source.iterator;
      _guard();
      _iterator = next;
    } else {
      final hasNext = current.moveNext();
      _guard();
      if (hasNext) {
        final lease = current.current;
        _guard();
        _count();
        _adopt(lease);
      } else {
        _iterator = null;
        if (_phase == _PictureDependencyPhase.text) {
          _text = null;
          _phase = _PictureDependencyPhase.marks;
        } else if (_phase == _PictureDependencyPhase.marks) {
          _marks = null;
          _phase = _PictureDependencyPhase.pictures;
        } else {
          _pictures = null;
          _phase = _PictureDependencyPhase.rows;
        }
      }
    }
  }

  void _adopt(ForumBodyNativeParagraphLease lease) {
    final cache = _cache!;
    if (!cache.ownsLease(lease)) {
      throw StateError('Foreign text picture dependency');
    }
    final key = (
      identity: lease.nativeInputIdentity,
      bandChildIndex: lease is ForumBodyTextBandChildLease
          ? lease.childIndex
          : null,
      paragraphRow: null,
      inlineRow: null,
    );
    if (!_wanted.contains(key)) {
      throw ArgumentError('Unrequested text picture dependency');
    }
    if (!_resources.containsKey(key)) {
      final alias = switch (lease) {
        ForumBodyTextLease() => cache._aliasTextLease(lease),
        ForumBodyEmphasisMarkLease() => cache._aliasEmphasisMarkLease(lease),
        ForumBodyTextPictureLease() => cache._aliasPictureLease(lease),
        _ => throw ArgumentError('Unsupported text picture resource'),
      };
      _aliases.add(alias);
      _resources[key] = alias;
    }
  }

  void _advanceRows() {
    final current = _rowIterator;
    if (current == null) {
      final next = _rows!.iterator;
      _guard();
      _rowIterator = next;
    } else {
      final hasNext = current.moveNext();
      _guard();
      if (hasNext) {
        final row = current.current;
        _guard();
        _count();
        _adoptRow(row);
      } else {
        _rows = null;
        _rowIterator = null;
        _phase = _PictureDependencyPhase.inlineRows;
      }
    }
  }

  void _adoptRow(ForumBodyParagraphRowView row) {
    final cache = _cache!, parent = row.parent;
    if (!cache.ownsLease(parent) || !row.isPaintPrepared) {
      throw StateError('Foreign or unprepared paragraph row');
    }
    final identity = row.nativeInputIdentity;
    _guard();
    final key = (
      identity: identity,
      bandChildIndex: null,
      paragraphRow: row.selector,
      inlineRow: null,
    );
    if (!_wanted.contains(key)) {
      throw ArgumentError('Unrequested paragraph row dependency');
    }
    if (!_resources.containsKey(key)) {
      // Equal native keys do not identify the current source parent. Several
      // selectors share an alias only for that same qualified content object.
      final parentKey = (
        identity: parent.nativeInputIdentity,
        content: parent.content,
      );
      var alias = _rowParents[parentKey];
      if (alias == null) {
        alias = cache._aliasTextLease(parent) as ForumBodyParagraphLease;
        _aliases.add(alias);
        _rowParents[parentKey] = alias;
      }
      _resources[key] = alias;
      final bound = ForumBodyParagraphRowView.bind(
        parent: alias,
        metrics: row.metrics,
        ensureOwner: _ensureOwner!,
      );
      _guard();
      _rowViews[key] = bound;
    }
  }

  void _count() {
    if (++_inspected > _input!.commands.length) {
      throw ArgumentError('Excess text picture dependencies');
    }
  }

  void _advanceInlineRows() {
    final current = _inlineIterator;
    if (current == null) {
      final next = _inlineRows!.iterator;
      _guard();
      _inlineIterator = next;
    } else {
      final more = current.moveNext();
      _guard();
      if (more) {
        final row = current.current;
        _guard();
        _count();
        _adoptInlineRow(row);
      } else {
        _inlineRows = null;
        _inlineIterator = null;
        _phase = _PictureDependencyPhase.publish;
      }
    }
  }

  void _adoptInlineRow(ForumBodyInlinePaintRowView row) {
    final cache = _cache!, parent = row.parent;
    if (!cache.ownsLease(parent) || !row.isPaintPrepared) {
      throw StateError('Foreign or unprepared inline row');
    }
    final identity = row.nativeInputIdentity;
    _guard();
    final key = (
      identity: identity,
      bandChildIndex: null,
      paragraphRow: null,
      inlineRow: row.selector,
    );
    if (!_wanted.contains(key)) {
      throw ArgumentError('Unrequested inline row dependency');
    }
    if (!_resources.containsKey(key)) {
      final parentKey = (identity: identity, content: parent.content);
      var alias = _inlineParents[parentKey];
      if (alias == null) {
        alias = cache._aliasInlineLease(parent);
        _aliases.add(alias);
        _inlineParents[parentKey] = alias;
      }
      _resources[key] = alias;
      final bound = row.bindAlias(parent: alias, ensureOwner: _ensureOwner!);
      _guard();
      _inlineViews[key] = bound;
    }
  }

  _TextPictureDependencies takeDependencies() {
    _guard();
    if (!isReady) throw StateError('Text picture dependencies are incomplete');
    final result = _result!;
    _result = null;
    _phase = _PictureDependencyPhase.transferred;
    _cache = null;
    _ensureOwner = null;
    return result;
  }

  void _guard() {
    if (_phase == _PictureDependencyPhase.closed ||
        _phase == _PictureDependencyPhase.transferred) {
      throw StateError('Text picture dependency assembly is retired');
    }
    _ensureOwner!();
    if (_phase == _PictureDependencyPhase.closed || _cache!.isClosed) {
      throw StateError('Text picture dependency owner is retired');
    }
  }

  void _dropInputs() {
    _input = null;
    _text = null;
    _marks = null;
    _pictures = null;
    _rows = null;
    _inlineRows = null;
    _iterator = null;
    _rowIterator = null;
    _inlineIterator = null;
    _wanted = {};
    _rowParents = {};
    _inlineParents = {};
  }

  void close() {
    if (_phase == _PictureDependencyPhase.closed ||
        _phase == _PictureDependencyPhase.transferred) {
      return;
    }
    _phase = _PictureDependencyPhase.closed;
    final result = _result,
        owned = _TextPictureDependencies(
          _resources,
          _rowViews,
          _inlineViews,
          _aliases,
        );
    _result = null;
    _resources = {};
    _rowViews = {};
    _inlineViews = {};
    _aliases = [];
    _dropInputs();
    _cache = null;
    _ensureOwner = null;
    try {
      result?.close();
    } finally {
      owned.close();
    }
  }
}
