import 'dart:collection';

import 'package:y300/features/novel/presentation/models/novel_reader_page_fragment.dart';

/// A fixed, read-only prefix of pages that have already been sealed.
///
/// Only [NovelReaderPageSnapshotBuilder] can create this type. Its private
/// storage only grows, so snapshots share page references without exposing
/// subsequently appended pages or allowing existing pages to be replaced.
final class NovelReaderPageSnapshot
    extends UnmodifiableListView<NovelReaderPageFragment> {
  NovelReaderPageSnapshot._(List<NovelReaderPageFragment> pages, int length)
    : super(_PagePrefix(pages, length));
}

/// Owns append-only storage for one pagination run. Pages passed to [add] must
/// already have their final content and immutable metadata.
final class NovelReaderPageSnapshotBuilder {
  final List<NovelReaderPageFragment> _pages = <NovelReaderPageFragment>[];
  NovelReaderPageSnapshot? _snapshot;

  int get length => _pages.length;

  void add(NovelReaderPageFragment page) {
    _pages.add(page);
    _snapshot = null;
  }

  NovelReaderPageSnapshot get snapshot =>
      _snapshot ??= NovelReaderPageSnapshot._(_pages, _pages.length);
}

final class _PagePrefix extends ListBase<NovelReaderPageFragment> {
  _PagePrefix(this._pages, this._length);

  final List<NovelReaderPageFragment> _pages;
  final int _length;

  @override
  int get length => _length;

  @override
  set length(int value) => throw UnsupportedError('Page snapshots are fixed.');

  @override
  NovelReaderPageFragment operator [](int index) {
    RangeError.checkValidIndex(index, this, 'index', _length);
    return _pages[index];
  }

  @override
  void operator []=(int index, NovelReaderPageFragment value) =>
      throw UnsupportedError('Page snapshots are read-only.');
}
