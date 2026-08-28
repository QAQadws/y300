import 'package:y300/features/thread/domain/models/thread_ui_feedback.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/services/localized_error_summary.dart';

/// Presentation-only mapping for thread UI text.
///
/// Server-provided titles, authors, body text and action responses remain raw.
/// This resolver only turns stable application semantics into localized UI.
final class ThreadTextResolver {
  const ThreadTextResolver._();

  static String detailTitle(AppLocalizations l10n, String? rawForumName) {
    final value = rawForumName?.trim();
    return value == null || value.isEmpty ? l10n.threadDetailTitle : value;
  }

  static String pageLabel(AppLocalizations l10n, int page) {
    return l10n.threadDetailPage(page <= 0 ? 1 : page);
  }

  static String copySuccess(AppLocalizations l10n, String target) {
    final value = target.trim();
    return l10n.threadDetailCopySuccess(value.isEmpty ? '' : value);
  }

  static String loadFailure(
    AppLocalizations l10n,
    ThreadUiErrorCode code,
    Object? detail,
  ) {
    if (code == ThreadUiErrorCode.loginRequired) {
      return l10n.threadLoginRequired;
    }
    if (code == ThreadUiErrorCode.permissionDenied) {
      return l10n.threadPermissionDenied;
    }
    final safe = _detailOrUnknown(l10n, detail);
    return switch (code) {
      ThreadUiErrorCode.refreshFailed => l10n.threadDetailRefreshFailed(safe),
      ThreadUiErrorCode.pageLoadFailed => l10n.threadDetailPageLoadFailed(safe),
      _ => l10n.threadDetailLoadFailed(safe),
    };
  }

  static String actionFailure(
    AppLocalizations l10n,
    ThreadActionFailure failure,
  ) {
    if (failure.code == ThreadUiErrorCode.loginRequired) {
      return l10n.threadLoginRequired;
    }
    if (failure.code == ThreadUiErrorCode.permissionDenied) {
      return l10n.threadPermissionDenied;
    }
    if (failure.code == ThreadUiErrorCode.unsupported) {
      return l10n.threadUnsupported;
    }
    final safe = _detailOrUnknown(l10n, failure.detail ?? failure.message);
    return switch (failure.code) {
      ThreadUiErrorCode.favoriteFailed => l10n.threadFavoriteFailed(safe),
      ThreadUiErrorCode.voteFailed => l10n.threadPollVoteFailed(safe),
      ThreadUiErrorCode.rateFailed => l10n.threadRatingFailed(safe),
      ThreadUiErrorCode.commentFailed => l10n.threadCommentFailed(safe),
      ThreadUiErrorCode.replyFailed => l10n.threadReplyFailed(safe),
      ThreadUiErrorCode.unknown
          when failure.action == ThreadActionKind.ratings =>
        l10n.threadRatingLoadFailed,
      _ => l10n.threadDetailLoadFailed(safe),
    };
  }

  static String actionNotice(AppLocalizations l10n, ThreadActionNotice notice) {
    if (notice.code == ThreadActionNoticeCode.validation) {
      return notice.action == ThreadActionKind.vote && notice.maxChoices != null
          ? pollMaxChoices(l10n, notice.maxChoices!)
          : l10n.threadPollSelectOption;
    }
    if (notice.code == ThreadActionNoticeCode.loginRequired) {
      return l10n.threadLoginRequired;
    }
    if (notice.code == ThreadActionNoticeCode.permissionDenied) {
      return l10n.threadPermissionDenied;
    }
    if (notice.code == ThreadActionNoticeCode.unsupported) {
      return l10n.threadUnsupported;
    }
    if (notice.code == ThreadActionNoticeCode.success) {
      final detail = _nonEmpty(notice.detail ?? notice.message);
      return switch (notice.action) {
        ThreadActionKind.favorite => detail ?? l10n.threadFavoriteSuccess,
        ThreadActionKind.vote => detail ?? l10n.threadPollVoteSuccess,
        ThreadActionKind.rate => detail ?? l10n.threadRatingSuccess,
        ThreadActionKind.comment => detail ?? l10n.threadCommentSuccess,
        ThreadActionKind.reply => detail ?? l10n.threadReplySuccess,
        _ => detail ?? l10n.threadDetailTitle,
      };
    }
    if (notice.code == ThreadActionNoticeCode.partialSuccess &&
        notice.action == ThreadActionKind.favorite) {
      return l10n.threadFavoriteSuccessSyncFailed;
    }
    if (notice.code == ThreadActionNoticeCode.unknown) {
      if (notice.action == ThreadActionKind.rate) {
        return l10n.threadRatingOutcomeUnknown;
      }
      if (notice.action == ThreadActionKind.comment) {
        return l10n.threadCommentOutcomeUnknown;
      }
    }
    if (notice.commandFailure != null) {
      final detail = LocalizedErrorSummary.resolve(l10n, notice.commandFailure);
      return switch (notice.action) {
        ThreadActionKind.favorite => l10n.threadFavoriteFailed(detail),
        ThreadActionKind.rate => l10n.threadRatingFailed(detail),
        ThreadActionKind.comment => l10n.threadCommentFailed(detail),
        ThreadActionKind.vote => l10n.threadPollVoteFailed(detail),
        ThreadActionKind.reply => l10n.threadReplyFailed(detail),
        _ => l10n.threadDetailLoadFailed(detail),
      };
    }
    final failure = ThreadActionFailure(
      code: switch (notice.action) {
        ThreadActionKind.favorite => ThreadUiErrorCode.favoriteFailed,
        ThreadActionKind.vote => ThreadUiErrorCode.voteFailed,
        ThreadActionKind.rate => ThreadUiErrorCode.rateFailed,
        ThreadActionKind.comment => ThreadUiErrorCode.commentFailed,
        ThreadActionKind.reply => ThreadUiErrorCode.replyFailed,
        _ => ThreadUiErrorCode.unknown,
      },
      action: notice.action,
      detail: notice.detail,
      message: notice.message,
    );
    return actionFailure(l10n, failure);
  }

  static String pollMaxChoices(AppLocalizations l10n, int count) {
    return l10n.threadPollMaxChoices(count);
  }

  static String pollVotes(AppLocalizations l10n, int count) {
    return l10n.threadPollVotes(count);
  }

  static String ratingRange(
    AppLocalizations l10n,
    int min,
    int max,
    int remaining,
  ) {
    final range = l10n.threadRatingRange(min, max);
    return remaining <= 0
        ? range
        : l10n.threadRatingRangeWithRemaining(range, remaining);
  }

  static String safeErrorSummary(Object? error) {
    var value = error?.toString().replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
    if (value.isEmpty) {
      return '';
    }
    value = value.replaceAll(
      RegExp(r'https?://\S+', caseSensitive: false),
      '[url]',
    );
    value = value.replaceAll(
      RegExp(
        r'(cookie|formhash|uploadhash)\s*[:=]\s*\S+',
        caseSensitive: false,
      ),
      '[redacted]',
    );
    return value.length <= 160 ? value : '${value.substring(0, 157)}...';
  }

  static String _detailOrUnknown(AppLocalizations l10n, Object? detail) {
    return _nonEmpty(safeErrorSummary(detail)) ?? l10n.commonUnknownError;
  }

  static String? _nonEmpty(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
