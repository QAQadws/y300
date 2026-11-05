import 'package:y300/features/content_rendering_shared/content_rendering.dart';

enum NovelReaderNativePrefixState {
  active,
  waitingForPages,
  matched,
  mismatched,
  closed,
}

enum NovelReaderNativePrefixMismatch {
  scope,
  truncated,
  page,
  fragment,
  rule,
  background,
}

final class NovelReaderNativePrefixStep {
  const NovelReaderNativePrefixStep(
    this.pagesCompared,
    this.fragmentsCompared,
    this.state,
  );
  final int pagesCompared;
  final int fragmentsCompared;
  final NovelReaderNativePrefixState state;
}

/// Bounded retry verification from page zero, never a random-start checkpoint.
/// Only immutable page metadata is borrowed. No session, paragraph, lease,
/// semantic document or callback is retained; terminal states drop both prefixes.
final class NovelReaderNativePrefixVerifier {
  NovelReaderNativePrefixVerifier({
    required ForumBodyTextPageSnapshot previous,
    required String previousPaginationKey,
    required ForumBodyTextPageSnapshot incoming,
    required String incomingPaginationKey,
  }) : _previous = previous,
       _incoming = incoming,
       _identity = previous.identity,
       _layoutId = incoming.layoutId,
       _key = previousPaginationKey,
       _width = previous.width,
       _height = previous.height,
       prefixLength = previous.length {
    _checkScope(previous, previousPaginationKey);
    if (state == NovelReaderNativePrefixState.active) {
      update(incoming, paginationKey: incomingPaginationKey);
    }
  }
  ForumBodyTextPageSnapshot? _previous;
  ForumBodyTextPageSnapshot? _incoming;
  final ForumBodyIdentity _identity;
  final String _layoutId;
  final String _key;
  final double _width;
  final double _height;
  final int prefixLength;
  int _page = 0;
  int _fragment = 0;
  int _rule = 0;
  int _background = 0;
  int _incomingLength = 0;
  bool _incomingComplete = false;
  NovelReaderNativePrefixState _state = NovelReaderNativePrefixState.active;
  NovelReaderNativePrefixMismatch? _mismatch;

  NovelReaderNativePrefixState get state => _state;
  NovelReaderNativePrefixMismatch? get mismatch => _mismatch;
  int get verifiedPageCount => _page;

  /// Incoming publications belong to one actual append-only retry session.
  /// A different retry uses a new verifier/request, even for the same document.
  void update(
    ForumBodyTextPageSnapshot incoming, {
    required String paginationKey,
  }) {
    if (_state != NovelReaderNativePrefixState.active &&
        _state != NovelReaderNativePrefixState.waitingForPages) {
      throw StateError('Native prefix verifier is retired');
    }
    _checkScope(incoming, paginationKey);
    if (_state == NovelReaderNativePrefixState.mismatched) return;
    if (incoming.layoutId != _layoutId ||
        incoming.length < _incomingLength ||
        (_incomingComplete && !incoming.isComplete)) {
      _fail(NovelReaderNativePrefixMismatch.scope);
      return;
    }
    if (incoming.isComplete && incoming.length < prefixLength) {
      _fail(NovelReaderNativePrefixMismatch.truncated);
      return;
    }
    _incoming = incoming;
    _incomingLength = incoming.length;
    _incomingComplete = incoming.isComplete;
    if (_page == prefixLength) {
      _finish();
    } else {
      _state = _page < incoming.length
          ? NovelReaderNativePrefixState.active
          : NovelReaderNativePrefixState.waitingForPages;
    }
  }

  NovelReaderNativePrefixStep advance({
    required int maxPages,
    required int maxFragments,
  }) {
    if (_state != NovelReaderNativePrefixState.active &&
        _state != NovelReaderNativePrefixState.waitingForPages) {
      throw StateError('Native prefix verifier is retired');
    }
    if (maxPages <= 0 || maxFragments <= 0) {
      throw ArgumentError('Invalid prefix work budget');
    }
    var pages = 0;
    var fragments = 0;
    while (_state == NovelReaderNativePrefixState.active &&
        pages < maxPages &&
        fragments < maxFragments) {
      final old = _previous![_page];
      final incoming = _incoming![_page];
      if (old.index != incoming.index ||
          old.usedHeight != incoming.usedHeight ||
          old.fragments.length != incoming.fragments.length ||
          old.rules.length != incoming.rules.length ||
          old.backgrounds.length != incoming.backgrounds.length) {
        _fail(NovelReaderNativePrefixMismatch.page);
        break;
      }
      if (_fragment < old.fragments.length) {
        if (!_sameFragment(
          old.fragments[_fragment],
          incoming.fragments[_fragment],
        )) {
          _fail(NovelReaderNativePrefixMismatch.fragment);
          break;
        }
        _fragment++;
        fragments++;
      } else if (_rule < old.rules.length) {
        final a = old.rules[_rule], b = incoming.rules[_rule];
        if (a.path != b.path ||
            a.left != b.left ||
            a.top != b.top ||
            a.width != b.width ||
            a.thickness != b.thickness ||
            a.color != b.color) {
          _fail(NovelReaderNativePrefixMismatch.rule);
          break;
        }
        _rule++;
        fragments++;
      } else if (_background < old.backgrounds.length) {
        final a = old.backgrounds[_background],
            b = incoming.backgrounds[_background];
        if (a.path != b.path ||
            a.left != b.left ||
            a.top != b.top ||
            a.width != b.width ||
            a.height != b.height ||
            a.color != b.color ||
            a.startsBox != b.startsBox ||
            a.endsBox != b.endsBox ||
            a.quoteDecoration?.borderColor != b.quoteDecoration?.borderColor) {
          _fail(NovelReaderNativePrefixMismatch.background);
          break;
        }
        _background++;
        fragments++;
      }
      if (_fragment == old.fragments.length &&
          _rule == old.rules.length &&
          _background == old.backgrounds.length) {
        _fragment = 0;
        _rule = 0;
        _background = 0;
        _page++;
        pages++;
        if (_page == prefixLength) {
          _finish();
        } else if (_page == _incoming!.length) {
          _state = NovelReaderNativePrefixState.waitingForPages;
        }
      }
    }
    return NovelReaderNativePrefixStep(pages, fragments, _state);
  }

  void _checkScope(ForumBodyTextPageSnapshot prefix, String key) {
    if (_key.isEmpty ||
        key != _key ||
        prefix.identity != _identity ||
        prefix.width != _width ||
        prefix.height != _height ||
        prefix.backendRevision != ForumBodyParagraphLayout.backendRevision ||
        prefix.composerRevision != ForumBodyTextPageComposer.revision) {
      _fail(NovelReaderNativePrefixMismatch.scope);
    }
  }

  bool _sameFragment(
    ForumBodyTextPageFragment old,
    ForumBodyTextPageFragment next,
  ) =>
      old.paragraphIndex == next.paragraphIndex &&
      old.kind == next.kind &&
      old.imageFrame == next.imageFrame &&
      old.listMarker?.baseline == next.listMarker?.baseline &&
      old.listMarker?.bounds == next.listMarker?.bounds &&
      old.path == next.path &&
      old.fontRevision == next.fontRevision &&
      old.styleRevision == next.styleRevision &&
      old.startLine == next.startLine &&
      old.endLine == next.endLine &&
      old.coverageStartUtf16 == next.coverageStartUtf16 &&
      old.coverageEndUtf16 == next.coverageEndUtf16 &&
      old.sourceHint == next.sourceHint &&
      old.left == next.left &&
      old.top == next.top &&
      old.width == next.width &&
      old.height == next.height;

  void _finish() {
    _state = NovelReaderNativePrefixState.matched;
    _drop();
  }

  void _fail(NovelReaderNativePrefixMismatch reason) {
    _mismatch = reason;
    _state = NovelReaderNativePrefixState.mismatched;
    _drop();
  }

  void _drop() {
    _previous = null;
    _incoming = null;
  }

  void close() {
    _state = NovelReaderNativePrefixState.closed;
    _drop();
  }
}
