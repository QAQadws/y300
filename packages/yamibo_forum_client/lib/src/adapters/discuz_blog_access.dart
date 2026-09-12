import 'package:html/parser.dart' as html;

import '../contracts/data_read_contract.dart';
import 'discuz_profile_html_parsers.dart';

/// Recognizes access interstitials without exposing a server payload as UI text.
abstract final class DiscuzBlogAccess {
  /// Returns a classified failure only for an observed access boundary.
  static DataReadFailure<T, C>? failure<T, C>(String source) {
    if (DiscuzProfileAuthPageDetector.isLoginPage(source)) {
      return const DataReadFailure(
        kind: DataReadFailureKind.unauthorized,
        code: 'user_blog_login_required',
        diagnosticMessage: 'user_blog_login_required',
      );
    }
    final document = html.parse(source);
    if (document.querySelector('form#invalueform input[name="viewpwd"]') !=
        null) {
      return const DataReadFailure(
        kind: DataReadFailureKind.business,
        code: 'user_blog_password_required',
        diagnosticMessage: 'user_blog_password_required',
      );
    }
    // space_privacy falls back to the desktop template even in mobile mode.
    if (document.querySelector('#ct .nfl .f_c table .avt') != null &&
        document.querySelector('#ct a[href*="do=friend"]') != null) {
      return const DataReadFailure(
        kind: DataReadFailureKind.business,
        code: 'user_blog_private',
        diagnosticMessage: 'user_blog_private',
      );
    }
    final notice = document.querySelector(
      '#messagetext, .jump_c, .alert_error',
    );
    if (notice != null &&
        document.querySelector(
              '.viewthread .message, .threadlist .threadlist_tit',
            ) ==
            null) {
      // Missing, moderated, disabled, and unauthorized content can deliberately
      // use the same server notice. Do not guess existence or leak its payload.
      return const DataReadFailure(
        kind: DataReadFailureKind.business,
        code: 'user_blog_unavailable',
        diagnosticMessage: 'user_blog_unavailable',
      );
    }
    return null;
  }
}
