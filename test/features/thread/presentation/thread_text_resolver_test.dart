import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/domain/models/thread_ui_feedback.dart';
import 'package:y300/features/thread/presentation/thread_text_resolver.dart';
import 'package:y300/l10n/app_localizations_zh.dart';

void main() {
  final zh = AppLocalizationsZh();
  final zhTw = AppLocalizationsZhTw();

  test('resolves stable thread labels through the active locale', () {
    expect(ThreadTextResolver.detailTitle(zh, ''), zh.threadDetailTitle);
    expect(ThreadTextResolver.detailTitle(zhTw, ''), zhTw.threadDetailTitle);
    expect(ThreadTextResolver.pageLabel(zh, 3), zh.threadDetailPage(3));
    expect(
      ThreadTextResolver.copySuccess(zhTw, zhTw.threadDetailPostLink),
      zhTw.threadDetailCopySuccess(zhTw.threadDetailPostLink),
    );
  });

  test('maps action notices and failures without putting UI text in state', () {
    expect(
      ThreadTextResolver.actionNotice(
        zh,
        const ThreadActionNotice(
          code: ThreadActionNoticeCode.success,
          action: ThreadActionKind.vote,
        ),
      ),
      zh.threadPollVoteSuccess,
    );
    expect(
      ThreadTextResolver.actionNotice(
        zhTw,
        const ThreadActionNotice(
          code: ThreadActionNoticeCode.validation,
          action: ThreadActionKind.vote,
          maxChoices: 2,
        ),
      ),
      zhTw.threadPollMaxChoices(2),
    );
    expect(
      ThreadTextResolver.actionFailure(
        zh,
        const ThreadActionFailure(
          code: ThreadUiErrorCode.loginRequired,
          action: ThreadActionKind.reply,
        ),
      ),
      zh.threadLoginRequired,
    );
  });

  test('formats poll and rating numeric values with localized resources', () {
    expect(ThreadTextResolver.pollVotes(zhTw, 5), zhTw.threadPollVotes(5));
    expect(
      ThreadTextResolver.ratingRange(zh, 1, 10, 3),
      zh.threadRatingRangeWithRemaining(zh.threadRatingRange(1, 10), 3),
    );
  });

  test('redacts sensitive details before exposing an error summary', () {
    final summary = ThreadTextResolver.safeErrorSummary(
      'Cookie=secret https://bbs.yamibo.com/forum.php?formhash=token\nnext',
    );

    expect(summary, isNot(contains('secret')));
    expect(summary, isNot(contains('https://')));
    expect(summary, isNot(contains('\n')));
    expect(summary.length, lessThanOrEqualTo(160));
  });

  test('keeps raw server details instead of translating them', () {
    const raw = '服务器返回的业务提示';
    final result = ThreadTextResolver.actionNotice(
      zh,
      const ThreadActionNotice(
        code: ThreadActionNoticeCode.success,
        action: ThreadActionKind.reply,
        detail: raw,
      ),
    );

    expect(result, raw);
  });
}
