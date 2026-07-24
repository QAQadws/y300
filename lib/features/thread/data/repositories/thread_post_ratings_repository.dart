import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/yamibo/yamibo_html_client.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

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

  ThreadPostRatingDetails parse(String html) {
    final document = html_parser.parse(_extractCData(html) ?? html);
    final drafts = _parseMobileDrafts(document);
    if (drafts.isEmpty) {
      drafts.addAll(_parseDesktopDrafts(document));
    }
    if (drafts.isEmpty) {
      throw ThreadPostRatingsParseException(_missingListMessage(document));
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

  List<_ThreadPostRatingDraft> _parseMobileDrafts(html_dom.Document document) {
    final list = document.querySelector('ul.post_box');
    if (list == null) {
      return <_ThreadPostRatingDraft>[];
    }
    final drafts = <_ThreadPostRatingDraft>[];
    for (final row in list.querySelectorAll('li.flex-box.mli')) {
      final cells = row.children
          .where((element) => element.localName == 'div')
          .toList(growable: false);
      if (cells.length >= 3) {
        final score = _cleanText(cells[0].text);
        final userName = _cleanText(cells[1].text);
        final dateline = _cleanText(cells[2].text);
        if (_isColumnHeader(score, userName, dateline)) {
          continue;
        }
        if (score.isEmpty || userName.isEmpty) {
          continue;
        }
        drafts.add(
          _ThreadPostRatingDraft(
            userName: userName,
            score: _normalizeScore(score),
            dateline: dateline,
          ),
        );
        continue;
      }

      if (cells.length == 1 && drafts.isNotEmpty) {
        final reason = _cleanText(cells.first.text);
        if (reason.isNotEmpty) {
          drafts.last.reason = reason;
        }
      }
    }
    return drafts;
  }

  List<_ThreadPostRatingDraft> _parseDesktopDrafts(html_dom.Document document) {
    for (final table in document.querySelectorAll('table')) {
      final drafts = <_ThreadPostRatingDraft>[];
      var scoreIndex = -1;
      var userIndex = -1;
      var datelineIndex = -1;
      var reasonIndex = -1;
      for (final row in table.querySelectorAll('tr')) {
        final cells = row.children
            .where(
              (element) =>
                  element.localName == 'th' || element.localName == 'td',
            )
            .toList(growable: false);
        if (cells.isEmpty) {
          continue;
        }
        final texts = cells
            .map((cell) => _cleanText(cell.text))
            .toList(growable: false);
        if (scoreIndex < 0) {
          scoreIndex = texts.indexWhere((text) => text == '积分');
          userIndex = texts.indexWhere((text) => text.contains('用户名'));
          datelineIndex = texts.indexWhere((text) => text.contains('时间'));
          reasonIndex = texts.indexWhere((text) => text.contains('理由'));
          if (scoreIndex < 0 || userIndex < 0 || datelineIndex < 0) {
            scoreIndex = -1;
            userIndex = -1;
            datelineIndex = -1;
          }
          continue;
        }
        final requiredLastIndex = <int>[
          scoreIndex,
          userIndex,
          datelineIndex,
        ].reduce((left, right) => left > right ? left : right);
        if (cells.length <= requiredLastIndex) {
          continue;
        }
        final score = _cleanText(cells[scoreIndex].text);
        final userName = _cleanText(cells[userIndex].text);
        if (score.isEmpty || userName.isEmpty) {
          continue;
        }
        drafts.add(
          _ThreadPostRatingDraft(
            userName: userName,
            score: _normalizeScore(score),
            dateline: _cleanText(cells[datelineIndex].text),
            reason: reasonIndex >= 0 && cells.length > reasonIndex
                ? _cleanText(cells[reasonIndex].text)
                : '',
          ),
        );
      }
      if (drafts.isNotEmpty) {
        return drafts;
      }
    }
    return <_ThreadPostRatingDraft>[];
  }

  String _missingListMessage(html_dom.Document document) {
    final prompt = document.querySelector(
      '.alert_error, .alert_info, #messagetext p, .showmessage',
    );
    final promptText = _cleanText(prompt?.text ?? '');
    if (promptText.isNotEmpty) {
      return promptText;
    }
    final title = _cleanText(document.querySelector('title')?.text ?? '');
    final hasLoginForm =
        document.querySelector('form[action*="logging"]') != null ||
        title.contains('登录');
    if (hasLoginForm) {
      return '登录状态失效，请重新登录后查看完整评分';
    }
    return '完整评分列表缺失';
  }

  String? _extractCData(String html) {
    final start = html.indexOf('<![CDATA[');
    if (start < 0) {
      return null;
    }
    final contentStart = start + '<![CDATA['.length;
    final end = html.indexOf(']]>', contentStart);
    if (end < 0) {
      return null;
    }
    return html.substring(contentStart, end);
  }

  bool _isColumnHeader(String score, String userName, String dateline) {
    return score == '积分' && userName.contains('用户名') && dateline.contains('时间');
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
    required YamiboHtmlClient htmlClient,
    ThreadPostRatingsHtmlParser parser = const ThreadPostRatingsHtmlParser(),
  }) : _htmlClient = htmlClient,
       _parser = parser;

  final YamiboHtmlClient _htmlClient;
  final ThreadPostRatingsHtmlParser _parser;

  @override
  Future<ApiResult<ThreadPostRatingDetails>> loadAll(String viewAllUrl) async {
    final endpoint = _validatedEndpoint(viewAllUrl);
    if (endpoint == null) {
      return const ApiFailure<ThreadPostRatingDetails>(
        ApiError(type: ApiErrorType.business, message: '完整评分地址无效'),
      );
    }

    final response = await _htmlClient.getMobilePage(
      path: endpoint.path,
      queryParameters: endpoint.queryParameters,
      context: const YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: 'thread.post.ratings',
        pageKind: 'thread.detail',
      ),
      referer: Uri.parse(AppConfig.siteBaseUrl).replace(
        path: '/forum.php',
        queryParameters: <String, String>{
          'mod': 'viewthread',
          'tid': endpoint.queryParameters['tid']!,
          'mobile': '2',
        },
      ),
    );
    if (response case ApiFailure(:final error)) {
      return ApiFailure<ThreadPostRatingDetails>(error);
    }

    try {
      return ApiSuccess<ThreadPostRatingDetails>(
        _parser.parse(response.dataOrNull ?? ''),
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
    return endpoint.replace(
      queryParameters: <String, String>{...query, 'mobile': '2'},
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
        htmlClient: ref.watch(yamiboHtmlClientProvider),
      ),
    );
