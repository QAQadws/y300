import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_prefix_verifier.dart';

import '../test_support/native_reader_test_fixture.dart';

NovelReaderNativePrefixVerifier _verifier(
  ForumBodyTextPageSnapshot old,
  ForumBodyTextPageSnapshot next, {
  String key = 'geometry',
}) {
  final value = NovelReaderNativePrefixVerifier(
    previous: old,
    previousPaginationKey: 'geometry',
    incoming: next,
    incomingPaginationKey: key,
  );
  addTearDown(value.close);
  return value;
}

void _compareAvailable(NovelReaderNativePrefixVerifier verifier) {
  while (verifier.state == NovelReaderNativePrefixState.active) {
    final step = verifier.advance(maxPages: 1, maxFragments: 1);
    expect(step.pagesCompared, lessThanOrEqualTo(1));
    expect(step.fragmentsCompared, lessThanOrEqualTo(1));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const html = '<p>ab</p><p>cd</p><p>ef</p>';

  test('quote border paint is checked even when text, source and fill geometry are identical', () {
    const source = '<blockquote><p>quote</p></blockquote>';
    ForumBodyReaderStyle reader(Color border) => ForumBodyReaderStyle(
      textStyle: const TextStyle(
        fontSize: 10,
        height: 1,
        fontFamily: 'Ahem',
        color: Color(0xff000000),
      ),
      fontRevision: 'same',
      linkColor: border,
      paragraphAfter: 0,
    );
    final old = NativeReaderTestFixture(
      source,
      reader: reader(const Color(0xffff0000)),
    );
    final next = NativeReaderTestFixture(
      source,
      reader: reader(const Color(0xff0000ff)),
      layoutId: 'retry',
    );
    final verifier = _verifier(old.session.snapshot, next.session.snapshot);
    _compareAvailable(verifier);
    expect(verifier.mismatch, NovelReaderNativePrefixMismatch.background);
    expect(old.session.snapshot.single.backgrounds.single.endsBox, isTrue);
  });

  test('padding backgrounds share retry work budgets and compare actual paint color', () {
    const source =
        '<div style="background:currentColor;padding-top:45px"><p>x</p></div>';
    ForumBodyReaderStyle reader(Color color) => ForumBodyReaderStyle(
      textStyle: TextStyle(fontSize: 10, color: color),
      fontRevision: 'same',
      linkColor: color,
    );
    final old = NativeReaderTestFixture(
      source,
      height: 20,
      reader: reader(const Color(0xffff0000)),
    );
    final next = NativeReaderTestFixture(
      source,
      height: 20,
      reader: reader(const Color(0xffff0000)),
      layoutId: 'retry',
    );
    final verifier = _verifier(old.session.snapshot, next.session.snapshot);
    var compared = 0;
    while (verifier.state == NovelReaderNativePrefixState.active) {
      final step = verifier.advance(maxPages: 1, maxFragments: 1);
      compared += step.fragmentsCompared;
      expect(step.fragmentsCompared, lessThanOrEqualTo(1));
    }
    expect(compared, 4);
    expect(verifier.state, NovelReaderNativePrefixState.matched);
    final changed = NativeReaderTestFixture(
      source,
      height: 20,
      reader: reader(const Color(0xff0000ff)),
      layoutId: 'changed',
    );
    final stale = _verifier(old.session.snapshot, changed.session.snapshot);
    _compareAvailable(stale);
    expect(stale.mismatch, NovelReaderNativePrefixMismatch.background);
    expect(
      old.session.snapshot.first.backgrounds.single.color,
      const Color(0xffff0000),
    );
  });

  test('rule-only retry pages compare every paint item within the existing work budget', () {
    final source = List.filled(9, '<hr style="margin:0">').join();
    final old = NativeReaderTestFixture(source, height: 4);
    final next = NativeReaderTestFixture(source, height: 4, layoutId: 'retry');
    final verifier = _verifier(old.session.snapshot, next.session.snapshot);
    var compared = 0;
    while (verifier.state == NovelReaderNativePrefixState.active) {
      final step = verifier.advance(maxPages: 1, maxFragments: 1);
      expect(step.fragmentsCompared, lessThanOrEqualTo(1));
      compared += step.fragmentsCompared;
    }
    expect(compared, 9);
    expect(verifier.state, NovelReaderNativePrefixState.matched);
  });

  test(
    'same geometry cannot hide changed rule paint under a stale fingerprint',
    () {
      ForumBodyReaderStyle reader(Color color) => ForumBodyReaderStyle(
        textStyle: TextStyle(fontSize: 10, color: color),
        fontRevision: 'same',
        linkColor: color,
      );
      const source = '<hr style="margin:0">';
      final old = NativeReaderTestFixture(
        source,
        reader: reader(const Color(0xffff0000)),
      );
      final next = NativeReaderTestFixture(
        source,
        reader: reader(const Color(0xff0000ff)),
        layoutId: 'retry',
      );
      final verifier = _verifier(old.session.snapshot, next.session.snapshot);
      _compareAvailable(verifier);
      expect(verifier.state, NovelReaderNativePrefixState.mismatched);
      expect(verifier.mismatch, NovelReaderNativePrefixMismatch.rule);
      expect(
        old.session.snapshot.single.rules.single.color,
        const Color(0xffff0000),
      );
    },
  );

  test(
    'a new request matches fixed prefix incrementally without new shaping',
    () {
      final previous = NativeReaderTestFixture(html, width: 20, height: 10);
      final retry = NativeReaderTestFixture(
        html,
        width: 20,
        height: 10,
        complete: false,
        layoutId: 'retry',
      );
      final empty = retry.session.snapshot;
      final verifier = _verifier(previous.session.snapshot, empty);
      expect(verifier.state, NovelReaderNativePrefixState.waitingForPages);
      retry.finishSource(pages: 1);
      final one = retry.session.snapshot;
      verifier.update(one, paginationKey: 'geometry');
      final builds = retry.cache.layoutBuildCount;
      _compareAvailable(verifier);
      expect(verifier.verifiedPageCount, 1);
      expect(verifier.state, NovelReaderNativePrefixState.waitingForPages);
      expect(retry.cache.layoutBuildCount, builds);
      retry.finishSource();
      verifier.update(retry.session.snapshot, paginationKey: 'geometry');
      _compareAvailable(verifier);
      expect(verifier.state, NovelReaderNativePrefixState.matched);
      expect(empty.length, 0);
      expect(one.length, 1);
      expect(previous.session.isClosed, isFalse);
      expect(retry.session.activeIssuedLeases, 0);
      expect(
        () => verifier.advance(maxPages: 1, maxFragments: 1),
        throwsStateError,
      );
    },
  );

  test('a matching empty prefix still requires the same document and stable layout key', () {
    final old = NativeReaderTestFixture(html, complete: false);
    final retry = NativeReaderTestFixture(
      html,
      complete: false,
      layoutId: 'retry',
    );
    expect(
      _verifier(old.session.snapshot, retry.session.snapshot).state,
      NovelReaderNativePrefixState.matched,
    );
    expect(
      _verifier(
        old.session.snapshot,
        retry.session.snapshot,
        key: 'changed',
      ).mismatch,
      NovelReaderNativePrefixMismatch.scope,
    );
    final foreign = NativeReaderTestFixture(
      '<p>different</p>',
      complete: false,
    );
    expect(
      _verifier(old.session.snapshot, foreign.session.snapshot).mismatch,
      NovelReaderNativePrefixMismatch.scope,
    );
  });

  test('actual geometry catches a stale caller fingerprint and preserves old view leases', () {
    final old = NativeReaderTestFixture(html, width: 100, height: 40);
    final leases = old.session.preparePageLeases(0);
    final retry = NativeReaderTestFixture(
      html,
      width: 100,
      height: 40,
      textScaler: const TextScaler.linear(1.1),
      layoutId: 'retry',
    );
    final verifier = _verifier(old.session.snapshot, retry.session.snapshot);
    _compareAvailable(verifier);
    expect(verifier.state, NovelReaderNativePrefixState.mismatched);
    expect(verifier.mismatch, NovelReaderNativePrefixMismatch.page);
    expect(leases.every((lease) => lease.isActive), isTrue);
    for (final lease in leases) {
      lease.release();
    }
  });

  test(
    'a retry EOF shorter than the old stable prefix is an explicit mismatch',
    () {
      final old = NativeReaderTestFixture(
        html,
        width: 20,
        height: 20,
        textScaler: const TextScaler.linear(2),
      );
      final retry = NativeReaderTestFixture(
        html,
        width: 20,
        height: 20,
        layoutId: 'retry',
      );
      expect(
        retry.session.snapshot.length,
        lessThan(old.session.snapshot.length),
      );
      final verifier = _verifier(old.session.snapshot, retry.session.snapshot);
      expect(verifier.mismatch, NovelReaderNativePrefixMismatch.truncated);
    },
  );

  test('incoming request changes and regressing prefixes cannot reuse already verified work', () {
    final old = NativeReaderTestFixture(html, width: 20, height: 10);
    final retry = NativeReaderTestFixture(
      html,
      width: 20,
      height: 10,
      complete: false,
      layoutId: 'retry',
    );
    final empty = retry.session.snapshot;
    retry.finishSource(pages: 1);
    final verifier = _verifier(old.session.snapshot, retry.session.snapshot);
    _compareAvailable(verifier);
    verifier.update(empty, paginationKey: 'geometry');
    expect(verifier.mismatch, NovelReaderNativePrefixMismatch.scope);
    final fresh = _verifier(old.session.snapshot, retry.session.snapshot);
    final other = NativeReaderTestFixture(
      html,
      width: 20,
      height: 10,
      layoutId: 'other-retry',
    );
    fresh.update(other.session.snapshot, paginationKey: 'geometry');
    expect(fresh.mismatch, NovelReaderNativePrefixMismatch.scope);
  });

  test('blank padding pages count toward the page budget and metadata cannot bypass bounds', () {
    const padded = '<div style="padding-top:30px"><p>abc</p></div>';
    final old = NativeReaderTestFixture(padded, width: 100, height: 10);
    final retry = NativeReaderTestFixture(
      padded,
      width: 100,
      height: 10,
      layoutId: 'retry',
    );
    final verifier = _verifier(old.session.snapshot, retry.session.snapshot);
    final first = verifier.advance(maxPages: 1, maxFragments: 1);
    expect(first.pagesCompared, 1);
    expect(first.fragmentsCompared, 0);
    expect(verifier.state, NovelReaderNativePrefixState.active);
    expect(
      () => verifier.advance(maxPages: 0, maxFragments: 1),
      throwsArgumentError,
    );
    _compareAvailable(verifier);
    expect(verifier.state, NovelReaderNativePrefixState.matched);
    verifier.close();
    verifier.close();
  });
}
