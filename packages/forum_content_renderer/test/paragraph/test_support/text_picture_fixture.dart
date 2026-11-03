import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

final class TextPictureFixture {
  TextPictureFixture({
    int entries = 16,
    int bytes = 1 << 24,
    bool band = false,
    String first = 'AB',
  }) {
    cache = ForumBodyParagraphCache(
      maxEntries: entries,
      maxEstimatedBytes: bytes,
    );
    final document = const ForumBodyParser().parse(
      html:
          '<p><span style="color:red">$first</span><span style="font-size:10px;color:blue">xy</span></p>',
      sourceId: 'prepared-text-picture',
      conversionIdentity: 'none',
    );
    final styles = const ForumBodyStyleResolver().resolve(
      document,
      ForumBodyReaderStyle(
        textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1),
        fontRevision: 'ahem',
        linkColor: const Color(0xff0000ff),
      ),
    );
    final contexts = [
      for (var i = 0; i < 2; i++)
        const ForumBodyParagraphContentBuilder().build(
          document: document,
          styles: styles,
          path: '0/$i',
          layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
        ),
    ];
    if (band) {
      final value = ForumBodyTextBandContent(contexts: contexts);
      text = [
        for (var i = 0; i < 2; i++)
          cache.acquireBandChild(content: value, childIndex: i),
      ];
      for (final lease in text.cast<ForumBodyTextBandChildLease>()) {
        cache.prepareBandChildPaint(lease);
      }
    } else {
      text = [
        for (final value in contexts) cache.acquire(content: value, width: 100),
      ];
    }
    input = ForumBodyTextPictureInput(
      commands: [
        ForumBodyTextPictureCommand.fromText(text[0], const Offset(5, 25)),
        ForumBodyTextPictureCommand.fromText(text[1], const Offset(15, 5)),
        ForumBodyTextPictureCommand.fromText(text[0], const Offset(65, 25)),
      ],
    );
    addTearDown(() {
      for (final lease in text) {
        lease.release();
      }
      cache.close();
    });
  }
  late final ForumBodyParagraphCache cache;
  late final List<ForumBodyTextLease> text;
  late final ForumBodyTextPictureInput input;
  ForumBodyTextPicturePreparation open({
    void Function()? owner,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
  }) => ForumBodyTextPicturePreparation(
    cache: cache,
    input: input,
    text: text,
    ensureOwner: owner ?? () {},
    additionalOwnedLeases: additionalOwnedLeases,
  );
  ForumBodyTextPictureLease finish(
    ForumBodyTextPicturePreparation job, {
    bool cachedOnly = false,
  }) {
    for (var i = 0; !job.isReady && i < 10000; i++) {
      final step = job.advance(maxParts: 1, cachedOnly: cachedOnly);
      expect(step.partsPrepared, lessThanOrEqualTo(1));
      expect(step.picturesRecorded, lessThanOrEqualTo(1));
      expect(step.waitingForLayoutBudget, isFalse);
      expect(job.cacheMiss, isFalse);
    }
    expect(job.isReady, isTrue);
    return job.takeLease();
  }
}
