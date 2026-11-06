import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

ForumBodyTextBandContent band(List<String> roots, {String font = 'loaded'}) {
  final document = const ForumBodyParser().parse(
    html: '<p>${roots.join()}</p>',
    sourceId: 'band-cache',
    conversionIdentity: 'none',
  );
  final styles = const ForumBodyStyleResolver().resolve(
    document,
    ForumBodyReaderStyle(
      textStyle: const TextStyle(
        fontFamily: 'Ahem',
        fontSize: 20,
        height: 1,
        color: Color(0xff000000),
      ),
      fontRevision: font,
      linkColor: const Color(0xff0000ff),
    ),
  );
  return ForumBodyTextBandContent(
    contexts: [
      for (var i = 0; i < roots.length; i++)
        const ForumBodyParagraphContentBuilder().build(
          document: document,
          styles: styles,
          path: '0/$i',
          layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
        ),
    ],
  );
}

ForumBodyParagraphCache cache({int entries = 64, int bytes = 1 << 24}) =>
    ForumBodyParagraphCache(maxEntries: entries, maxEstimatedBytes: bytes);

ForumBodyTextBandContent heavyBand() {
  final text = [
    for (var i = 0; i < 200; i++)
      '<span style="color:${i.isEven ? '#123456' : '#654321'}">a</span>',
  ].join();
  return band(['<span>$text</span>', '<span>$text</span>']);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the same band rechecks nonlinear values even for one equal mutable scaler',
    () {
      final owner = cache();
      addTearDown(owner.close);
      final input = band([
        '<span style="font-size:10px">aa</span>',
        '<span>b</span>',
      ]);
      final scaler = _BranchScaler();
      final first = owner.acquireBandChild(
        content: input,
        childIndex: 0,
        textScaler: scaler,
      );
      final firstWidth = first.layout.width;
      scaler.ratio = 1.4;
      final second = owner.acquireBandChild(
        content: input,
        childIndex: 0,
        textScaler: scaler,
      );
      expect(second.layout.width, greaterThan(firstWidth));
      expect(owner.layoutBuildCount, 2);
      scaler.ratio = 1;
      final returned = owner.tryAcquireBandChildCached(
        content: input,
        childIndex: 0,
        textScaler: scaler,
      )!;
      expect(returned.layout.width, firstWidth);
      expect(owner.layoutBuildCount, 2);
      first.release();
      returned.release();
      owner.clearUnpinned();
      expect(second.isActive, isTrue);
      scaler.ratio = 1.4;
      final alias = owner.tryAcquireBandChildCached(
        content: input,
        childIndex: 0,
        textScaler: scaler,
      )!;
      expect(alias.layout.width, second.layout.width);
      expect(owner.layoutBuildCount, 2);
      second.release();
      alias.release();
      owner.clearUnpinned();
      expect(owner.entryCount, 0);
      expect(
        owner.tryAcquireBandChildCached(
          content: input,
          childIndex: 0,
          textScaler: scaler,
        ),
        isNull,
      );
    },
  );

  for (final close in [false, true]) {
    test(
      'an indexed band can retire during current scaler validation close=$close',
      () {
        final owner = cache();
        addTearDown(owner.close);
        final input = band(['<span>a</span>', '<span>b</span>']);
        final first = owner.acquireBandChild(content: input, childIndex: 0);
        owner.prepareBandChildPaint(first);
        first.release();
        final scaler = _OnceScaler(close ? owner.close : owner.clearUnpinned);
        if (close) {
          expect(
            () => owner.acquireBandChild(
              content: input,
              childIndex: 1,
              textScaler: scaler,
            ),
            throwsStateError,
          );
          expect(owner.estimatedRetainedBytes, 0);
        } else {
          final next = owner.acquireBandChild(
            content: input,
            childIndex: 1,
            textScaler: scaler,
          );
          expect(owner.layoutBuildCount, 2);
          expect(next.layout.isPaintPrepared, isFalse);
          expect(next.content, same(input.contexts[1]));
          next.release();
        }
        expect(owner.activeLeases, 0);
      },
    );
  }

  test('immutable band summaries keep original UTF16 and run budget costs', () {
    final owner = cache();
    addTearDown(owner.close);
    final input = band(['<span>a\u0301😀</span>', '<span><b>B</b>C</span>']);
    expect(input.textCodeUnits, 6);
    expect(input.runCount, 3);
    final lease = owner.acquireBandChild(content: input, childIndex: 0);
    expect(owner.estimatedRetainedBytes, 14432);
    lease.release();
  });

  test('64 unique children pin one entry and pictures prepare only once', () {
    final owner = cache(entries: 1);
    addTearDown(owner.close);
    final input = band([for (var i = 0; i < 64; i++) '<span>child$i</span>']);
    expect(
      owner.tryAcquireBandChildCached(content: input, childIndex: 0),
      isNull,
    );
    expect(owner.layoutBuildCount, 0);
    final leases = [
      for (var i = 0; i < 64; i++)
        owner.acquireBandChild(content: input, childIndex: i),
    ];
    expect(owner.entryCount, 1);
    expect(owner.layoutBuildCount, 1);
    expect(owner.activeLeases, 64);
    expect(owner.preparedPictureCount, 0);
    final bytes = owner.estimatedRetainedBytes;
    expect(owner.prepareBandChildPaint(leases[0]), isTrue);
    expect(owner.prepareBandChildPaint(leases[0]), isFalse);
    expect(leases[0].layout.isPaintPrepared, isTrue);
    expect(leases[1].layout.isPaintPrepared, isFalse);
    final withPicture = owner.estimatedRetainedBytes;
    expect(owner.prepareBandChildPaint(leases[1]), isFalse);
    expect(leases[1].layout.isPaintPrepared, isTrue);
    expect(owner.estimatedRetainedBytes, withPicture);
    expect(owner.preparedPictureCount, 1);
    expect(owner.pictureBuildCount, 1);
    final alias = owner.tryAcquireBandChildCached(
      content: input,
      childIndex: 0,
    )!;
    expect(alias.layout.isPaintPrepared, isTrue);
    expect(alias.content, same(input.contexts[0]));
    leases[0].release();
    expect(alias.layout.width, greaterThan(0));
    expect(owner.estimatedRetainedBytes, greaterThanOrEqualTo(bytes));
    for (final lease in leases) {
      lease.release();
    }
    owner.clearUnpinned();
    expect(owner.entryCount, 1);
    alias.release();
    owner.clearUnpinned();
    expect(owner.entryCount, 0);
    expect(owner.estimatedRetainedBytes, 0);
    expect(owner.preparedPictureCount, 0);
    expect(owner.activeLeases, 0);
  });

  test('pure whole-view probe deduplicates children without native work', () {
    final owner = cache(entries: 1);
    addTearDown(owner.close);
    final input = band(['<span>a</span>', '<b>b</b>']);
    final probe = owner.createBudgetProbe();
    addTearDown(probe.close);
    probe.includeBandChild(content: input, childIndex: 0);
    probe.includeBandChild(content: input, childIndex: 1);
    expect(owner.layoutBuildCount, 0);
    expect(owner.pictureBuildCount, 0);
    expect(owner.entryCount, 0);
    expect(
      () => probe.includeBandChild(
        content: band(['<span>different</span>']),
        childIndex: 0,
      ),
      throwsA(
        isA<ForumBodyParagraphBudgetException>().having(
          (error) => error.failure,
          'failure',
          ForumBodyParagraphBudgetFailure.content,
        ),
      ),
    );
  });

  test('source mapping, font, scaler and gutter remain native identities', () {
    final owner = cache();
    addTearDown(owner.close);
    final input = band(['<span>a</span>', '<span>b</span>']);
    final first = owner.acquireBandChild(content: input, childIndex: 0);
    final current = band(['<span>a</span>', '<span>b</span>']);
    final alias = owner.acquireBandChild(content: current, childIndex: 0);
    expect(alias.content, same(current.contexts[0]));
    expect(owner.layoutBuildCount, 1);
    final others = [
      owner.acquireBandChild(content: input, childIndex: 0, gutter: 41),
      owner.acquireBandChild(
        content: input,
        childIndex: 0,
        textScaler: TextScaler.linear(1.1),
      ),
      owner.acquireBandChild(
        content: band(['<span>a</span>', '<span>b</span>'], font: 'next'),
        childIndex: 0,
      ),
      owner.acquireBandChild(
        content: band(['<span>&#97;</span>', '<span>b</span>']),
        childIndex: 0,
      ),
    ];
    expect(owner.layoutBuildCount, 5);
    for (final lease in [first, alias, ...others]) {
      lease.release();
    }
  });

  test(
    'band and ordinary paragraphs compete in the existing pinned budget',
    () {
      final owner = cache(entries: 1);
      addTearDown(owner.close);
      final input = band(['<span>a</span>']);
      final lease = owner.acquireBandChild(content: input, childIndex: 0);
      expect(
        () => owner.acquire(content: input.contexts.single, width: 20),
        throwsA(
          isA<ForumBodyParagraphBudgetException>().having(
            (error) => error.failure,
            'failure',
            ForumBodyParagraphBudgetFailure.pinned,
          ),
        ),
      );
      expect(owner.layoutBuildCount, 1);
      lease.release();
      final plain = owner.acquire(content: input.contexts.single, width: 20);
      expect(owner.entryCount, 1);
      expect(owner.layoutBuildCount, 2);
      expect(lease.isActive, isFalse);
      plain.release();
    },
  );

  test(
    'foreign, released and caller-disposed child views cannot prepare paint',
    () {
      final owner = cache();
      final other = cache();
      addTearDown(owner.close);
      addTearDown(other.close);
      final input = band(['<span>a</span>']);
      final lease = owner.acquireBandChild(content: input, childIndex: 0);
      expect(() => other.prepareBandChildPaint(lease), throwsStateError);
      lease.layout.dispose();
      expect(owner.ownsLease(lease), isFalse);
      expect(() => owner.prepareBandChildPaint(lease), throwsStateError);
      lease.release();
      expect(owner.activeLeases, 0);
      expect(() => owner.prepareBandChildPaint(lease), throwsStateError);
    },
  );

  test(
    'picture creation can close the owner without publishing late state',
    () {
      final owner = cache();
      addTearDown(owner.close);
      final lease = owner.acquireBandChild(
        content: band(['<span>a</span>']),
        childIndex: 0,
      );
      final previous = ui.Picture.onCreate;
      ui.Picture.onCreate = (_) => owner.close();
      try {
        expect(() => owner.prepareBandChildPaint(lease), throwsStateError);
      } finally {
        ui.Picture.onCreate = previous;
      }
      expect(owner.isClosed, isTrue);
      expect(owner.activeLeases, 0);
      expect(owner.entryCount, 0);
      expect(owner.estimatedRetainedBytes, 0);
      expect(owner.pictureBuildCount, 0);
      lease.release();
    },
  );

  test('picture creation releasing the view drops only the new picture', () {
    final owner = cache();
    addTearDown(owner.close);
    final lease = owner.acquireBandChild(
      content: band(['<span>a</span>']),
      childIndex: 0,
    );
    final previous = ui.Picture.onCreate;
    ui.Picture.onCreate = (_) => lease.release();
    try {
      expect(() => owner.prepareBandChildPaint(lease), throwsStateError);
    } finally {
      ui.Picture.onCreate = previous;
    }
    expect(owner.entryCount, 1);
    expect(owner.activeLeases, 0);
    expect(owner.preparedPictureCount, 0);
    expect(owner.pictureBuildCount, 0);
  });

  test('close invoked by native disposal cannot cause late admission', () {
    final owner = cache(entries: 1);
    addTearDown(owner.close);
    final lease = owner.acquireBandChild(
      content: band(['<span>a</span>']),
      childIndex: 0,
    );
    owner.prepareBandChildPaint(lease);
    lease.release();
    final previous = ui.Picture.onDispose;
    ui.Picture.onDispose = (_) => owner.close();
    try {
      expect(
        () => owner.acquireBandChild(
          content: band(['<span>b</span>']),
          childIndex: 0,
        ),
        throwsStateError,
      );
    } finally {
      ui.Picture.onDispose = previous;
    }
    expect(owner.entryCount, 0);
    expect(owner.activeLeases, 0);
    expect(owner.estimatedRetainedBytes, 0);
  });

  test(
    'clear skips a later victim pinned by an earlier native disposal hook',
    () {
      final owner = cache();
      addTearDown(owner.close);
      final a = band(['<span>a</span>']);
      final b = band(['<span>b</span>']);
      final first = owner.acquireBandChild(content: a, childIndex: 0);
      final second = owner.acquireBandChild(content: b, childIndex: 0);
      owner.prepareBandChildPaint(first);
      first.release();
      second.release();
      ForumBodyTextBandChildLease? pinned;
      final previous = ui.Picture.onDispose;
      ui.Picture.onDispose = (_) {
        pinned = owner.tryAcquireBandChildCached(content: b, childIndex: 0);
      };
      try {
        owner.clearUnpinned();
      } finally {
        ui.Picture.onDispose = previous;
      }
      expect(pinned, isNotNull);
      expect(pinned!.isActive, isTrue);
      expect(owner.entryCount, 1);
      expect(owner.activeLeases, 1);
      pinned!.release();
      owner.clearUnpinned();
      expect(owner.estimatedRetainedBytes, 0);
    },
  );

  test(
    'same-key request from eviction observer cannot overwrite pending entry',
    () {
      final owner = cache(entries: 1);
      addTearDown(owner.close);
      final first = owner.acquireBandChild(
        content: band(['<span>a</span>']),
        childIndex: 0,
      );
      owner.prepareBandChildPaint(first);
      first.release();
      final next = band(['<span>b</span>']);
      final previous = ui.Picture.onDispose;
      ui.Picture.onDispose = (_) {
        expect(
          () => owner.acquireBandChild(content: next, childIndex: 0),
          throwsStateError,
        );
      };
      late ForumBodyTextBandChildLease result;
      try {
        result = owner.acquireBandChild(content: next, childIndex: 0);
      } finally {
        ui.Picture.onDispose = previous;
      }
      expect(owner.layoutBuildCount, 2);
      expect(owner.entryCount, 1);
      expect(owner.activeLeases, 1);
      result.release();
      owner.close();
      expect(owner.estimatedRetainedBytes, 0);
    },
  );

  test(
    'close snapshots entries before disposal hooks clear or close again',
    () {
      final owner = cache();
      final leases = [
        for (final text in ['a', 'b', 'c'])
          owner.acquireBandChild(
            content: band(['<span>$text</span>']),
            childIndex: 0,
          ),
      ];
      for (final lease in leases) {
        owner.prepareBandChildPaint(lease);
      }
      var disposed = 0;
      final previous = ui.Picture.onDispose;
      ui.Picture.onDispose = (_) {
        disposed++;
        owner.clearUnpinned();
        owner.close();
      };
      try {
        owner.close();
      } finally {
        ui.Picture.onDispose = previous;
      }
      expect(disposed, 3);
      expect(owner.entryCount, 0);
      expect(owner.estimatedRetainedBytes, 0);
      expect(owner.activeLeases, 0);
      for (final lease in leases) {
        expect(lease.isActive, isFalse);
        lease.release();
      }
    },
  );

  test('picture cost above the reserved slots is admitted or rolled back', () {
    final input = heavyBand();
    final generous = cache();
    addTearDown(generous.close);
    final first = generous.acquireBandChild(content: input, childIndex: 0);
    final second = generous.acquireBandChild(content: input, childIndex: 1);
    final initialBytes = generous.estimatedRetainedBytes;
    expect(generous.prepareBandChildPaint(first), isTrue);
    final finalBytes = generous.estimatedRetainedBytes;
    expect(finalBytes, greaterThan(initialBytes));
    expect(generous.prepareBandChildPaint(second), isFalse);
    expect(generous.estimatedRetainedBytes, finalBytes);

    final limited = cache(bytes: finalBytes - 1);
    addTearDown(limited.close);
    final a = limited.acquireBandChild(content: input, childIndex: 0);
    final b = limited.acquireBandChild(content: input, childIndex: 1);
    expect(
      () => limited.prepareBandChildPaint(a),
      throwsA(
        isA<ForumBodyParagraphBudgetException>().having(
          (error) => error.failure,
          'failure',
          ForumBodyParagraphBudgetFailure.content,
        ),
      ),
    );
    expect(a.layout.isPaintPrepared, isFalse);
    expect(b.layout.isPaintPrepared, isFalse);
    expect(limited.preparedPictureCount, 0);
    expect(limited.pictureBuildCount, 0);
    expect(limited.estimatedRetainedBytes, initialBytes);
    a.release();
    b.release();
    limited.clearUnpinned();
    expect(limited.estimatedRetainedBytes, 0);
    first.release();
    second.release();
  });

  test(
    'foreign pins can block picture growth and release unblocks the same band',
    () {
      final input = heavyBand();
      final foreignBand = band(['<span>foreign</span>']);
      final generous = cache();
      final full = generous.acquireBandChild(content: input, childIndex: 0);
      final samplePin = generous.acquireBandChild(
        content: foreignBand,
        childIndex: 0,
      );
      final initialWithPin = generous.estimatedRetainedBytes;
      samplePin.release();
      generous.clearUnpinned();
      generous.prepareBandChildPaint(full);
      final fullBytes = generous.estimatedRetainedBytes;
      full.release();
      generous.close();
      final owner = cache(
        entries: 2,
        bytes: fullBytes > initialWithPin ? fullBytes : initialWithPin,
      );
      addTearDown(owner.close);
      final a = owner.acquireBandChild(content: input, childIndex: 0);
      final b = owner.acquireBandChild(content: input, childIndex: 1);
      final foreign = owner.acquireBandChild(
        content: foreignBand,
        childIndex: 0,
      );
      late ForumBodyParagraphBudgetException rejection;
      try {
        owner.prepareBandChildPaint(a);
        fail('Picture must be blocked by a foreign pin');
      } on ForumBodyParagraphBudgetException catch (error) {
        rejection = error;
      }
      expect(rejection.failure, ForumBodyParagraphBudgetFailure.pinned);
      expect(rejection.requiredAdditionalEntries, 0);
      expect(owner.isBlockedByExternalPins(rejection, [a, b]), isTrue);
      expect(owner.preparedPictureCount, 0);
      foreign.release();
      expect(owner.prepareBandChildPaint(a), isTrue);
      expect(owner.prepareBandChildPaint(b), isFalse);
      expect(owner.entryCount, 1);
      expect(owner.preparedPictureCount, 1);
      expect(owner.estimatedRetainedBytes, fullBytes);
      expect(owner.layoutBuildCount, 2);
      a.release();
      b.release();
    },
  );
}

class _BranchScaler extends TextScaler {
  final _ratio = [1.0];
  set ratio(double value) => _ratio[0] = value;
  @override
  double scale(double fontSize) =>
      fontSize == 10 ? fontSize * _ratio.single : fontSize;
  @override
  double get textScaleFactor => 1;
  @override
  bool operator ==(Object other) => other is _BranchScaler;
  @override
  int get hashCode => 1;
}

class _OnceScaler extends TextScaler {
  _OnceScaler(VoidCallback action) : _action = [action];
  final List<VoidCallback?> _action;
  @override
  double scale(double size) {
    final action = _action.single;
    _action[0] = null;
    action?.call();
    return size;
  }

  @override
  double get textScaleFactor => 1;
}
