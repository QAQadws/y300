import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/comic/domain/models/comic_comment_models.dart';
import 'package:y300/features/comic/presentation/comic_comment_content_projection.dart';
import 'package:y300/features/comic/presentation/comic_comment_presentation_store.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/thread/data/repositories/thread_post_ratings_repository.dart';
import 'package:y300/features/thread/presentation/thread_detail_state.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart'
    show ThreadPost;

import '../data/comic_comment_fixtures.dart';

void main() {
  test(
    'append preserves values, refreshed content rejects old image and rating results',
    () async {
      final store = ComicCommentPresentationStore();
      addTearDown(store.dispose);
      final original = _projection([commentPost(1)]);
      store.synchronize(original);
      final first = store['1']!;
      first.body.collapseExpansion['fold'] = true;
      first.recordImageSize('image', const Size(100, 200));
      final pending = Completer<ApiResult<ThreadPostRatingDetails>>();
      var requests = 0;
      Future<ApiResult<ThreadPostRatingDetails>> load() {
        requests++;
        return pending.future;
      }

      final loading = first.loadRatings(load);
      await first.loadRatings(load);
      expect(requests, 1);
      store.synchronize(_projection([commentPost(1), commentPost(2)]));
      expect(store['1'], same(first));
      expect(first.body.collapseExpansion['fold'], isTrue);
      expect(first.imageAspectRatio('image'), 0.5);

      store.synchronize(
        _projection([commentPost(1, message: '<p>edited</p>'), commentPost(2)]),
      );
      expect(store['1'], isNot(same(first)));
      expect(first.body.isActive, isFalse);
      expect(store.forRenderedPost(original.items.first.renderPost), isNull);
      pending.complete(const ApiSuccess(_details));
      await loading;
      first.recordImageSize('late', const Size(400, 200));
      expect(store['1']!.imageAspectRatio('late'), isNull);
      expect(store['1']!.ratings.status, ThreadPostRatingsLoadStatus.idle);
    },
  );

  test(
    'completed detached rating reads survive until the owning session ends',
    () async {
      final entry = ComicCommentPostPresentation();
      var notifications = 0;
      void listener() => notifications++;
      entry.addListener(listener);
      final pending = Completer<ApiResult<ThreadPostRatingDetails>>();
      final loading = entry.loadRatings(() => pending.future);
      entry.removeListener(listener); // The lazy card has unmounted.
      pending.complete(const ApiSuccess(_details));
      await loading;
      expect(entry.ratings.details, same(_details));
      expect(notifications, 1);
      final conversion = Completer<ThreadPostRatingDetails>();
      final converting = entry.convertRatings(
        identity: 'traditional',
        convert: (_) => conversion.future,
      );
      entry.dispose();
      conversion.complete(_converted);
      await converting;
      expect(entry.displayRatings.details, isNot(same(_converted)));
      expect(entry.body.isActive, isFalse);
    },
  );

  test(
    'failed conversion does not automatically retry through listeners',
    () async {
      final entry = ComicCommentPostPresentation();
      addTearDown(entry.dispose);
      await entry.loadRatings(() async => const ApiSuccess(_details));
      var conversions = 0;
      Future<ThreadPostRatingDetails> convert(ThreadPostRatingDetails _) async {
        conversions++;
        throw StateError('converter unavailable');
      }

      await entry.convertRatings(identity: 'traditional', convert: convert);
      await entry.convertRatings(identity: 'traditional', convert: convert);
      expect(conversions, 1);
      expect(entry.displayRatings.details, same(_details));
    },
  );
}

const _details = ThreadPostRatingDetails(
  participantCount: 2,
  totalScoreText: '+4',
  ratings: [],
);
const _converted = ThreadPostRatingDetails(
  participantCount: 2,
  totalScoreText: 'converted',
  ratings: [],
);

ComicCommentContentProjection _projection(List<ThreadPost> posts) =>
    ComicCommentContentProjection.raw(
      ComicCommentLoadResult.fromRead(commentDetailPage(posts: posts)),
      mode: TextConversionMode.none,
      converterId: 'identity',
      sourceRevision: 'fixture',
    );
