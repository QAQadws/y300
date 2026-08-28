import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/plain_text_batch_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/thread/presentation/thread_post_interaction_models.dart';
import 'package:y300/features/thread/presentation/thread_post_rate_form_projection.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_widgets.dart';

import '../../../test_support/localized_test_app.dart';

void main() {
  group('ThreadPostRateFormProjector', () {
    test('converts server reasons but keeps their raw values', () async {
      final service = _PrefixPlainService();
      final form = _form();

      final projection = await ThreadPostRateFormProjector(
        plainTextBatchConversionService: service,
      ).project(form, converter: const _TestConverter());

      expect(service.callCount, 1);
      expect(projection.isConverted, isTrue);
      expect(projection.reasons.single.rawValue, '服务器理由');
      expect(projection.reasons.single.displayLabel, '显示：服务器理由');
      expect(identical(projection.sourceForm, form), isTrue);
    });

    test('keeps an empty server reason list without conversion', () async {
      final service = _PrefixPlainService();

      final projection =
          await ThreadPostRateFormProjector(
            plainTextBatchConversionService: service,
          ).project(
            _form(reasonOptions: const <String>[]),
            converter: const _TestConverter(),
          );

      expect(service.callCount, 0);
      expect(projection.isConverted, isFalse);
      expect(projection.reasons, isEmpty);
    });

    test('single-control UI preserves unexposed server score values', () {
      const primary = ThreadPostRatingDimension(
        id: 'score1',
        label: '积分',
        minimum: 0,
        maximum: 5,
        initialScore: 0,
        todayRemaining: 10,
      );
      const secondary = ThreadPostRatingDimension(
        id: 'score2',
        label: '附加积分',
        minimum: -1,
        maximum: 1,
        initialScore: 0,
        todayRemaining: 2,
      );
      final form = ThreadPostRateForm(
        preparation: const ThreadPostRatingPreparation(
          tid: '100',
          pid: '1',
          dimensions: <ThreadPostRatingDimension>[primary, secondary],
          reasonSuggestions: <String>['服务器理由'],
          notificationPolicy: ThreadPostRatingNotificationPolicy.optional,
          notifyAuthorByDefault: true,
          token: _TestRatingToken(),
        ),
        dimension: primary,
      );

      final submission = ThreadPostRateDraft(
        form: form,
        score: 5,
        reason: '服务器理由',
        notifyAuthor: true,
      ).toSubmission();

      expect(submission.scores, <String, int>{'score1': 5, 'score2': 0});
    });
  });

  testWidgets('selecting a display reason submits its raw server value', (
    tester,
  ) async {
    final projection = await ThreadPostRateFormProjector(
      plainTextBatchConversionService: _PrefixPlainService(),
    ).project(_form(), converter: const _TestConverter());
    ThreadPostRateDraft? submitted;

    await tester.pumpWidget(
      LocalizedTestApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return FilledButton(
                key: const Key('open-rate-sheet'),
                onPressed: () async {
                  submitted = await showModalBottomSheet<ThreadPostRateDraft>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => ThreadPostRateSheet(projection: projection),
                  );
                },
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-rate-sheet')));
    await tester.pumpAndSettle();
    expect(find.text('显示：服务器理由'), findsOneWidget);

    await tester.tap(find.byKey(const Key('thread-post-rate-reason-服务器理由')));
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const Key('thread-post-rate-submit-button')),
    );
    await tester.tap(find.byKey(const Key('thread-post-rate-submit-button')));
    await tester.pumpAndSettle();

    expect(submitted?.reason, '服务器理由');
    expect(submitted?.form.preparation.tid, '100');
    expect(submitted?.toSubmission().scores, <String, int>{'score1': 3});
  });

  testWidgets('editing a selected reason submits the exact user input', (
    tester,
  ) async {
    final projection = await ThreadPostRateFormProjector(
      plainTextBatchConversionService: _PrefixPlainService(),
    ).project(_form(), converter: const _TestConverter());
    ThreadPostRateDraft? submitted;

    await tester.pumpWidget(
      LocalizedTestApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return FilledButton(
                key: const Key('open-rate-sheet'),
                onPressed: () async {
                  submitted = await showModalBottomSheet<ThreadPostRateDraft>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => ThreadPostRateSheet(projection: projection),
                  );
                },
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-rate-sheet')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('thread-post-rate-reason-服务器理由')));
    await tester.enterText(
      find.byKey(const Key('thread-post-rate-reason-input')),
      '用户逐字输入',
    );
    await tester.ensureVisible(
      find.byKey(const Key('thread-post-rate-submit-button')),
    );
    await tester.tap(find.byKey(const Key('thread-post-rate-submit-button')));
    await tester.pumpAndSettle();

    expect(submitted?.reason, '用户逐字输入');
  });
}

ThreadPostRateForm _form({
  List<String> reasonOptions = const <String>['服务器理由'],
}) {
  const dimension = ThreadPostRatingDimension(
    id: 'score1',
    label: '积分',
    minimum: 1,
    maximum: 3,
    initialScore: 1,
    todayRemaining: 5,
  );
  return ThreadPostRateForm(
    preparation: ThreadPostRatingPreparation(
      tid: '100',
      pid: '1',
      dimensions: const <ThreadPostRatingDimension>[dimension],
      reasonSuggestions: reasonOptions,
      notificationPolicy: ThreadPostRatingNotificationPolicy.optional,
      notifyAuthorByDefault: true,
      token: const _TestRatingToken(),
    ),
    dimension: dimension,
  );
}

final class _TestRatingToken implements ThreadPostRatingPreparationToken {
  const _TestRatingToken();
}

class _PrefixPlainService implements PlainTextBatchConversionService {
  int callCount = 0;

  @override
  Future<List<String>> convertAll({
    required List<String> sources,
    required TextConverter converter,
  }) async {
    callCount += 1;
    return <String>[for (final source in sources) '显示：$source'];
  }
}

class _TestConverter implements TextConverter {
  const _TestConverter();

  @override
  String get id => 'test:traditional';

  @override
  TextConversionMode get mode => TextConversionMode.toTraditional;

  @override
  Future<String> convertHtml(String html) async => html;
}
