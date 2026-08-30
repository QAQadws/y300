import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
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

  test('maps stable poll rejection codes without exposing server payloads', () {
    const cases = <String, String Function(AppLocalizationsZh)>{
      'thread_poll_voted': _alreadyVoted,
      'thread_poll_closed': _closed,
      'poll_overdue': _expired,
      'poll_choose_most': _tooMany,
      'thread_poll_invalid': _unavailable,
      'parameters_error': _invalidSelection,
      'submit_invalid': _sessionExpired,
      'group_nopermission': _permissionDenied,
    };

    for (final entry in cases.entries) {
      final text = ThreadTextResolver.actionNotice(
        zh,
        ThreadActionNotice(
          code: ThreadActionNoticeCode.failure,
          action: ThreadActionKind.vote,
          commandFailure: DataCommandFailure(
            kind: DataCommandFailureKind.validation,
            retryPolicy: DataCommandRetryPolicy.explicitOnly,
            code: entry.key,
            diagnosticMessage: 'private server payload',
          ),
        ),
      );
      expect(text, entry.value(zh), reason: entry.key);
      expect(text, isNot(contains('private server payload')));
    }
  });

  test('keeps an unproved sent poll result explicitly unknown', () {
    expect(
      ThreadTextResolver.actionNotice(
        zhTw,
        const ThreadActionNotice(
          code: ThreadActionNoticeCode.unknown,
          action: ThreadActionKind.vote,
        ),
      ),
      zhTw.threadPollVoteOutcomeUnknown,
    );
  });

  test('prefers a stable poll code over a generic login suffix category', () {
    expect(
      ThreadTextResolver.actionNotice(
        zh,
        const ThreadActionNotice(
          code: ThreadActionNoticeCode.loginRequired,
          action: ThreadActionKind.vote,
          commandFailure: DataCommandFailure(
            kind: DataCommandFailureKind.unauthenticated,
            retryPolicy: DataCommandRetryPolicy.afterSessionRefresh,
            code: 'thread_poll_voted',
            diagnosticMessage: 'thread_poll_voted',
          ),
        ),
      ),
      zh.threadPollVoteAlreadyVoted,
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

String _alreadyVoted(AppLocalizationsZh l10n) =>
    l10n.threadPollVoteAlreadyVoted;
String _closed(AppLocalizationsZh l10n) => l10n.threadPollVoteClosed;
String _expired(AppLocalizationsZh l10n) => l10n.threadPollVoteExpired;
String _tooMany(AppLocalizationsZh l10n) => l10n.threadPollVoteTooMany;
String _unavailable(AppLocalizationsZh l10n) => l10n.threadPollVoteUnavailable;
String _invalidSelection(AppLocalizationsZh l10n) =>
    l10n.threadPollVoteInvalidSelection;
String _sessionExpired(AppLocalizationsZh l10n) =>
    l10n.threadPollVoteSessionExpired;
String _permissionDenied(AppLocalizationsZh l10n) =>
    l10n.threadPermissionDenied;
