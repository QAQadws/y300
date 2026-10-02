import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import '../contracts/data_read_contract.dart';
import '../contracts/forum_daily_sign_in.dart';

/// A safe, stable failure while reading the mobile sign-in page.
final class DiscuzDailySignInParseFailure implements Exception {
  /// Creates a failure without retaining response content or a sign-in URL.
  const DiscuzDailySignInParseFailure(this.code, this.kind);

  /// A protocol diagnostic safe to include in logs.
  final String code;

  /// Category for a future read adapter to return to callers.
  final DataReadFailureKind kind;

  @override
  String toString() => 'DiscuzDailySignInParseFailure($code)';
}

/// A verified snapshot and a page-local, non-public sign-in action.
final class DiscuzDailySignInPage {
  /// Creates the result of a read-only parse.
  const DiscuzDailySignInPage({required this.snapshot, this.signUri});

  /// State established by the server-rendered page.
  final ForumDailySignInSnapshot snapshot;

  /// Opaque action for a future adapter; absent once today's sign-in is proved.
  ///
  /// Do not persist, log, or expose this URI outside the package adapter.
  final Uri? signUri;
}

/// Parses a fresh mobile sign-in page without executing links or scripts.
final class DiscuzDailySignInPageParser {
  /// Creates a stateless parser.
  const DiscuzDailySignInPageParser();

  /// Checks response location, identity, day, calendar, button, and action.
  ///
  /// [requestedUri] is the canonical mobile page request. [sourceUri] is the
  /// final response URI, so a login or other redirect cannot masquerade as
  /// today's unsigned state.
  DiscuzDailySignInPage parse(
    String source, {
    required Uri requestedUri,
    required Uri sourceUri,
    required String expectedUserId,
  }) {
    final document = html_parser.parse(source);
    if (document.querySelector('form#loginform, .loginbox') != null) {
      throw const DiscuzDailySignInParseFailure(
        'daily_sign_in_login_required',
        DataReadFailureKind.unauthorized,
      );
    }
    if (!_isCanonicalPageUri(requestedUri) ||
        !_isCanonicalPageUri(sourceUri) ||
        !_sameOrigin(requestedUri, sourceUri)) {
      throw const DiscuzDailySignInParseFailure(
        'daily_sign_in_response_uri_invalid',
        DataReadFailureKind.parse,
      );
    }
    if (!RegExp(r'^[1-9][0-9]*$').hasMatch(expectedUserId)) {
      throw const DiscuzDailySignInParseFailure(
        'daily_sign_in_expected_user_invalid',
        DataReadFailureKind.parse,
      );
    }

    final scriptText = document
        .querySelectorAll('script')
        .where((element) => !element.attributes.containsKey('src'))
        .map((element) => element.text)
        .join('\n');
    final uidMatches = RegExp(
      r'''(?:^|[,;\s])discuz_uid\s*=\s*(['"])([0-9]+)\1''',
    ).allMatches(scriptText).toList();
    if (uidMatches.length != 1) {
      throw const DiscuzDailySignInParseFailure(
        'daily_sign_in_user_unverified',
        DataReadFailureKind.parse,
      );
    }
    final pageUserId = uidMatches.single.group(2)!;
    if (pageUserId == '0') {
      throw const DiscuzDailySignInParseFailure(
        'daily_sign_in_login_required',
        DataReadFailureKind.unauthorized,
      );
    }
    if (pageUserId != expectedUserId) {
      throw const DiscuzDailySignInParseFailure(
        'daily_sign_in_user_mismatch',
        DataReadFailureKind.parse,
      );
    }

    final serverDate = _serverDate(document);
    final today = _todayCell(document, serverDate);
    final status = today.classes.contains('on')
        ? ForumDailySignInStatus.signed
        : ForumDailySignInStatus.unsigned;
    final button = _signInButton(document, status);
    final validatedSignUri = _signUri(button, sourceUri);
    final statistics = _statistics(document);
    return DiscuzDailySignInPage(
      snapshot: ForumDailySignInSnapshot(
        userId: pageUserId,
        forumDay: serverDate.dayKey,
        status: status,
        statistics: statistics,
      ),
      signUri: status == ForumDailySignInStatus.unsigned
          ? validatedSignUri
          : null,
    );
  }

  _ForumDate _serverDate(html_dom.Document document) {
    final clocks = document.querySelectorAll('em#showtime');
    if (clocks.length != 1 ||
        clocks.single.parent?.localName != 'span' ||
        !clocks.single.parent!.classes.contains('y') ||
        clocks.single.parent!.parent?.classes.contains('hui-content') != true) {
      throw const DiscuzDailySignInParseFailure(
        'daily_sign_in_server_date_missing',
        DataReadFailureKind.parse,
      );
    }
    final matches = RegExp(
      r'([0-9]{4})年\s*([0-9]{1,2})月\s*([0-9]{1,2})日',
    ).allMatches(clocks.single.parent!.text).toList();
    if (matches.length != 1) {
      throw const DiscuzDailySignInParseFailure(
        'daily_sign_in_server_date_invalid',
        DataReadFailureKind.parse,
      );
    }
    final match = matches.single;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    if (!_validDate(year, month, day)) {
      throw const DiscuzDailySignInParseFailure(
        'daily_sign_in_server_date_invalid',
        DataReadFailureKind.parse,
      );
    }
    return _ForumDate(year, month, day);
  }

  html_dom.Element _todayCell(
    html_dom.Document document,
    _ForumDate serverDate,
  ) {
    final calendars = document.querySelectorAll('#calendar');
    if (calendars.length != 1) {
      throw const DiscuzDailySignInParseFailure(
        'daily_sign_in_calendar_missing',
        DataReadFailureKind.parse,
      );
    }
    final calendar = calendars.single;
    final headings = calendar.querySelectorAll('#tablehead th[colspan="7"]');
    final dayTables = calendar.querySelectorAll('#tablebody');
    if (headings.length != 1 || dayTables.length != 1) {
      throw const DiscuzDailySignInParseFailure(
        'daily_sign_in_calendar_invalid',
        DataReadFailureKind.parse,
      );
    }
    final monthMatches = RegExp(
      r'([0-9]{4})年\s*([0-9]{1,2})月',
    ).allMatches(headings.single.text).toList();
    if (monthMatches.length != 1 ||
        int.parse(monthMatches.single.group(1)!) != serverDate.year ||
        int.parse(monthMatches.single.group(2)!) != serverDate.month) {
      throw const DiscuzDailySignInParseFailure(
        'daily_sign_in_calendar_month_mismatch',
        DataReadFailureKind.parse,
      );
    }
    final todayCells = dayTables.single.querySelectorAll('.day.today');
    if (todayCells.length != 1 ||
        calendar.querySelectorAll('.day.today').length != 1 ||
        todayCells.single.parent?.localName != 'td' ||
        todayCells.single.text.trim() != serverDate.day.toString() ||
        !todayCells.single.classes.contains('day') ||
        todayCells.single.classes.any(
          (name) => name != 'day' && name != 'today' && name != 'on',
        )) {
      throw const DiscuzDailySignInParseFailure(
        'daily_sign_in_today_cell_invalid',
        DataReadFailureKind.parse,
      );
    }
    return todayCells.single;
  }

  html_dom.Element _signInButton(
    html_dom.Document document,
    ForumDailySignInStatus status,
  ) {
    final buttons = document
        .querySelectorAll('.signbtn a.btna')
        .where(
          (element) =>
              element.text.trim() == '点击打卡' || element.text.trim() == '今日已打卡',
        );
    if (buttons.length != 1 ||
        buttons.single.text.trim() !=
            (status == ForumDailySignInStatus.signed ? '今日已打卡' : '点击打卡')) {
      throw const DiscuzDailySignInParseFailure(
        'daily_sign_in_button_state_mismatch',
        DataReadFailureKind.parse,
      );
    }
    return buttons.single;
  }

  Uri _signUri(html_dom.Element button, Uri sourceUri) {
    final href = button.attributes['href'];
    final candidate = href == null ? null : Uri.tryParse(href);
    if (candidate == null) {
      throw const DiscuzDailySignInParseFailure(
        'daily_sign_in_action_invalid',
        DataReadFailureKind.parse,
      );
    }
    final action = sourceUri.resolveUri(candidate);
    final query = action.queryParametersAll;
    final token = query['sign'];
    if (!_sameOrigin(sourceUri, action) ||
        action.userInfo.isNotEmpty ||
        action.path != '/plugin.php' ||
        action.fragment.isNotEmpty ||
        query.length != 2 ||
        query['id']?.length != 1 ||
        query['id']!.single != 'zqlj_sign' ||
        token?.length != 1 ||
        !RegExp(r'^[A-Za-z0-9_-]{1,256}$').hasMatch(token!.single)) {
      throw const DiscuzDailySignInParseFailure(
        'daily_sign_in_action_invalid',
        DataReadFailureKind.parse,
      );
    }
    return action;
  }

  List<ForumDailySignInStatistic>? _statistics(html_dom.Document document) {
    final titles = document
        .querySelectorAll('.hui-common-title-txt')
        .where((element) => element.text.trim() == '我的打卡动态')
        .toList();
    if (titles.isEmpty) return null;
    if (titles.length != 1) {
      throw const DiscuzDailySignInParseFailure(
        'daily_sign_in_statistics_invalid',
        DataReadFailureKind.parse,
      );
    }
    final list = titles.single.parent?.nextElementSibling;
    if (list == null || !list.classes.contains('hui-list')) {
      throw const DiscuzDailySignInParseFailure(
        'daily_sign_in_statistics_invalid',
        DataReadFailureKind.parse,
      );
    }
    final rows = list.querySelectorAll('.hui-list-text');
    final statistics = <ForumDailySignInStatistic>[];
    for (final row in rows) {
      final text = row.text.trim();
      final divider = text.indexOf('：');
      if (divider <= 0 || divider == text.length - 1) {
        throw const DiscuzDailySignInParseFailure(
          'daily_sign_in_statistics_invalid',
          DataReadFailureKind.parse,
        );
      }
      statistics.add(
        ForumDailySignInStatistic(
          label: text.substring(0, divider),
          value: text.substring(divider + 1),
        ),
      );
    }
    return List<ForumDailySignInStatistic>.unmodifiable(statistics);
  }

  bool _isCanonicalPageUri(Uri uri) {
    final query = uri.queryParametersAll;
    return uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        uri.path == '/plugin.php' &&
        uri.fragment.isEmpty &&
        query.length == 2 &&
        query['id']?.length == 1 &&
        query['id']!.single == 'zqlj_sign' &&
        query['mobile']?.length == 1 &&
        query['mobile']!.single == '2';
  }

  bool _sameOrigin(Uri left, Uri right) =>
      left.scheme == right.scheme &&
      left.host == right.host &&
      left.port == right.port;

  bool _validDate(int year, int month, int day) {
    final date = DateTime.utc(year, month, day);
    return date.year == year && date.month == month && date.day == day;
  }
}

final class _ForumDate {
  const _ForumDate(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;

  String get dayKey =>
      '${year.toString().padLeft(4, '0')}'
      '${month.toString().padLeft(2, '0')}'
      '${day.toString().padLeft(2, '0')}';
}
