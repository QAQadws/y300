import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_classified_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_flowable_complex_pagination.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_plan.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_progress.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_complex_html_search_budget.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_flowable_complex_pagination_engine.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_preparation_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_hybrid_pagination_planner.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_coordinator.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_demand.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_renderer_validator.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_text_run_extractor.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/typography/rich_text_typography.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

void main() {
  test(
    'collapse followed by style and line breaks has no blank final page',
    () async {
      const content =
          '<p>正文介绍。</p>'
          '<div class="showcollapse_box">'
          '<div class="showcollapse_title">合成目录</div>'
          '<div class="showcollapse_content">'
          '<div class="showcollapse_box">'
          '<div class="showcollapse_title">第一组</div>'
          '<div class="showcollapse_content">'
          '<a href="forum.php?mod=viewthread&amp;tid=10001">第一章</a>'
          '</div></div></div></div>';
      final chapter = await _prepare(
        '$content<br>\r\n<br>\r\n<br>\r\n'
        '<style>.showcollapse_content{display:none}</style>'
        '<br>\r\n<br>\r\n',
      );
      final adapter = _RecordingMeasureAdapter(
        heightFor: (request, _) => request.html.contains('<style>') ? 0 : 10,
      );
      final plan = await _planner(
        adapter,
      ).paginate(chapter, _key(chapter, height: 120));

      expect(plan.pages, hasLength(2));
      expect(plan.pages.first.html, contains('正文介绍。'));
      expect(plan.pages.last.isDedicatedContentPage, isTrue);
      expect(plan.pages.last.html, contains('第一章'));
      expect(plan.dedicatedCollapsePageCount, 1);
      expect(plan.atomicWidgetPageCount, 0);
      expect(
        adapter.requests.where((request) => request.html.contains('<style>')),
        isEmpty,
      );
      final baseline = await _prepare(content);
      final baselinePlan = await _planner(
        _RecordingMeasureAdapter(),
      ).paginate(baseline, _key(baseline, height: 120));
      expect(
        plan.pages.map((page) => page.html),
        baselinePlan.pages.map((page) => page.html),
      );
    },
  );

  test('incremental pages never publish metadata-only content', () async {
    final chapter = await _prepare(
      '<p>前文</p>'
      '<table><tr><td>表格</td></tr></table>'
      '<br><style>.fixture{color:red}</style>'
      '<div><script>fixtureCallback();</script><!-- fixture --></div>'
      '<p>后文</p><br><br>',
    );
    final updates = await _planner(_RecordingMeasureAdapter())
        .planIncrementally(
          chapter: chapter,
          key: _key(chapter, height: 120),
          cancellationToken: NovelReaderPaginationCancellationToken(),
        )
        .toList();

    expect(updates.last.isComplete, isTrue);
    expect(updates.last.plan.pageCount, 3);
    for (final update in updates) {
      for (final page in update.plan.pages) {
        final fragment = html_parser.parseFragment(page.html);
        fragment
            .querySelectorAll('style,script')
            .forEach((node) => node.remove());
        expect((fragment.text ?? '').trim(), isNotEmpty);
        expect(page.html, isNot(contains('fixture')));
      }
    }
    expect(updates.last.plan.pages.last.html, '<p>后文</p>');
  });

  test(
    'keeps a long edit notice intact on the same page as the following prose',
    () async {
      final notice =
          '本帖最后由 ${List.filled(30, 'fixture-user').join()} 于 2026-1-1 12:34 编辑';
      final chapter = await _prepare(
        '<i class="pstatus">$notice</i><br><br><p>正文第一段。</p>',
      );
      final adapter = _RecordingMeasureAdapter();
      final plan = await _planner(
        adapter,
      ).paginate(chapter, _key(chapter, height: 160));

      expect(plan.pageCount, 1);
      expect(plan.pages.single.html, contains(notice));
      expect(plan.pages.single.html, contains('正文第一段。'));
      expect(plan.pages.single.requiresInnerScroll, isFalse);
      expect(plan.pages.single.isDedicatedContentPage, isFalse);
      expect(plan.routeCounts[NovelReaderPaginationRoute.editStatus], 1);
      expect(plan.routeCounts[NovelReaderPaginationRoute.safeText], 1);
      expect(plan.textLayoutCount, 1);
      expect(
        adapter.requests.where(
          (r) => r.html.contains(notice) && !r.html.contains('正文第一段。'),
        ),
        hasLength(1),
      );
    },
  );

  test(
    'an edit notice joins preceding content without forcing a new page',
    () async {
      final chapter = await _prepare(
        '<p>前文</p><i class="pstatus">编辑提示</i><p>后文</p>',
      );
      final plan = await _planner(
        _RecordingMeasureAdapter(),
      ).paginate(chapter, _key(chapter, height: 160));
      expect(plan.pageCount, 1);
      expect(plan.pages.single.html, contains('前文'));
      expect(plan.pages.single.html, contains('编辑提示'));
      expect(plan.pages.single.html, contains('后文'));
    },
  );

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

  test(
    'cancelling a pending measurement disposes once and cannot fall back',
    () async {
      final chapter = await _prepare(
        '<font face="Fantasy Novel Font">复杂正文。</font>',
      );
      final adapter = _GatedSessionFactory(disposeCompletesError: true);
      final token = NovelReaderPaginationCancellationToken();
      final operation = _planner(adapter).plan(
        chapter: chapter,
        key: _key(chapter, height: 120),
        cancellationToken: token,
      );
      final cancelled = expectLater(
        operation,
        throwsA(
          isA<NovelReaderPaginationException>().having(
            (error) => error.code,
            'code',
            'paginationCancelled',
          ),
        ),
      );
      await adapter.session.started.future;

      token.cancel();
      await cancelled;
      expect(adapter.session.disposeCalls, 1);
      expect(
        adapter.session.measureCalls,
        1,
        reason: 'Cancellation must not trigger an atomic measurement fallback.',
      );
    },
  );

  test(
    'cancel releases a planner even when its adapter ignores disposal',
    () async {
      for (final fail in <bool>[false, true]) {
        final chapter = await _prepare('<table><tr><td>等待正文</td></tr></table>');
        final adapter = _GatedSessionFactory();
        final token = NovelReaderPaginationCancellationToken();
        final operation = _planner(adapter).plan(
          chapter: chapter,
          key: _key(chapter, height: 120),
          cancellationToken: token,
        );
        final cancelled = expectLater(
          operation,
          throwsA(
            isA<NovelReaderPaginationException>().having(
              (error) => error.code,
              'code',
              'paginationCancelled',
            ),
          ),
        );
        await adapter.session.started.future;

        token.cancel();
        await cancelled; // No renderer completion is required to leave the run.
        expect(adapter.session.disposeCalls, 1);
        if (fail) {
          adapter.session.result.completeError(
            StateError('late renderer error'),
          );
        } else {
          adapter.session.result.complete(
            const NovelReaderPaginationMeasureResult(height: 20),
          );
        }
        await Future<void>.delayed(Duration.zero);
        expect(adapter.session.measureCalls, 1);
        expect(adapter.session.disposeCalls, 1);
      }
    },
  );

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

  test(
    'nearby pages pause probes and promotion resumes the same session',
    () async {
      final chapter = await _prepare(
        '<p><font face="Fantasy Novel Font">${'甲' * 96}</font></p>',
      );
      final key = _key(chapter, height: 80);
      double heightFor(NovelReaderPaginationMeasureRequest request, int _) =>
          (request.endOffset! - request.startOffset!) * 10.0;
      final eager = await _planner(
        _RecordingMeasureAdapter(heightFor: heightFor),
      ).paginate(chapter, key);
      final idle = Completer<void>();
      final deferred = Completer<void>();
      final demand = NovelReaderPaginationDemand(
        lookAhead: 0,
        idleScheduler: () => idle.future,
      )..update(targetPending: false, pageIndex: 0);
      demand.addListener(() {
        if (demand.isDeferring && !deferred.isCompleted) {
          deferred.complete();
        }
      });
      final adapter = _RecordingMeasureAdapter(heightFor: heightFor);
      final sessions = _DemandMeasureSessionFactory(adapter);
      final events = <NovelReaderPaginationProgress>[];
      final completed = _planner(sessions, workDemand: demand)
          .planIncrementally(
            chapter: chapter,
            key: key,
            cancellationToken: NovelReaderPaginationCancellationToken(),
          )
          .map((progress) {
            events.add(progress);
            return progress;
          })
          .toList();

      await deferred.future.timeout(const Duration(seconds: 2));
      try {
        final probeCount = adapter.requests.length;
        expect(events.last.plan.pageCount, 1);
        expect(events.every((event) => !event.isComplete), isTrue);
        expect(sessions.sessions, hasLength(1));
        expect(sessions.sessions.single.disposeCalls, 0);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(adapter.requests, hasLength(probeCount));
        expect(events.last.plan.pageCount, 1);
      } finally {
        demand.update(
          targetPending: false,
          pageIndex: 0,
          requireComplete: true,
        );
      }
      final updates = await completed;
      final plan = updates.last.plan;
      expect(updates.last.isComplete, isTrue);
      expect(
        plan.pages.map((page) => page.html),
        eager.pages.map((page) => page.html),
      );
      for (var index = 0; index < plan.pageCount; index += 1) {
        final actual = plan.pages[index];
        final expected = eager.pages[index];
        expect(
          _anchorValues(actual.startAnchor),
          _anchorValues(expected.startAnchor),
        );
        expect(
          _anchorValues(actual.endAnchor),
          _anchorValues(expected.endAnchor),
        );
        expect(
          actual.anchorRanges.map(
            (range) => [_anchorValues(range.start), _anchorValues(range.end)],
          ),
          expected.anchorRanges.map(
            (range) => [_anchorValues(range.start), _anchorValues(range.end)],
          ),
        );
      }
      expect(sessions.sessions, hasLength(1));
      expect(sessions.sessions.single.disposeCalls, 1);
      expect(plan.pages.take(1).toList(), events.first.plan.pages);
      idle.complete();
      await Future<void>.delayed(Duration.zero);
      demand.dispose();
    },
  );

  test(
    'cancelling deferred work releases its session without late cache writes',
    () async {
      final chapter = await _prepare(
        '<p><font face="Fantasy Novel Font">${'甲' * 96}</font></p>',
      );
      final idle = Completer<void>();
      final deferred = Completer<void>();
      final demand = NovelReaderPaginationDemand(
        lookAhead: 0,
        idleScheduler: () => idle.future,
      )..update(targetPending: false, pageIndex: 0);
      demand.addListener(() {
        if (demand.isDeferring && !deferred.isCompleted) {
          deferred.complete();
        }
      });
      final adapter = _RecordingMeasureAdapter(
        heightFor: (request, _) =>
            (request.endOffset! - request.startOffset!) * 10.0,
      );
      final sessions = _DemandMeasureSessionFactory(adapter);
      final coordinator = DefaultNovelReaderPaginationCoordinator(
        pageBreaker: _planner(sessions, workDemand: demand),
      );
      final events = <NovelReaderPaginationProgress>[];
      final errors = <Object>[];
      final done = Completer<void>();
      final subscription = coordinator
          .paginateIncrementally(
            chapter: chapter,
            key: _key(chapter, height: 80),
          )
          .listen(events.add, onError: errors.add, onDone: done.complete);
      await deferred.future.timeout(const Duration(seconds: 2));
      final probeCount = adapter.requests.length;
      final eventCount = events.length;
      coordinator.cancelPending();
      await done.future.timeout(const Duration(seconds: 2));
      idle.complete();
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(demand.isDeferring, isFalse);
      expect(sessions.sessions, hasLength(1));
      expect(sessions.sessions.single.disposeCalls, 1);
      expect(adapter.requests, hasLength(probeCount));
      expect(events, hasLength(eventCount));
      expect(events.every((event) => !event.isComplete), isTrue);
      expect(errors, hasLength(1));
      expect(
        errors.single,
        isA<NovelReaderPaginationException>().having(
          (error) => error.code,
          'code',
          'paginationCancelled',
        ),
      );
      expect(coordinator.cache.length, 0);
      await subscription.cancel();
      demand.dispose();
    },
  );

  test(
    'complete-plan callers remain eager when a demand object is supplied',
    () async {
      final chapter = await _prepare(
        '<p><font face="Fantasy Novel Font">${'甲' * 48}</font></p>',
      );
      final demand = NovelReaderPaginationDemand(
        lookAhead: 0,
        idleScheduler: () =>
            throw StateError('Complete plans must not be gated.'),
      )..update(targetPending: false, pageIndex: 0);
      final adapter = _RecordingMeasureAdapter(
        heightFor: (request, _) =>
            (request.endOffset! - request.startOffset!) * 10.0,
      );
      final plan = await _planner(
        adapter,
        workDemand: demand,
      ).paginate(chapter, _key(chapter, height: 80));

      expect(plan.pageCount, 6);
      expect(
        plan.pages.map((page) => _visibleText(page.html)).join(),
        '甲' * 48,
      );
      expect(demand.isDeferring, isFalse);
      demand.dispose();
    },
  );

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

  test(
    'a safe-path failure cannot swallow the atomic candidate limit',
    () async {
      final chapter = await _prepare('<p>${List.filled(9000, '甲').join()}</p>');
      final adapter = _RecordingMeasureAdapter();
      final planner = DefaultNovelReaderHybridPaginationPlanner(
        measureAdapter: adapter,
        preferences: _preferences,
        theme: _theme,
        baseStyle: _baseStyle,
        textRunExtractor: const NovelReaderPaginationTextRunExtractor(
          styleResolver: _ThrowingTextStyleResolver(),
        ),
      );
      await expectLater(
        planner.paginate(chapter, _key(chapter, height: 120)),
        throwsA(
          isA<NovelReaderPaginationException>().having(
            (error) => error.code,
            'code',
            'complexFitSearchCandidateLimitExceeded',
          ),
        ),
      );
      expect(adapter.requests, isEmpty);
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

  for (final failSecondPage in <bool>[false, true]) {
    test(
      failSecondPage
          ? 'a later complex failure preserves the published prefix and falls back only the tail'
          : 'publishes a stable complex first page before measuring the second',
      () async {
        final text = List<String>.filled(96, '甲').join();
        final chapter = await _prepare(
          '<p><font face="Fantasy Novel Font">$text</font></p>',
        );
        final secondPageStarted = Completer<void>();
        final releaseSecondPage = Completer<void>();
        final candidateDomNodeCounts = <int>[];
        final adapter = _RecordingMeasureAdapter(
          heightFor: (request, _) =>
              (request.endOffset! - request.startOffset!) * 10.0,
          beforeMeasure: (request) async {
            final fragment = html_parser.parseFragment(request.html);
            final pending = <html_dom.Node>[...fragment.nodes];
            var nodeCount = 0;
            while (pending.isNotEmpty) {
              final node = pending.removeLast();
              nodeCount += 1;
              pending.addAll(node.nodes);
            }
            candidateDomNodeCounts.add(nodeCount);
            if (request.startOffset! > 0 && !secondPageStarted.isCompleted) {
              secondPageStarted.complete();
              await releaseSecondPage.future;
              if (failSecondPage) {
                throw StateError('synthetic later complex measurement failure');
              }
            }
          },
        );
        final events = <NovelReaderPaginationProgress>[];
        final completed = _planner(adapter)
            .planIncrementally(
              chapter: chapter,
              key: _key(chapter, height: 80),
              cancellationToken: NovelReaderPaginationCancellationToken(),
            )
            .map((progress) {
              events.add(progress);
              return progress;
            })
            .toList();

        try {
          await secondPageStarted.future;
          expect(
            adapter.requests.any(
              (request) => request.startOffset == 0 && request.endOffset == 8,
            ),
            isTrue,
          );
          expect(adapter.requests.last.startOffset, 8);
          expect(events, hasLength(1));
          expect(events.single.isComplete, isFalse);
          expect(events.single.plan.pageCount, 1);
          expect(
            _visibleText(events.single.plan.pages.single.html),
            text.substring(0, 8),
          );
          expect(events.single.plan.flowableComplexFragmentCount, 1);
          expect(events.single.plan.complexBoundaryIndexBuildCount, 1);
          expect(events.single.plan.complexSearchProbeCount, greaterThan(0));
        } finally {
          releaseSecondPage.complete();
        }

        final updates = await completed;
        final plan = updates.last.plan;
        expect(updates.first.plan.pageCount, 1);
        expect(plan.pages.first, same(updates.first.plan.pages.first));
        expect(candidateDomNodeCounts, hasLength(adapter.requests.length));
        expect(
          candidateDomNodeCounts.fold<int>(0, (total, count) => total + count),
          greaterThan(adapter.requests.length),
          reason: 'DOM node cost is recorded only for uncached adapter probes.',
        );
        expect(updates.last.isComplete, isTrue);
        expect(
          plan.routeCounts[NovelReaderPaginationRoute.flowableComplexText],
          1,
        );
        expect(plan.pages.map((page) => _visibleText(page.html)).join(), text);
        if (failSecondPage) {
          expect(plan.pageCount, 2);
          expect(plan.atomicWidgetPageCount, 1);
          expect(plan.flowableComplexFragmentCount, 1);
          expect(plan.pages.last.requiresInnerScroll, isTrue);
          expect(plan.pages.first.startAnchor.textOffset, 0);
          expect(plan.pages.first.endAnchor.textOffset, 8);
          expect(plan.pages.last.startAnchor.textOffset, 8);
          expect(plan.pages.last.endAnchor.textOffset, text.length);
          expect(adapter.requests.last.html, isNot(contains(text)));
          expect(plan.flowabilityFailureReasonCounts, {
            NovelReaderFlowableComplexFallbackReason.measurementFailure: 1,
          });
        } else {
          expect(plan.pageCount, 12);
          expect(plan.flowableComplexFragmentCount, 12);
          expect(plan.atomicWidgetPageCount, 0);
          expect(plan.flowabilityFailureReasonCounts, isEmpty);
        }
      },
    );
  }

  test(
    'an unmeasurable failed tail leaves the stable prefix available',
    () async {
      final text = '甲' * 9000;
      final chapter = await _prepare(
        '<p><font face="Fantasy Novel Font">$text</font></p>',
      );
      final adapter = _RecordingMeasureAdapter(
        heightFor: (request, _) =>
            (request.endOffset! - request.startOffset!) * 10.0,
        beforeMeasure: (request) async {
          if (request.startOffset! > 0) {
            throw StateError('failed uncommitted tail');
          }
        },
      );
      final updates = <NovelReaderPaginationProgress>[];
      await expectLater(
        _planner(adapter)
            .planIncrementally(
              chapter: chapter,
              key: _key(chapter, height: 80),
              cancellationToken: NovelReaderPaginationCancellationToken(),
            )
            .map((progress) {
              updates.add(progress);
              return progress;
            })
            .toList(),
        throwsA(
          isA<NovelReaderPaginationException>().having(
            (e) => e.code,
            'code',
            'complexFitSearchCandidateLimitExceeded',
          ),
        ),
      );
      expect(updates, hasLength(1));
      expect(updates.single.isComplete, isFalse);
      expect(updates.single.plan.pageCount, 1);
      expect(_visibleText(updates.single.plan.pages.single.html), '甲' * 8);
      expect(adapter.requests.every((r) => r.html.length <= 8192), isTrue);
    },
  );

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

  for (final limit in ['html', 'nodes']) {
    test(
      'a flowable failure cannot remeasure a whole atom beyond the $limit limit',
      () async {
        final content = limit == 'html'
            ? List.filled(9000, '甲').join()
            : List.filled(160, '<span>甲</span>').join();
        final chapter = await _prepare(
          '<p><font face="Fantasy Novel Font">$content</font></p>',
        );
        if (limit == 'html') {
          expect(chapter.html.length, greaterThan(8192));
        } else {
          expect(chapter.html.length, lessThanOrEqualTo(8192));
          expect(
            NovelReaderComplexHtmlSearchBudget.countDomNodes(chapter.html),
            greaterThan(256),
          );
        }
        final adapter = _RecordingMeasureAdapter(
          beforeMeasure: (_) async {
            throw StateError(
              'Controlled complex candidate measurement failure.',
            );
          },
        );
        await expectLater(
          _planner(adapter).paginate(chapter, _key(chapter, height: 100)),
          throwsA(
            isA<NovelReaderPaginationException>().having(
              (error) => error.code,
              'code',
              'complexFitSearchCandidateLimitExceeded',
            ),
          ),
        );
        expect(adapter.requests, hasLength(1));
        expect(
          adapter.requests.single.html.length,
          lessThan(chapter.html.length),
        );
        expect(adapter.requests.single.html.length, lessThanOrEqualTo(8192));
      },
    );
  }

  test(
    'a measured oversized minimum becomes a dedicated page without a second probe',
    () async {
      final text = List.filled(9000, '甲').join();
      final chapter = await _prepare('<p><ruby>$text<rt>注</rt></ruby></p>');
      final adapter = _RecordingMeasureAdapter(heightFor: (_, _) => 200);
      final plan = await _planner(
        adapter,
      ).paginate(chapter, _key(chapter, height: 100));

      expect(adapter.requests, hasLength(1));
      expect(plan.measurementCount, 1);
      expect(plan.minimumComplexFragmentCount, 1);
      expect(plan.atomicWidgetPageCount, 1);
      expect(plan.flowableComplexFragmentCount, 0);
      expect(plan.pages, hasLength(1));
      expect(plan.pages.single.requiresInnerScroll, isTrue);
      expect(plan.pages.single.isDedicatedContentPage, isTrue);
      expect(plan.pages.single.html, adapter.requests.single.html);
      expect(_visibleText(plan.pages.single.html), _visibleText(chapter.html));
      expect(plan.flowabilityFailureReasonCounts, {
        NovelReaderFlowableComplexFallbackReason.minimumFragmentOverflow: 1,
      });
    },
  );

  test(
    'an indivisible minimum beyond the finite exception limit is not measured',
    () async {
      final text = List.filled(40000, '甲').join();
      final chapter = await _prepare('<p><ruby>$text<rt>注</rt></ruby></p>');
      final adapter = _RecordingMeasureAdapter();
      await expectLater(
        _planner(adapter).paginate(chapter, _key(chapter, height: 100)),
        throwsA(
          isA<NovelReaderPaginationException>().having(
            (error) => error.code,
            'code',
            'complexFitSearchCandidateLimitExceeded',
          ),
        ),
      );
      expect(adapter.requests, isEmpty);
    },
  );

  for (final code in [
    'complexFitSearchCandidateLimitExceeded',
    'complexFitSearchBudgetUnavailable',
  ]) {
    test(
      'a propagated $code cannot be swallowed into an atomic measurement',
      () async {
        final chapter = await _prepare(
          '<p><font face="Fantasy Novel Font">复杂正文</font></p>',
        );
        final adapter = _RecordingMeasureAdapter();
        await expectLater(
          _planner(
            adapter,
            flowableComplexEngine: _RejectingFlowableEngine(code),
          ).paginate(chapter, _key(chapter, height: 100)),
          throwsA(
            isA<NovelReaderPaginationException>().having(
              (error) => error.code,
              'code',
              code,
            ),
          ),
        );
        expect(adapter.requests, isEmpty);
      },
    );
  }
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
  NovelReaderPaginationMeasureAdapter adapter, {
  NovelReaderFlowableComplexPaginationEngine? flowableComplexEngine,
  NovelReaderPaginationDemand? workDemand,
}) {
  return DefaultNovelReaderHybridPaginationPlanner(
    measureAdapter: adapter,
    preferences: _preferences,
    theme: _theme,
    baseStyle: _baseStyle,
    workDemand: workDemand,
    flowableComplexEngine: flowableComplexEngine,
    validationPolicy: const NovelReaderPaginationValidationPolicy(interval: 8),
  );
}

List<Object?> _anchorValues(NovelReaderTextAnchor anchor) => [
  anchor.episodeId,
  anchor.nodeId,
  anchor.textOffset,
  anchor.pageIndex,
  anchor.scrollOffset,
  anchor.progressPercent,
  anchor.formatVersion,
  anchor.textIdentity,
  anchor.isProgressPercentValid,
];

final class _DemandMeasureSessionFactory
    implements
        NovelReaderPaginationMeasureAdapter,
        NovelReaderPaginationMeasureSessionFactory {
  _DemandMeasureSessionFactory(this.adapter);

  final _RecordingMeasureAdapter adapter;
  final sessions = <_DemandMeasureSession>[];

  @override
  NovelReaderPaginationMeasureSession create({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
  }) {
    final session = _DemandMeasureSession(adapter);
    sessions.add(session);
    return session;
  }

  @override
  Future<NovelReaderPaginationMeasureResult> measure(
    NovelReaderPaginationMeasureRequest request,
  ) => adapter.measure(request);
}

final class _DemandMeasureSession
    implements NovelReaderPaginationMeasureSession {
  _DemandMeasureSession(this.adapter);

  final _RecordingMeasureAdapter adapter;
  int disposeCalls = 0;

  @override
  Future<NovelReaderPaginationMeasureResult> measure(
    NovelReaderPaginationMeasureRequest request,
  ) => adapter.measure(request);

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
  }
}

final class _RejectingFlowableEngine
    implements NovelReaderFlowableComplexPaginationEngine {
  const _RejectingFlowableEngine(this.code);

  final String code;

  @override
  Future<NovelReaderFlowableComplexPaginationResult> paginate({
    required NovelReaderClassifiedPaginationAtom atom,
    required NovelReaderPaginationPageContext page,
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
    required NovelReaderPaginationMeasureSession measureSession,
    required NovelReaderPaginationCancellationToken cancellationToken,
    NovelReaderFlowableComplexChunkConsumer? onChunk,
  }) async {
    throw NovelReaderPaginationException(
      code: code,
      message: 'Controlled bounded engine failure.',
    );
  }
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
  _RecordingMeasureAdapter({this.heightFor, this.beforeMeasure});

  final _HeightFor? heightFor;
  final Future<void> Function(NovelReaderPaginationMeasureRequest)?
  beforeMeasure;
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
    final beforeMeasure = this.beforeMeasure;
    if (beforeMeasure != null) {
      await beforeMeasure(request);
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

final class _GatedSessionFactory
    implements
        NovelReaderPaginationMeasureAdapter,
        NovelReaderPaginationMeasureSessionFactory {
  _GatedSessionFactory({bool disposeCompletesError = false})
    : session = _GatedLifecycleMeasureSession(disposeCompletesError);

  final _GatedLifecycleMeasureSession session;

  @override
  NovelReaderPaginationMeasureSession create({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
  }) => session;

  @override
  Future<NovelReaderPaginationMeasureResult> measure(
    NovelReaderPaginationMeasureRequest request,
  ) => session.measure(request);
}

final class _GatedLifecycleMeasureSession
    implements NovelReaderPaginationMeasureSession {
  _GatedLifecycleMeasureSession(this.disposeCompletesError);

  final bool disposeCompletesError;
  final started = Completer<void>();
  final result = Completer<NovelReaderPaginationMeasureResult>();
  int measureCalls = 0;
  int disposeCalls = 0;

  @override
  Future<NovelReaderPaginationMeasureResult> measure(
    NovelReaderPaginationMeasureRequest request,
  ) {
    measureCalls += 1;
    if (!started.isCompleted) started.complete();
    return result.future;
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    if (disposeCompletesError && !result.isCompleted) {
      result.completeError(
        const NovelReaderPaginationException(
          code: 'measurementSessionDisposed',
          message: 'Controlled probe disposal.',
        ),
      );
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
