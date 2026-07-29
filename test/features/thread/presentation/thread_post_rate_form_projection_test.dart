import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/plain_text_batch_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';
import 'package:y300/features/thread/data/repositories/thread_post_rate_repository.dart';
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

    test('does not B-convert application fallback reasons', () async {
      final service = _PrefixPlainService();

      final projection =
          await ThreadPostRateFormProjector(
            plainTextBatchConversionService: service,
          ).project(
            _form(origin: ThreadPostRateReasonOrigin.applicationFallback),
            converter: const _TestConverter(),
          );

      expect(service.callCount, 0);
      expect(projection.isConverted, isFalse);
      expect(projection.reasons.single.displayLabel, '服务器理由');
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
    expect(submitted?.form.formHash, 'raw-formhash');
    expect(submitted?.form.actionUrl, '/rate-submit');
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
  ThreadPostRateReasonOrigin origin = ThreadPostRateReasonOrigin.serverForm,
}) {
  return ThreadPostRateForm(
    actionUrl: '/rate-submit',
    formHash: 'raw-formhash',
    tid: '100',
    pid: '1',
    referer: '/thread-100-1-1.html',
    scoreName: 'score1',
    scoreMin: 1,
    scoreMax: 3,
    todayRemaining: 5,
    reasonOptions: const <String>['服务器理由'],
    notifyAuthorDefault: true,
    reasonOrigin: origin,
  );
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
