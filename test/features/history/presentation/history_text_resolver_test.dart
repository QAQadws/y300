import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart' as date_symbol_data;
import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/history/domain/services/history_date_grouping_policy.dart';
import 'package:y300/features/history/presentation/history_text_resolver.dart';
import 'package:y300/l10n/app_localizations_zh.dart';

import '../test_support/history_test_support.dart';

void main() {
  final zh = AppLocalizationsZh();
  final zhTw = AppLocalizationsZhTw();

  setUpAll(date_symbol_data.initializeDateFormatting);

  test('resolves target type labels for both supported locales', () {
    expect(
      HistoryTextResolver.typeLabel(zh, HistoryTargetType.thread),
      zh.historyTypeThread,
    );
    expect(
      HistoryTextResolver.typeLabel(zhTw, HistoryTargetType.comic),
      zhTw.historyTypeComic,
    );
    expect(
      HistoryTextResolver.typeLabel(zhTw, HistoryTargetType.novel),
      zhTw.historyTypeNovel,
    );
    expect(
      HistoryTextResolver.typeLabel(zh, HistoryTargetType.blog),
      zh.historyTypeBlog,
    );
    expect(
      HistoryTextResolver.typeLabel(zhTw, HistoryTargetType.blog),
      zhTw.historyTypeBlog,
    );
  });

  test('localizes blog framing while retaining source titles and authors', () {
    final entry = historyEntry(
      type: HistoryTargetType.blog,
      id: '101:23',
      title: '日志原文',
      contextLabel: '原作者名字',
      visitedAt: DateTime.utc(2026, 9, 27),
    );
    final empty = historyEntry(
      type: HistoryTargetType.blog,
      id: '101:24',
      title: '',
      contextLabel: '',
      visitedAt: DateTime.utc(2026, 9, 27),
    );

    for (final l10n in [zh, zhTw]) {
      expect(HistoryTextResolver.entryTitle(l10n, entry), entry.title);
      expect(
        HistoryTextResolver.entryContext(l10n, entry),
        l10n.historyBlogAuthor(entry.contextLabel),
      );
      expect(HistoryTextResolver.entryTitle(l10n, empty), l10n.historyTypeBlog);
      expect(
        HistoryTextResolver.entryContext(l10n, empty),
        l10n.historyTypeBlog,
      );
    }
  });

  test('formats relative and calendar date groups in presentation', () {
    const entry = <HistoryEntry>[];
    expect(
      HistoryTextResolver.dateGroupLabel(
        zh,
        HistoryDateGroup(
          localDate: DateTime(2026, 7, 16),
          daysAgo: 0,
          entries: entry,
        ),
      ),
      zh.historyToday,
    );
    expect(
      HistoryTextResolver.dateGroupLabel(
        zhTw,
        HistoryDateGroup(
          localDate: DateTime(2026, 7, 10),
          daysAgo: 6,
          entries: entry,
        ),
      ),
      zhTw.historyDaysAgo(6),
    );

    final calendarDate = DateTime(2025, 12, 31);
    expect(
      HistoryTextResolver.dateGroupLabel(
        zhTw,
        HistoryDateGroup(localDate: calendarDate, daysAgo: 7, entries: entry),
      ),
      DateFormat.yMd(zhTw.localeName).format(calendarDate),
    );
  });

  test('maps structured unavailable results without routing text', () {
    expect(
      HistoryTextResolver.unavailableMessage(
        zh,
        const HistoryOpenUnavailable(
          code: HistoryOpenUnavailableCode.localWorkRemoved,
          targetType: HistoryTargetType.comic,
        ),
      ),
      zh.historyWorkUnavailable(zh.historyTypeComic),
    );
    expect(
      HistoryTextResolver.unavailableMessage(
        zhTw,
        const HistoryOpenUnavailable(
          code: HistoryOpenUnavailableCode.threadExpired,
        ),
      ),
      zhTw.historyThreadExpired,
    );
    expect(
      HistoryTextResolver.unavailableMessage(
        zh,
        const HistoryOpenUnavailable(message: 'legacy detail'),
      ),
      'legacy detail',
    );
  });

  test('redacts and bounds error summaries', () {
    expect(
      HistoryTextResolver.safeErrorSummary(
        StateError(
          'Cookie: secret request https://example.test/?formhash=secret failed',
        ),
      ),
      contains('[url]'),
    );
    expect(
      HistoryTextResolver.safeErrorSummary('formhash=secret failed'),
      isNot(contains('secret')),
    );
    expect(HistoryTextResolver.safeErrorSummary('x' * 200), hasLength(160));
  });
}
