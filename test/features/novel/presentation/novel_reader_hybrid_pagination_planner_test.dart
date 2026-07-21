import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_classified_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_flowable_complex_pagination.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_plan.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_progress.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_preparation_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_hybrid_pagination_planner.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_renderer_validator.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_text_run_extractor.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/typography/rich_text_typography.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_text_style_resolver.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

void main() {
  test('pure text uses TextPainter with bounded HTML validation', () async {
    final chapter = await _prepare(
      '<p>${List<String>.filled(60, '混合分页正文 mixed 123。').join()}</p>',
    );
    final adapter = _RecordingMeasureAdapter();

    final plan = await _planner(
      adapter,
    ).paginate(chapter, _key(chapter, height: 120));

    expect(plan.pageCount, greaterThan(2));
    expect(plan.textFastPathCount, plan.pageCount);
    expect(plan.textLayoutCount, 1);
    expect(plan.safeTextRunCount, greaterThan(0));
    expect(plan.complexBlockCount, 0);
    expect(plan.safeTextFallbackCount, 0);
    expect(plan.rendererValidationCount, greaterThan(0));
    expect(plan.rendererValidationCount, lessThan(plan.pageCount));
    expect(plan.measurementCount, plan.rendererValidationCount);
    expect(plan.domSliceCount, plan.pageCount);
    expect(plan.routeCounts[NovelReaderPaginationRoute.safeText], 1);
    expect(
      plan.pages
          .map((page) => html_parser.parseFragment(page.html).text ?? '')
          .join(),
      html_parser.parseFragment(chapter.html).text,
    );
  });

  test(
    'routes text, ruby, tables and readable images through one planner',
    () async {
      final chapter = await _prepare(
        '<p>普通正文</p>'
        '<p>前<ruby>字<rt>じ</rt></ruby>后</p>'
        '<table><tr><td>表格正文</td></tr></table>'
        '<img src="data/attachment/forum/phase4.jpg">',
      );
      final plan = await _planner(
        _RecordingMeasureAdapter(),
      ).paginate(chapter, _key(chapter, height: 160));

      expect(plan.routeCounts[NovelReaderPaginationRoute.safeText], 1);
      expect(plan.routeCounts[NovelReaderPaginationRoute.rubyInline], 1);
      expect(plan.routeCounts[NovelReaderPaginationRoute.tableBlock], 1);
      expect(plan.routeCounts[NovelReaderPaginationRoute.isolatedImage], 1);
      expect(plan.complexBlockCount, 2);
      expect(plan.readableImageCount, 1);
      expect(
        plan.pages.where((page) => page.containsIsolatedImage),
        hasLength(1),
      );
      expect(
        plan.pages
            .singleWhere((page) => page.containsIsolatedImage)
            .requiresInnerScroll,
        isTrue,
        reason:
            'Unknown image geometry must not be allowed to overflow after decode.',
      );
      expect(plan.pages.expand((page) => page.imageIndices), contains(0));
      expect(plan.pages.any((page) => page.html.contains('<ruby>')), isTrue);
      expect(plan.pages.any((page) => page.html.contains('<table>')), isTrue);
    },
  );

  test(
    'backs off to fewer complete lines after a validation mismatch',
    () async {
      final chapter = await _prepare(
        '<p>${List<String>.filled(20, '需要回退的安全正文。').join()}</p>',
      );
      final adapter = _RecordingMeasureAdapter(
        heightFor: (request, validationCall) {
          if (request.atomId?.endsWith(':validation') == true &&
              validationCall == 1) {
            return 240;
          }
          return 40;
        },
      );

      final plan = await _planner(
        adapter,
      ).paginate(chapter, _key(chapter, height: 120));

      expect(plan.rendererValidationMismatchCount, 1);
      expect(plan.safeTextFallbackCount, 0);
      expect(plan.textFastPathCount, greaterThan(0));
      expect(plan.pages.every((page) => !page.requiresInnerScroll), isTrue);
    },
  );

  test(
    'falls back to a complex atom when bounded backoff still mismatches',
    () async {
      final chapter = await _prepare(
        '<p>${List<String>.filled(20, '持续不一致的正文。').join()}</p>',
      );
      final adapter = _RecordingMeasureAdapter(
        heightFor: (request, validationCall) {
          if (request.atomId?.endsWith(':validation') == true) {
            return 260;
          }
          return 80;
        },
      );

      final plan = await _planner(
        adapter,
      ).paginate(chapter, _key(chapter, height: 120));

      expect(plan.rendererValidationMismatchCount, 2);
      expect(plan.safeTextFallbackCount, 1);
      expect(
        plan.safeTextFallbackReasonCounts,
        <NovelReaderSafeTextFallbackReason, int>{
          NovelReaderSafeTextFallbackReason.rendererMismatch: 1,
        },
      );
      expect(plan.complexBlockCount, 1);
      expect(plan.pageCount, 1);
      expect(plan.pages.single.html, chapter.html);
    },
  );

  test(
    'uses first-page remaining height to compose adjacent text atoms',
    () async {
      final chapter = await _prepare('<p>第一段短文。</p><p>第二段短文。</p>');
      final plan = await _planner(
        _RecordingMeasureAdapter(),
      ).paginate(chapter, _key(chapter, height: 120));

      expect(plan.pageCount, 1);
      expect(plan.pages.single.html, contains('第一段短文'));
      expect(plan.pages.single.html, contains('第二段短文'));
      expect(plan.pages.single.anchorRanges, hasLength(2));
    },
  );

  test('top-level br-separated lines share pages on the text path', () async {
    final source = List<String>.generate(
      24,
      (index) => '第${index + 1}句短文。<br>\r\n',
    ).join();
    final chapter = await _prepare(source);

    final plan = await _planner(
      _RecordingMeasureAdapter(),
    ).paginate(chapter, _key(chapter, height: 120));

    expect(plan.pageCount, greaterThan(1));
    expect(plan.pageCount, lessThan(24));
    expect(plan.complexBlockCount, 0);
    expect(plan.routeCounts.keys, <NovelReaderPaginationRoute>{
      NovelReaderPaginationRoute.safeText,
    });
    final combinedHtml = plan.pages.map((page) => page.html).join();
    expect(combinedHtml, contains('第1句短文。<br>'));
    expect(combinedHtml, contains('第24句短文。'));
    expect(combinedHtml, isNot(endsWith('<br>')));
  });

  test('does not publish separator-only pages before an image', () async {
    final chapter = await _prepare(
      '<p>图片前正文。</p>'
      '<div>&nbsp; &nbsp;</div>'
      '<br><br>'
      '<img src="data/attachment/forum/blank-page.jpg">',
    );

    final plan = await _planner(
      _RecordingMeasureAdapter(),
    ).paginate(chapter, _key(chapter, height: 42));

    expect(plan.pages, hasLength(2));
    expect(plan.pages.first.html, contains('图片前正文'));
    expect(plan.pages.first.containsIsolatedImage, isFalse);
    expect(plan.pages.last.containsIsolatedImage, isTrue);
    expect(plan.pages.last.html, contains('blank-page.jpg'));
    expect(
      plan.pages.where((page) {
        final fragment = html_parser.parseFragment(page.html);
        final text = (fragment.text ?? '').replaceAll('\u00A0', ' ').trim();
        return text.isEmpty && fragment.querySelector('img') == null;
      }),
      isEmpty,
    );
  });

  test(
    'drops a whitespace-only text chunk before an image at 18.5 and 1.6',
    () async {
      final chapter = await _prepare(
        '<div>图片前正文。<br>\r\n<br>\r\n<br>\r\n<br>\r\n</div>'
        '<img src="data/attachment/forum/blank-chunk.jpg">',
      );

      final plan = await _planner(
        _RecordingMeasureAdapter(),
      ).paginate(chapter, _key(chapter, height: 60));

      expect(
        plan.pages.where((page) => page.containsIsolatedImage),
        hasLength(1),
      );
      expect(
        plan.pages.where(
          (page) =>
              !page.containsIsolatedImage && _visibleText(page.html).isEmpty,
        ),
        isEmpty,
      );
      expect(
        plan.pages.where((page) => _visibleText(page.html).contains('图片前正文')),
        hasLength(1),
      );
    },
  );

  test('does not place a blank page before the fixture image', () async {
    final fixture = await File(
      'test/features/novel/fixtures/pagination/'
      'nested_title_attachment_v1.html',
    ).readAsString();
    final html = fixture.replaceFirst(
      '[attach]841380[/attach]',
      '<img src="data/attachment/forum/nested-title-cover.jpg">',
    );
    final chapter = await _prepare(html);

    final plan = await _planner(
      _RecordingMeasureAdapter(),
    ).paginate(chapter, _key(chapter, height: 600));

    final imagePageIndex = plan.pages.indexWhere(
      (page) => page.containsIsolatedImage,
    );
    expect(imagePageIndex, greaterThan(0));
    expect(
      _visibleText(plan.pages[imagePageIndex - 1].html),
      isNotEmpty,
      reason: 'A separator-only page must not be emitted before an image.',
    );
    expect(
      plan.pages.where(
        (page) =>
            !page.containsIsolatedImage && _visibleText(page.html).isEmpty,
      ),
      isEmpty,
    );
    final textBeforeImage = plan.pages
        .take(imagePageIndex)
        .map((page) => _visibleText(page.html))
        .join(' ');
    expect(textBeforeImage, contains('尊重发帖人的意愿'));
    expect(textBeforeImage, contains('默默下载就是了'));
    expect(plan.pages[imagePageIndex].html, contains('nested-title-cover.jpg'));
  });

  test(
    'ACT23 fixture packs Discuz lines around ruby without sparse pages',
    () async {
      final html = await File(
        'test/features/novel/fixtures/pagination/'
        'act23_ruby_collapse_v1.html',
      ).readAsString();
      final chapter = await _prepare(html);
      final plan = await _planner(
        _RecordingMeasureAdapter(
          heightFor: (request, _) {
            if (request.html.contains('showcollapse_box')) {
              return 60;
            }
            if (request.html.contains('<ruby>')) {
              return 120;
            }
            return 10;
          },
        ),
      ).paginate(chapter, _key(chapter, height: 600));

      expect(plan.routeCounts[NovelReaderPaginationRoute.safeText], 88);
      expect(plan.routeCounts[NovelReaderPaginationRoute.rubyInline], 1);
      expect(plan.routeCounts[NovelReaderPaginationRoute.collapseBlock], 1);
      expect(plan.pageCount, lessThanOrEqualTo(9));
      expect(plan.dedicatedCollapsePageCount, 1);
      expect(plan.averageTextPageFullness, greaterThan(0.85));
      final textPages = plan.pages
          .where((page) => !page.isDedicatedContentPage)
          .toList(growable: false);
      expect(
        textPages
            .take(textPages.length - 1)
            .every((page) => page.fullness > 0.85),
        isTrue,
      );
      expect(
        plan.pages.where((page) => _visibleText(page.html).isEmpty),
        isEmpty,
      );
      final combinedText = plan.pages
          .map((page) => _visibleText(page.html))
          .join();
      expect(combinedText, contains('ACT23'));
      expect(combinedText, contains('我也好想变成像蓝沙前辈那样出色的姐姐啊'));
      expect(combinedText, contains('碎碎念'));
    },
  );

  test(
    'flows Ruby and fixed-size smileys without splitting protected clusters',
    () async {
      final html = await File(
        'test/features/novel/fixtures/pagination/'
        'phase6_ruby_protected_inline_v1.html',
      ).readAsString();
      final chapter = await _prepare(html);
      final plan = await _planner(
        _RecordingMeasureAdapter(
          heightFor: (request, _) {
            final fragment = html_parser.parseFragment(request.html);
            final imageHeight = fragment.querySelectorAll('img').length * 24;
            return (_visibleText(request.html).runes.length * 8 + imageHeight)
                .toDouble();
          },
        ),
      ).paginate(chapter, _key(chapter, height: 180));

      expect(plan.routeCounts[NovelReaderPaginationRoute.rubyInline], 4);
      expect(
        plan.routeCounts[NovelReaderPaginationRoute.flowableComplexText],
        1,
      );
      expect(plan.pageCount, greaterThan(1));
      expect(plan.flowableComplexFragmentCount, greaterThan(5));
      expect(plan.atomicWidgetPageCount, 0);
      expect(plan.dedicatedImagePageCount, 0);
      expect(plan.pages.every((page) => !page.isDedicatedContentPage), isTrue);

      final publishedHtml = plan.pages.map((page) => page.html).join();
      final published = html_parser.parseFragment(publishedHtml);
      expect(published.querySelectorAll('ruby'), hasLength(5));
      expect(published.querySelectorAll('rt'), hasLength(5));
      expect(published.querySelectorAll('rp'), hasLength(10));
      for (final ruby in published.querySelectorAll('ruby')) {
        expect(ruby.querySelectorAll('rt'), hasLength(1));
        expect(ruby.querySelectorAll('rp'), hasLength(2));
      }
      final smileys = published.querySelectorAll('img');
      expect(smileys, hasLength(1));
      expect(smileys.single.attributes['width'], '24');
      expect(smileys.single.attributes['height'], '24');
      expect(
        _withoutFormattingWhitespace(publishedHtml),
        _withoutFormattingWhitespace(chapter.html),
        reason: 'Flowable slices must not lose or duplicate annotated text.',
      );
    },
  );

  test(
    'moves a heading forward when the following body line would orphan',
    () async {
      final chapter = await _prepare(
        '<p>${List<String>.filled(20, '前文').join()}</p>'
        '<h2>章节标题</h2>'
        '<p>标题后的第一行正文。</p>',
      );
      final plan = await _planner(
        _RecordingMeasureAdapter(),
      ).paginate(chapter, _key(chapter, height: 180));

      final headingPage = plan.pages.singleWhere(
        (page) => page.html.contains('<h2>'),
      );
      expect(headingPage.index, greaterThan(0));
      expect(plan.pages[headingPage.index - 1].html, isNot(contains('<h2>')));
      expect(headingPage.html, contains('标题后的第一行正文'));
    },
  );

  test('keeps a fitting table on a dedicated page', () async {
    final chapter = await _prepare(
      '<p>表格前的短文。</p>'
      '<table><tr><td>单元格</td></tr></table>',
    );
    final adapter = _RecordingMeasureAdapter(
      heightFor: (request, _) {
        if (request.atomId?.contains(':composition:validation') == true) {
          return 70;
        }
        return request.html.contains('<table>') ? 24 : 30;
      },
    );

    final plan = await _planner(
      adapter,
    ).paginate(chapter, _key(chapter, height: 120));

    expect(plan.pageCount, 2);
    expect(plan.pages.first.html, contains('表格前的短文'));
    expect(plan.pages.first.html, isNot(contains('<table>')));
    expect(plan.pages.last.html, contains('<table>'));
    expect(plan.pages.last.isDedicatedContentPage, isTrue);
    expect(plan.pages.last.gapReason, NovelReaderPageGapReason.dedicatedTable);
    expect(plan.dedicatedTablePageCount, 1);
    expect(plan.rendererValidationCount, 1);
    expect(plan.rendererValidationMismatchCount, 0);
  });

  test('does not probe page composition for a dedicated table', () async {
    final chapter = await _prepare(
      '<p>表格前的短文。</p>'
      '<table><tr><td>单元格</td></tr></table>',
    );
    final adapter = _RecordingMeasureAdapter(
      heightFor: (request, _) {
        if (request.atomId?.contains(':composition:validation') == true) {
          return 180;
        }
        return request.html.contains('<table>') ? 24 : 30;
      },
    );

    final plan = await _planner(
      adapter,
    ).paginate(chapter, _key(chapter, height: 120));

    expect(plan.pageCount, 2);
    expect(plan.pages.first.html, contains('表格前的短文'));
    expect(plan.pages.first.html, isNot(contains('<table>')));
    expect(plan.pages.last.html, contains('<table>'));
    expect(
      adapter.requests.where(
        (request) => request.atomId?.contains(':composition') == true,
      ),
      isEmpty,
    );
    expect(plan.rendererValidationMismatchCount, 0);
  });

  test(
    'keeps original pages when complex composition validation throws',
    () async {
      final chapter = await _prepare(
        '<p>表格前的短文。</p>'
        '<table><tr><td>单元格</td></tr></table>',
      );

      final plan = await DefaultNovelReaderHybridPaginationPlanner(
        measureAdapter: const _ThrowingCompositionMeasureAdapter(),
        preferences: _preferences,
        theme: _theme,
        baseStyle: _baseStyle,
      ).paginate(chapter, _key(chapter, height: 120));

      expect(plan.pageCount, 2);
      expect(plan.pages.first.html, contains('表格前的短文'));
      expect(plan.pages.last.html, contains('<table>'));
      expect(plan.pages.every((page) => page.html.trim().isNotEmpty), isTrue);
    },
  );

  test('validates each distinct risk style signature once', () async {
    final chapter = await _prepare(
      '<p><span style="background-color:#ffeeaa">第一种样式。</span></p>'
      '<p><span style="background-color:#ddeeff">第二种样式。</span></p>',
    );
    final plan = await DefaultNovelReaderHybridPaginationPlanner(
      measureAdapter: _RecordingMeasureAdapter(),
      preferences: _preferences,
      theme: _theme,
      baseStyle: _baseStyle,
      validationPolicy: const NovelReaderPaginationValidationPolicy(
        interval: 10000,
      ),
    ).paginate(chapter, _key(chapter, height: 200));

    expect(plan.rendererValidationCount, 2);
    expect(plan.rendererValidationMismatchCount, 0);
  });

  test(
    'marks oversized tables as inner-scroll pages without splitting rows',
    () async {
      const table = '<table><tr><td>第一行</td></tr><tr><td>第二行</td></tr></table>';
      final chapter = await _prepare(table);
      final adapter = _RecordingMeasureAdapter(
        heightFor: (request, _) => request.html.contains('<table>') ? 300 : 10,
      );
      final plan = await _planner(
        adapter,
      ).paginate(chapter, _key(chapter, height: 100));

      expect(plan.pageCount, 1);
      expect(plan.pages.single.requiresInnerScroll, isTrue);
      expect(
        html_parser
            .parseFragment(plan.pages.single.html)
            .querySelectorAll('tr'),
        hasLength(2),
      );
    },
  );

  test('honors cancellation before publishing a plan', () async {
    final chapter = await _prepare('<p>正文</p>');
    final token = NovelReaderPaginationCancellationToken()..cancel();

    await expectLater(
      _planner(_RecordingMeasureAdapter()).plan(
        chapter: chapter,
        key: _key(chapter, height: 120),
        cancellationToken: token,
      ),
      throwsA(
        isA<NovelReaderPaginationException>().having(
          (error) => error.code,
          'code',
          'paginationCancelled',
        ),
      ),
    );
  });

  test('publishes only stable pages before the complete plan', () async {
    final chapter = await _prepare(
      '<p>${List<String>.filled(80, '增量分页正文 mixed 123。').join()}</p>',
    );
    final token = NovelReaderPaginationCancellationToken();

    final events = await _planner(_RecordingMeasureAdapter())
        .planIncrementally(
          chapter: chapter,
          key: _key(chapter, height: 120),
          cancellationToken: token,
        )
        .toList();

    expect(events.length, greaterThan(1));
    expect(events.first.isComplete, isFalse);
    expect(events.first.plan.pages, hasLength(1));
    expect(events.last.isComplete, isTrue);
    expect(events.last.processedAtomCount, events.last.totalAtomCount);
    for (var index = 1; index < events.length; index += 1) {
      final previous = events[index - 1].plan.pages;
      final current = events[index].plan.pages;
      expect(current.length, greaterThanOrEqualTo(previous.length));
      expect(current.take(previous.length).toList(), previous);
    }
  });

  test('incremental pagination stops publishing after cancellation', () async {
    final chapter = await _prepare(
      '<p>${List<String>.filled(80, '可取消的增量分页正文。').join()}</p>',
    );
    final token = NovelReaderPaginationCancellationToken();
    final events = <NovelReaderPaginationProgress>[];
    final done = Completer<void>();

    _planner(_RecordingMeasureAdapter())
        .planIncrementally(
          chapter: chapter,
          key: _key(chapter, height: 120),
          cancellationToken: token,
        )
        .listen(
          (progress) {
            events.add(progress);
            if (!progress.isComplete && !token.isCancelled) {
              token.cancel();
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            expect(
              error,
              isA<NovelReaderPaginationException>().having(
                (value) => value.code,
                'code',
                'paginationCancelled',
              ),
            );
            done.complete();
          },
          onDone: () {
            if (!done.isCompleted) {
              done.complete();
            }
          },
        );

    await done.future;
    expect(events, isNotEmpty);
    expect(events.every((event) => !event.isComplete), isTrue);
  });

  test('publishes the first page before later renderer validation', () async {
    final chapter = await _prepare(
      '<p><span style="background-color:#ffeeaa">'
      '${List<String>.filled(100, '风险样式增量分页正文。').join()}'
      '</span></p>',
    );
    final adapter = _GatedValidationMeasureAdapter();
    final firstPage = Completer<NovelReaderPaginationProgress>();
    final complete = Completer<NovelReaderPaginationProgress>();

    _planner(adapter)
        .planIncrementally(
          chapter: chapter,
          key: _key(chapter, height: 120),
          cancellationToken: NovelReaderPaginationCancellationToken(),
        )
        .listen(
          (progress) {
            if (!progress.isComplete && !firstPage.isCompleted) {
              firstPage.complete(progress);
            }
            if (progress.isComplete && !complete.isCompleted) {
              complete.complete(progress);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!firstPage.isCompleted) {
              firstPage.completeError(error, stackTrace);
            }
            if (!complete.isCompleted) {
              complete.completeError(error, stackTrace);
            }
          },
        );

    final first = await firstPage.future;
    expect(first.plan.pages, hasLength(1));
    expect(complete.isCompleted, isFalse);
    for (
      var attempt = 0;
      attempt < 10 && !adapter.laterValidationStarted;
      attempt += 1
    ) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(adapter.laterValidationStarted, isTrue);

    adapter.releaseLaterValidation();
    expect((await complete.future).isComplete, isTrue);
  });

  test('late validation mismatch preserves already published pages', () async {
    final chapter = await _prepare(
      '<p><span style="background-color:#ffeeaa">'
      '${List<String>.filled(100, '迟到校验不应重写已发布页。').join()}'
      '</span></p>',
    );
    final adapter = _GatedValidationMeasureAdapter(laterHeight: 260);
    final events = <NovelReaderPaginationProgress>[];
    final complete = Completer<NovelReaderPaginationProgress>();

    _planner(adapter)
        .planIncrementally(
          chapter: chapter,
          key: _key(chapter, height: 120),
          cancellationToken: NovelReaderPaginationCancellationToken(),
        )
        .listen((progress) {
          events.add(progress);
          if (progress.isComplete && !complete.isCompleted) {
            complete.complete(progress);
          }
        }, onError: complete.completeError);

    for (
      var attempt = 0;
      attempt < 20 && !adapter.laterValidationStarted;
      attempt += 1
    ) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(events, isNotEmpty);
    final publishedFirstPage = events.first.plan.pages.single;

    adapter.releaseLaterValidation();
    final finalPlan = (await complete.future).plan;

    expect(finalPlan.pages.first, publishedFirstPage);
    expect(finalPlan.safeTextFallbackCount, 1);
    expect(
      finalPlan.safeTextFallbackReasonCounts,
      <NovelReaderSafeTextFallbackReason, int>{
        NovelReaderSafeTextFallbackReason.rendererMismatch: 1,
      },
    );
    expect(finalPlan.complexBlockCount, 1);
  });

  test(
    'falls back only the safe atom when text style resolution throws',
    () async {
      final chapter = await _prepare('<p>正文</p>');
      final planner = DefaultNovelReaderHybridPaginationPlanner(
        measureAdapter: _RecordingMeasureAdapter(),
        preferences: _preferences,
        theme: _theme,
        baseStyle: _baseStyle,
        textRunExtractor: const NovelReaderPaginationTextRunExtractor(
          styleResolver: _ThrowingTextStyleResolver(),
        ),
      );

      final plan = await planner.paginate(chapter, _key(chapter, height: 120));

      expect(plan.pageCount, 1);
      expect(plan.safeTextFallbackCount, 1);
      expect(
        plan.safeTextFallbackReasonCounts,
        <NovelReaderSafeTextFallbackReason, int>{
          NovelReaderSafeTextFallbackReason.textRunExtractionFailure: 1,
        },
      );
      expect(plan.complexBlockCount, 1);
      expect(plan.pages.single.html, chapter.html);
    },
  );

  test('composes safe, flowable complex and safe text on one page', () async {
    final chapter = await _prepare(
      '<p>前文。</p>'
      '<p><font face="Fantasy Novel Font">复杂标题。</font></p>'
      '<p>后文。</p>',
    );
    final adapter = _RecordingMeasureAdapter(
      heightFor: (request, _) {
        if (request.atomId?.endsWith(':validation') == true) {
          return 30;
        }
        return _visibleText(request.html).runes.length * 10.0;
      },
    );

    final plan = await _planner(
      adapter,
    ).paginate(chapter, _key(chapter, height: 200));

    expect(plan.routeCounts[NovelReaderPaginationRoute.flowableComplexText], 1);
    expect(plan.pageCount, 1);
    expect(plan.pages.single.html, contains('前文'));
    expect(plan.pages.single.html, contains('复杂标题'));
    expect(plan.pages.single.html, contains('后文'));
    expect(plan.flowableComplexFragmentCount, 1);
    expect(plan.complexBoundaryIndexBuildCount, 1);
    expect(plan.complexBoundaryIndexCacheHitCount, 0);
    expect(plan.complexSearchProbeCount, 1);
    expect(plan.complexSearchCacheHitCount, 1);
    expect(plan.atomicWidgetPageCount, 0);
    expect(plan.flowabilityFailureReasonCounts, isEmpty);
  });

  test('shares the boundary index across isolated production plans', () async {
    final chapter = await _prepare(
      '<p><font face="Fantasy Novel Font">复杂缓存正文。</font></p>',
    );
    final planner = _planner(
      _RecordingMeasureAdapter(
        heightFor: (request, _) =>
            (request.endOffset! - request.startOffset!) * 10.0,
      ),
    );
    final key = _key(chapter, height: 200);

    final first = await planner.paginate(chapter, key);
    final second = await planner.paginate(chapter, key);

    expect(first.complexBoundaryIndexBuildCount, 1);
    expect(first.complexBoundaryIndexCacheHitCount, 0);
    expect(second.complexBoundaryIndexBuildCount, 0);
    expect(second.complexBoundaryIndexCacheHitCount, 1);
  });

  test('paginates a long flowable complex atom across three pages', () async {
    final chapter = await _prepare(
      '<p><font face="Fantasy Novel Font">${List.filled(24, '甲').join()}</font></p>',
    );
    final adapter = _RecordingMeasureAdapter(
      heightFor: (request, _) =>
          (request.endOffset! - request.startOffset!) * 10.0,
    );

    final plan = await _planner(
      adapter,
    ).paginate(chapter, _key(chapter, height: 80));

    expect(plan.pageCount, 3);
    expect(plan.flowableComplexFragmentCount, 3);
    expect(plan.complexBoundaryCount, greaterThanOrEqualTo(24));
    expect(plan.complexBoundaryIndexBuildCount, 1);
    expect(plan.complexSearchProbeCount, greaterThan(3));
    expect(plan.atomicWidgetPageCount, 0);
    expect(
      plan.pages.map((page) => _visibleText(page.html)).join(),
      List.filled(24, '甲').join(),
    );
    for (var index = 1; index < plan.pages.length; index += 1) {
      expect(
        plan.pages[index - 1].endAnchor.textOffset,
        plan.pages[index].startAnchor.textOffset,
      );
    }
  });

  test(
    'falls back atomically when the minimum complex fragment overflows',
    () async {
      final chapter = await _prepare(
        '<p><font face="Fantasy Novel Font">复杂正文。</font></p>',
      );

      final plan = await _planner(
        _RecordingMeasureAdapter(heightFor: (_, _) => 200),
      ).paginate(chapter, _key(chapter, height: 100));

      expect(plan.pageCount, 1);
      expect(plan.pages.single.requiresInnerScroll, isTrue);
      expect(plan.pages.single.isDedicatedContentPage, isTrue);
      expect(plan.minimumComplexFragmentCount, 1);
      expect(plan.atomicWidgetPageCount, 1);
      expect(plan.flowableComplexFragmentCount, 0);
      expect(plan.flowabilityFailureReasonCounts, {
        NovelReaderFlowableComplexFallbackReason.minimumFragmentOverflow: 1,
      });
      expect(_visibleText(plan.pages.single.html), '复杂正文。');
    },
  );
}

String _visibleText(String html) {
  return (html_parser.parseFragment(html).text ?? '')
      .replaceAll('\u00A0', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _withoutFormattingWhitespace(String html) {
  return _visibleText(html).replaceAll(RegExp(r'\s+'), '');
}

DefaultNovelReaderHybridPaginationPlanner _planner(
  NovelReaderPaginationMeasureAdapter adapter,
) {
  return DefaultNovelReaderHybridPaginationPlanner(
    measureAdapter: adapter,
    preferences: _preferences,
    theme: _theme,
    baseStyle: _baseStyle,
    validationPolicy: const NovelReaderPaginationValidationPolicy(interval: 8),
  );
}

Future<NovelReaderPreparedChapter> _prepare(String html) {
  const episode = NovelEpisodeItem(
    episodeId: 'hybrid-episode',
    novelId: 'hybrid-novel',
    sourceTid: '100',
    episodeTitle: '混合分页',
    orderIndex: 0,
  );
  return const DefaultNovelReaderHtmlPreparationService().prepare(
    rawHtml: html,
    episode: episode,
    preferences: _preferences,
    theme: _theme,
    sourceId: episode.episodeId,
    threadId: episode.sourceTid,
    imageCacheOwnerId: episode.sourceTid,
  );
}

NovelReaderPaginationKey _key(
  NovelReaderPreparedChapter chapter, {
  required int height,
}) {
  return NovelReaderPaginationKey(
    episodeId: chapter.episodeId,
    contentHash: chapter.contentHash,
    viewportWidthPx: 320,
    viewportHeightPx: height,
    typographySignature: 'font=18.5|line=1.6|hybrid',
    themeSignature: chapter.themeSignature,
    imageDimensionRevision: chapter.imageDimensionRevision,
    rendererRevision: 3,
  );
}

typedef _HeightFor =
    double Function(
      NovelReaderPaginationMeasureRequest request,
      int validationCall,
    );

final class _RecordingMeasureAdapter
    implements NovelReaderPaginationMeasureAdapter {
  _RecordingMeasureAdapter({this.heightFor});

  final _HeightFor? heightFor;
  int calls = 0;
  int validationCalls = 0;
  final List<NovelReaderPaginationMeasureRequest> requests =
      <NovelReaderPaginationMeasureRequest>[];

  @override
  Future<NovelReaderPaginationMeasureResult> measure(
    NovelReaderPaginationMeasureRequest request,
  ) async {
    calls += 1;
    requests.add(request);
    if (request.atomId?.endsWith(':validation') == true) {
      validationCalls += 1;
    }
    return NovelReaderPaginationMeasureResult(
      height: heightFor?.call(request, validationCalls) ?? 10,
    );
  }
}

final class _GatedValidationMeasureAdapter
    implements NovelReaderPaginationMeasureAdapter {
  _GatedValidationMeasureAdapter({this.laterHeight = 10});

  final Completer<void> _laterValidationGate = Completer<void>();
  final double laterHeight;
  int validationCalls = 0;
  bool laterValidationStarted = false;

  @override
  Future<NovelReaderPaginationMeasureResult> measure(
    NovelReaderPaginationMeasureRequest request,
  ) async {
    if (request.atomId?.endsWith(':validation') == true) {
      validationCalls += 1;
      if (validationCalls == 2) {
        laterValidationStarted = true;
        await _laterValidationGate.future;
      }
    }
    return NovelReaderPaginationMeasureResult(
      height: validationCalls >= 2 ? laterHeight : 10,
    );
  }

  void releaseLaterValidation() {
    if (!_laterValidationGate.isCompleted) {
      _laterValidationGate.complete();
    }
  }
}

final class _ThrowingTextStyleResolver implements ForumHtmlTextStyleResolver {
  const _ThrowingTextStyleResolver();

  @override
  ForumHtmlResolvedTextStyle resolve({
    required html_dom.Element element,
    required TextStyle parentStyle,
    required TextStyle baseStyle,
    required ForumHtmlReaderPreferences preferences,
    required ForumHtmlThemeContext theme,
  }) {
    throw StateError('synthetic text layout failure');
  }
}

final class _ThrowingCompositionMeasureAdapter
    implements NovelReaderPaginationMeasureAdapter {
  const _ThrowingCompositionMeasureAdapter();

  @override
  Future<NovelReaderPaginationMeasureResult> measure(
    NovelReaderPaginationMeasureRequest request,
  ) async {
    if (request.atomId?.contains(':composition:validation') == true) {
      throw StateError('synthetic composition validation failure');
    }
    return NovelReaderPaginationMeasureResult(
      height: request.html.contains('<table>') ? 24 : 30,
    );
  }
}

const _preferences = ForumHtmlReaderPreferences(
  typography: RichTextTypography(
    fontScale: 18.5 / 14,
    lineHeightScale: 1.6,
    paragraphSpacing: 12,
  ),
  conversionMode: TextConversionMode.none,
);

const _baseStyle = TextStyle(
  color: Color(0xFF4C3A21),
  fontSize: 18.5,
  height: 1.6,
);

const _theme = ForumHtmlThemeContext(
  brightness: ForumHtmlBrightness.light,
  surface: Color(0xFFF4EAD7),
  foreground: Color(0xFF4C3A21),
  link: Color(0xFF6A55A3),
  quoteSurface: Color(0xFFE8D8B8),
  quoteForeground: Color(0xFF8B7355),
  codeSurface: Color(0xFFEFE0C4),
  codeForeground: Color(0xFF4C3A21),
);
