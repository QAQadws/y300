import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

final class ThreadPostRatingDetails {
  const ThreadPostRatingDetails({
    required this.participantCount,
    required this.totalScoreText,
    required this.ratings,
  });

  final int participantCount;
  final String totalScoreText;
  final List<ThreadPostRating> ratings;
}

abstract interface class ThreadPostRatingsRepository {
  Future<ApiResult<ThreadPostRatingDetails>> loadAll(String viewAllUrl);
}

final class ThreadPostRatingsHtmlParser {
  const ThreadPostRatingsHtmlParser();

  ThreadPostRatingDetails parse(String response) {
    final fragment = _extractAjaxFragment(response);
    if (fragment == null) {
      throw const ThreadPostRatingsParseException('完整评分 AJAX 响应缺少 CDATA 内容');
    }
    final document = html_parser.parse(fragment);
    final table = document.querySelector('.f_c table.list');
    if (table == null) {
      throw const ThreadPostRatingsParseException('完整评分表格缺失');
    }

    final rows = table.querySelectorAll('tr');
    final header = _findHeader(rows);
    if (header == null) {
      throw const ThreadPostRatingsParseException('完整评分表头缺失');
    }

    final drafts = _parseRows(rows, header);
    if (drafts.isEmpty) {
      throw const ThreadPostRatingsParseException('完整评分列表缺失');
    }

    final ratings = drafts
        .map(
          (draft) => ThreadPostRating(
            userName: draft.userName,
            score: draft.score,
            reason: draft.reason,
            dateline: draft.dateline.isEmpty ? null : draft.dateline,
          ),
        )
        .toList(growable: false);
    final rawTotal = _cleanText(document.querySelector('.o.pns')?.text ?? '');
    final totalScoreText = rawTotal
        .replaceFirst(RegExp(r'^总计\s*[:：]?\s*'), '')
        .trim();

    return ThreadPostRatingDetails(
      participantCount: ratings.length,
      totalScoreText: totalScoreText.isEmpty
          ? _sumScoreText(ratings)
          : totalScoreText,
      ratings: List<ThreadPostRating>.unmodifiable(ratings),
    );
  }

  _ThreadPostRatingHeader? _findHeader(List<html_dom.Element> rows) {
    for (final row in rows) {
      final cells = _cellsOf(row);
      if (cells.isEmpty) {
        continue;
      }
      final texts = cells.map((cell) => _cleanText(cell.text)).toList();
      final scoreIndex = texts.indexWhere((text) => text == '积分');
      final userIndex = texts.indexWhere((text) => text.contains('用户名'));
      final datelineIndex = texts.indexWhere((text) => text.contains('时间'));
      final reasonIndex = texts.indexWhere((text) => text.contains('理由'));
      if (scoreIndex >= 0 && userIndex >= 0 && datelineIndex >= 0) {
        return _ThreadPostRatingHeader(
          scoreIndex: scoreIndex,
          userIndex: userIndex,
          datelineIndex: datelineIndex,
          reasonIndex: reasonIndex,
          row: row,
        );
      }
    }
    return null;
  }

  List<_ThreadPostRatingDraft> _parseRows(
    List<html_dom.Element> rows,
    _ThreadPostRatingHeader header,
  ) {
    final drafts = <_ThreadPostRatingDraft>[];
    final headerIndex = rows.indexOf(header.row);
    for (final row in rows.skip(headerIndex + 1)) {
      final cells = _cellsOf(row);
      final requiredLastIndex = <int>[
        header.scoreIndex,
        header.userIndex,
        header.datelineIndex,
      ].reduce((left, right) => left > right ? left : right);
      if (cells.length <= requiredLastIndex) {
        continue;
      }
      final score = _cleanText(cells[header.scoreIndex].text);
      final userName = _cleanText(cells[header.userIndex].text);
      if (score.isEmpty || userName.isEmpty) {
        continue;
      }
      drafts.add(
        _ThreadPostRatingDraft(
          userName: userName,
          score: _normalizeScore(score),
          dateline: _cleanText(cells[header.datelineIndex].text),
          reason: header.reasonIndex >= 0 && cells.length > header.reasonIndex
              ? _cleanText(cells[header.reasonIndex].text)
              : '',
        ),
      );
    }
    return drafts;
  }

  List<html_dom.Element> _cellsOf(html_dom.Element row) {
    return row.children
        .where(
          (element) => element.localName == 'th' || element.localName == 'td',
        )
        .toList(growable: false);
  }

  String? _extractAjaxFragment(String response) {
    final rootStart = RegExp(
      r'<root(?:\s[^>]*)?>',
      caseSensitive: false,
    ).firstMatch(response);
    final rootEnd = RegExp(
      r'</root\s*>',
      caseSensitive: false,
    ).firstMatch(response);
    if (rootStart == null || rootEnd == null || rootEnd.start < rootStart.end) {
      return null;
    }
    final rootBody = response.substring(rootStart.end, rootEnd.start);
    final start = rootBody.indexOf('<![CDATA[');
    if (start < 0) {
      return null;
    }
    final contentStart = start + '<![CDATA['.length;
    final end = rootBody.indexOf(']]>', contentStart);
    if (end < 0) {
      return null;
    }
    return rootBody.substring(contentStart, end);
  }

  String _normalizeScore(String value) {
    final match = RegExp(r'[+-]?\s*\d+').firstMatch(value);
    return match?.group(0)?.replaceAll(' ', '') ?? value;
  }

  String _sumScoreText(List<ThreadPostRating> ratings) {
    var hasScore = false;
    var total = 0;
    for (final rating in ratings) {
      final match = RegExp(r'[+-]?\s*\d+').firstMatch(rating.score);
      final score = int.tryParse(match?.group(0)?.replaceAll(' ', '') ?? '');
      if (score == null) {
        continue;
      }
      hasScore = true;
      total += score;
    }
    if (!hasScore) {
      return '';
    }
    final signed = total > 0 ? '+$total' : total.toString();
    return '积分 $signed 点';
  }

  String _cleanText(String source) {
    return source
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

final class DiscuzThreadPostRatingsRepository
    implements ThreadPostRatingsRepository {
  DiscuzThreadPostRatingsRepository({
    required YamiboHttpGateway gateway,
    ThreadPostRatingsHtmlParser parser = const ThreadPostRatingsHtmlParser(),
  }) : _gateway = gateway,
       _parser = parser;

  final YamiboHttpGateway _gateway;
  final ThreadPostRatingsHtmlParser _parser;

  @override
  Future<ApiResult<ThreadPostRatingDetails>> loadAll(String viewAllUrl) async {
    final endpoint = _validatedEndpoint(viewAllUrl);
    if (endpoint == null) {
      return const ApiFailure<ThreadPostRatingDetails>(
        ApiError(type: ApiErrorType.business, message: '完整评分地址无效'),
      );
    }

    final response = await _gateway.getText(
      endpoint,
      context: const YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: 'thread.post.ratings',
        pageKind: 'thread.detail',
      ),
      headers: <String, String>{
        'User-Agent': DiscuzImageRequestHeaderBuilder.browserUserAgent,
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
        'Referer': _threadReferer(endpoint).toString(),
      },
    );
    if (response case ApiFailure(:final error)) {
      return ApiFailure<ThreadPostRatingDetails>(error);
    }

    try {
      return ApiSuccess<ThreadPostRatingDetails>(
        _parser.parse(response.dataOrNull?.body ?? ''),
      );
    } on ThreadPostRatingsParseException catch (error) {
      return ApiFailure<ThreadPostRatingDetails>(
        ApiError(type: ApiErrorType.parse, message: error.message),
      );
    } catch (error) {
      return ApiFailure<ThreadPostRatingDetails>(
        ApiError(type: ApiErrorType.parse, message: '完整评分解析失败：$error'),
      );
    }
  }

  Uri? _validatedEndpoint(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null) {
      return null;
    }
    final site = Uri.parse(AppConfig.siteBaseUrl);
    final endpoint = parsed.hasScheme ? parsed : site.resolveUri(parsed);
    final path = endpoint.path.toLowerCase();
    final query = endpoint.queryParameters;
    if (endpoint.scheme != 'https' ||
        endpoint.host.toLowerCase() != site.host.toLowerCase() ||
        (path != '/forum.php' && path != '/misc.php') ||
        query['mod']?.toLowerCase() != 'misc' ||
        query['action']?.toLowerCase() != 'viewratings' ||
        !_isPositiveId(query['tid']) ||
        !_isPositiveId(query['pid'])) {
      return null;
    }
    return site.replace(
      path: '/forum.php',
      queryParameters: <String, String>{
        'mod': 'misc',
        'action': 'viewratings',
        'tid': query['tid']!,
        'pid': query['pid']!,
        'infloat': 'yes',
        'handlekey': 'viewratings',
        'inajax': '1',
        'ajaxtarget': 'fwin_content_viewratings',
      },
    );
  }

  Uri _threadReferer(Uri endpoint) {
    return Uri.parse(AppConfig.siteBaseUrl).replace(
      path: '/forum.php',
      queryParameters: <String, String>{
        'mod': 'viewthread',
        'tid': endpoint.queryParameters['tid']!,
        'mobile': '2',
      },
    );
  }

  bool _isPositiveId(String? value) {
    final parsed = int.tryParse(value ?? '');
    return parsed != null && parsed > 0;
  }
}

final class ThreadPostRatingsParseException implements Exception {
  const ThreadPostRatingsParseException(this.message);

  final String message;
}

final class _ThreadPostRatingDraft {
  _ThreadPostRatingDraft({
    required this.userName,
    required this.score,
    required this.dateline,
    this.reason = '',
  });

  final String userName;
  final String score;
  final String dateline;
  String reason;
}

final threadPostRatingsRepositoryProvider =
    Provider<ThreadPostRatingsRepository>(
      (ref) => DiscuzThreadPostRatingsRepository(
        gateway: ref.watch(yamiboHttpGatewayProvider),
      ),
    );

final class _ThreadPostRatingHeader {
  const _ThreadPostRatingHeader({
    required this.scoreIndex,
    required this.userIndex,
    required this.datelineIndex,
    required this.reasonIndex,
    required this.row,
  });

  final int scoreIndex;
  final int userIndex;
  final int datelineIndex;
  final int reasonIndex;
  final html_dom.Element row;
}
