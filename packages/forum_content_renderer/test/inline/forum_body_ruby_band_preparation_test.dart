import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/ruby_pair_fixture.dart';

void ownerAlive() {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'one shared glyph build and two picture records use three distinct advances',
    () {
      final owner = ForumBodyParagraphCache(
        maxEntries: 1,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(owner.close);
      final input = rubyPairInput();
      final band = ForumBodyTextBandContent(
        contexts: [input.base, input.annotation],
      );
      final prepare = ForumBodyRubyGroupPreparation.fromRequests(
        cache: owner,
        base: ForumBodyTextRequest.bandChild(band: band, childIndex: 0),
        annotation: ForumBodyTextRequest.bandChild(band: band, childIndex: 1),
        ensureOwner: ownerAlive,
      );
      addTearDown(prepare.close);
      final steps = [prepare.advance(), prepare.advance(), prepare.advance()];
      expect(steps.map((step) => step.layoutsBuilt), [1, 0, 0]);
      expect(steps.map((step) => step.picturesBuilt), [0, 1, 1]);
      expect(steps.map((step) => step.partsPrepared), [0, 1, 1]);
      expect(steps.map((step) => step.madeProgress), everyElement(isTrue));
      expect(steps.map((step) => step.isReady), [false, false, true]);
      expect(prepare.preparedPartCount, 2);
      expect(owner.activeLeases, 2);
      final group = prepare.takeLayout();
      expect(group.size.width, 40);
      group.close();
      expect(owner.activeLeases, 0);
    },
  );

  test(
    'cached-only preparation neither shapes nor records even with a glyph-only hit',
    () {
      final owner = ForumBodyParagraphCache(
        maxEntries: 1,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(owner.close);
      final input = rubyPairInput();
      final band = ForumBodyTextBandContent(
        contexts: [input.base, input.annotation],
      );
      final prepare = ForumBodyRubyGroupPreparation.fromRequests(
        cache: owner,
        base: ForumBodyTextRequest.bandChild(band: band, childIndex: 0),
        annotation: ForumBodyTextRequest.bandChild(band: band, childIndex: 1),
        ensureOwner: ownerAlive,
      );
      addTearDown(prepare.close);
      expect(prepare.tryPrepareCached(), isFalse);
      expect(owner.layoutBuildCount, 0);
      owner.acquireBandChild(content: band, childIndex: 0).release();
      expect(prepare.tryPrepareCached(), isFalse);
      expect(prepare.tryPrepareCached(), isFalse);
      expect(owner.activeLeases, 1);
      expect(owner.layoutBuildCount, 1);
      expect(owner.pictureBuildCount, 0);
      expect(prepare.preparedPartCount, 0);
      expect(prepare.advance().picturesBuilt, 1);
      expect(prepare.advance().picturesBuilt, 1);
      prepare.takeLayout().close();
      final warm = ForumBodyRubyGroupPreparation.fromRequests(
        cache: owner,
        base: ForumBodyTextRequest.bandChild(band: band, childIndex: 0),
        annotation: ForumBodyTextRequest.bandChild(band: band, childIndex: 1),
        ensureOwner: ownerAlive,
      );
      addTearDown(warm.close);
      expect(warm.tryPrepareCached(), isTrue);
      expect(owner.layoutBuildCount, 1);
      expect(owner.pictureBuildCount, 2);
      warm.takeLayout().close();
      expect(owner.activeLeases, 0);
    },
  );

  test('separate bands keep both shape and drawing work bounded', () {
    final owner = ForumBodyParagraphCache(
      maxEntries: 2,
      maxEstimatedBytes: 1 << 20,
    );
    addTearDown(owner.close);
    final input = rubyPairInput(direction: 'rtl');
    final prepare = ForumBodyRubyGroupPreparation.fromRequests(
      cache: owner,
      base: ForumBodyTextRequest.bandChild(
        band: ForumBodyTextBandContent(contexts: [input.base]),
        childIndex: 0,
      ),
      annotation: ForumBodyTextRequest.bandChild(
        band: ForumBodyTextBandContent(contexts: [input.annotation]),
        childIndex: 0,
      ),
      ensureOwner: ownerAlive,
    );
    addTearDown(prepare.close);
    final steps = [for (var i = 0; i < 4; i++) prepare.advance()];
    expect(steps.map((step) => step.layoutsBuilt), [1, 0, 1, 0]);
    expect(steps.map((step) => step.picturesBuilt), [0, 1, 0, 1]);
    expect(steps.last.isReady, isTrue);
    prepare.takeLayout().close();
  });

  test(
    'plain base and band annotation keep the existing preparation entry usable',
    () {
      final owner = ForumBodyParagraphCache(
        maxEntries: 2,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(owner.close);
      final input = rubyPairInput();
      final prepare = ForumBodyRubyGroupPreparation.fromRequests(
        cache: owner,
        base: ForumBodyTextRequest.paragraph(input.base),
        annotation: ForumBodyTextRequest.bandChild(
          band: ForumBodyTextBandContent(contexts: [input.annotation]),
          childIndex: 0,
        ),
        ensureOwner: ownerAlive,
      );
      addTearDown(prepare.close);
      final steps = [for (var i = 0; i < 3; i++) prepare.advance()];
      expect(steps.map((step) => step.partsPrepared), [1, 0, 1]);
      expect(steps.last.isReady, isTrue);
      prepare.takeLayout().close();
    },
  );

  test(
    'generation cancellation after recording cannot publish a group or retain handles',
    () {
      final owner = ForumBodyParagraphCache(
        maxEntries: 1,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(owner.close);
      final input = rubyPairInput();
      final band = ForumBodyTextBandContent(
        contexts: [input.base, input.annotation],
      );
      var current = true;
      final prepare = ForumBodyRubyGroupPreparation.fromRequests(
        cache: owner,
        base: ForumBodyTextRequest.bandChild(band: band, childIndex: 0),
        annotation: ForumBodyTextRequest.bandChild(band: band, childIndex: 1),
        ensureOwner: () {
          if (!current) throw StateError('Retired test generation');
        },
      );
      prepare.advance();
      final previous = ui.Picture.onCreate;
      ui.Picture.onCreate = (_) {
        current = false;
      };
      try {
        expect(prepare.advance, throwsStateError);
      } finally {
        ui.Picture.onCreate = previous;
      }
      expect(prepare.state, ForumBodyRubyGroupPreparationState.failed);
      expect(owner.activeLeases, 0);
      expect(() => prepare.takeLayout(), throwsStateError);
      owner.clearUnpinned();
      expect(owner.estimatedRetainedBytes, 0);
    },
  );

  test(
    'closing preparation from Picture.onCreate retires the returned ticket',
    () {
      final owner = ForumBodyParagraphCache(
        maxEntries: 1,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(owner.close);
      final input = rubyPairInput();
      final band = ForumBodyTextBandContent(
        contexts: [input.base, input.annotation],
      );
      final prepare = ForumBodyRubyGroupPreparation.fromRequests(
        cache: owner,
        base: ForumBodyTextRequest.bandChild(band: band, childIndex: 0),
        annotation: ForumBodyTextRequest.bandChild(band: band, childIndex: 1),
        ensureOwner: ownerAlive,
      );
      prepare.advance();
      final previous = ui.Picture.onCreate;
      ui.Picture.onCreate = (_) => prepare.close();
      try {
        expect(prepare.advance, throwsStateError);
      } finally {
        ui.Picture.onCreate = previous;
      }
      expect(prepare.state, ForumBodyRubyGroupPreparationState.closed);
      expect(owner.activeLeases, 0);
      expect(owner.preparedPictureCount, 0);
    },
  );

  test(
    'owner closure while recording releases all pending and prepared state',
    () {
      final owner = ForumBodyParagraphCache(
        maxEntries: 1,
        maxEstimatedBytes: 1 << 20,
      );
      final input = rubyPairInput();
      final band = ForumBodyTextBandContent(
        contexts: [input.base, input.annotation],
      );
      final prepare = ForumBodyRubyGroupPreparation.fromRequests(
        cache: owner,
        base: ForumBodyTextRequest.bandChild(band: band, childIndex: 0),
        annotation: ForumBodyTextRequest.bandChild(band: band, childIndex: 1),
        ensureOwner: ownerAlive,
      );
      prepare.advance();
      final previous = ui.Picture.onCreate;
      ui.Picture.onCreate = (_) => owner.close();
      try {
        expect(prepare.advance, throwsStateError);
      } finally {
        ui.Picture.onCreate = previous;
        owner.close();
      }
      expect(prepare.state, ForumBodyRubyGroupPreparationState.failed);
      expect(owner.activeLeases, 0);
      expect(owner.preparedPictureCount, 0);
      expect(owner.estimatedRetainedBytes, 0);
    },
  );

  test(
    'whole-pair probe counts a shared band once under foreign pin pressure',
    () {
      final owner = ForumBodyParagraphCache(
        maxEntries: 1,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(owner.close);
      final input = rubyPairInput();
      final foreign = owner.acquire(content: input.base, width: 100);
      final band = ForumBodyTextBandContent(
        contexts: [input.base, input.annotation],
      );
      final prepare = ForumBodyRubyGroupPreparation.fromRequests(
        cache: owner,
        base: ForumBodyTextRequest.bandChild(band: band, childIndex: 0),
        annotation: ForumBodyTextRequest.bandChild(band: band, childIndex: 1),
        ensureOwner: ownerAlive,
      );
      addTearDown(prepare.close);
      final blocked = prepare.advance();
      expect(blocked.waitingForLayoutBudget, isTrue);
      expect(blocked.partsInspected, 2);
      expect(blocked.layoutsBuilt, 0);
      expect(blocked.picturesBuilt, 0);
      expect(foreign.isActive, isTrue);
      foreign.release();
      final steps = [for (var i = 0; i < 3; i++) prepare.advance()];
      expect(steps.last.isReady, isTrue);
      expect(owner.layoutBuildCount, 2);
      prepare.takeLayout().close();
    },
  );

  test('closing between shape and paint releases only this cursor alias', () {
    final owner = ForumBodyParagraphCache(
      maxEntries: 1,
      maxEstimatedBytes: 1 << 20,
    );
    addTearDown(owner.close);
    final input = rubyPairInput();
    final band = ForumBodyTextBandContent(
      contexts: [input.base, input.annotation],
    );
    final prepare = ForumBodyRubyGroupPreparation.fromRequests(
      cache: owner,
      base: ForumBodyTextRequest.bandChild(band: band, childIndex: 0),
      annotation: ForumBodyTextRequest.bandChild(band: band, childIndex: 1),
      ensureOwner: ownerAlive,
    );
    prepare.advance();
    final sibling = owner.acquireBandChild(content: band, childIndex: 1);
    prepare.close();
    expect(sibling.isActive, isTrue);
    expect(owner.activeLeases, 1);
    expect(owner.prepareBandChildPaint(sibling), isTrue);
    sibling.release();
  });
}
