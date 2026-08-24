import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/browser_user_agents.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/core/network/yamibo/yamibo_session_store.dart';
import 'package:y300/core/utils/parse_utils.dart';

enum ThreadPostRateReasonOrigin { serverForm, applicationFallback }

class ThreadPostRateForm {
  const ThreadPostRateForm({
    required this.actionUrl,
    required this.formHash,
    required this.tid,
    required this.pid,
    required this.referer,
    required this.scoreName,
    required this.scoreMin,
    required this.scoreMax,
    required this.todayRemaining,
    required this.reasonOptions,
    required this.notifyAuthorDefault,
    this.reasonOrigin = ThreadPostRateReasonOrigin.serverForm,
  });

  final String actionUrl;
  final String formHash;
  final String tid;
  final String pid;
  final String referer;
  final String scoreName;
  final int scoreMin;
  final int scoreMax;
  final int todayRemaining;
  final List<String> reasonOptions;
  final bool notifyAuthorDefault;
  final ThreadPostRateReasonOrigin reasonOrigin;

  int get defaultScore {
    if (scoreMax > 0) {
      return scoreMax.clamp(scoreMin, scoreMax).toInt();
    }
    return scoreMin;
  }
}

class ThreadPostRateDraft {
  const ThreadPostRateDraft({
    required this.form,
    required this.score,
    required this.reason,
    required this.notifyAuthor,
  });

  final ThreadPostRateForm form;
  final int score;
  final String reason;
  final bool notifyAuthor;
}

class ThreadPostRateResult {
  const ThreadPostRateResult({required this.message});

  final String message;
}

class ThreadPostRateFormSeed {
  const ThreadPostRateFormSeed({
    required this.rateUrl,
    required this.tid,
    required this.pid,
    required this.referer,
  });

  final String rateUrl;
  final String tid;
  final String pid;
  final String referer;
}

abstract class ThreadPostRateRepository {
  Future<ApiResult<ThreadPostRateForm>> loadForm(String rateUrl);

  Future<ApiResult<ThreadPostRateForm>> loadFormFromSeed(
    ThreadPostRateFormSeed seed,
  );

  Future<ApiResult<ThreadPostRateResult>> submit(ThreadPostRateDraft draft);
}

class ThreadPostRateFormFallbackBuilder {
  const ThreadPostRateFormFallbackBuilder({
    SiteUrlResolver urlResolver = const SiteUrlResolver(),
  }) : _urlResolver = urlResolver;

  final SiteUrlResolver _urlResolver;

  static const List<String> defaultReasonOptions = <String>[
    '你太可爱',
    '好萌好萌好萌',
    '我很赞同',
    '精品文章',
    '原创内容',
  ];

  ThreadPostRateForm? build({
    required ThreadPostRateFormSeed seed,
    required String? formHash,
  }) {
    final endpoint = _resolveUri(seed.rateUrl);
    if (endpoint == null) {
      return null;
    }
    final tid = _firstNonEmpty(seed.tid, endpoint.queryParameters['tid']);
    final pid = _firstNonEmpty(seed.pid, endpoint.queryParameters['pid']);
    final normalizedFormHash = formHash?.trim() ?? '';
    if (tid.isEmpty || pid.isEmpty || normalizedFormHash.isEmpty) {
      return null;
    }
    final referer = _firstNonEmpty(
      seed.referer,
      '${AppConfig.siteBaseUrl}/forum.php?mod=viewthread&tid=$tid#pid$pid',
    );
    return ThreadPostRateForm(
      actionUrl: Uri.parse(AppConfig.siteBaseUrl)
          .replace(
            path: '/forum.php',
            queryParameters: const <String, String>{
              'mod': 'misc',
              'action': 'rate',
              'ratesubmit': 'yes',
              'infloat': 'yes',
              'inajax': '1',
              'handlekey': 'rateform',
            },
          )
          .toString(),
      formHash: normalizedFormHash,
      tid: tid,
      pid: pid,
      referer: referer,
      scoreName: 'score1',
      scoreMin: 0,
      scoreMax: 5,
      todayRemaining: 0,
      reasonOptions: defaultReasonOptions,
      notifyAuthorDefault: false,
      reasonOrigin: ThreadPostRateReasonOrigin.applicationFallback,
    );
  }

  Uri? _resolveUri(String value) {
    final resolved = _urlResolver.resolve(value.trim());
    return resolved == null ? null : Uri.tryParse(resolved);
  }

  String _firstNonEmpty(String? first, String? second) {
    final firstValue = first?.trim();
    if (firstValue != null && firstValue.isNotEmpty) {
      return firstValue;
    }
    return second?.trim() ?? '';
  }
}

class ThreadPostRateFormParser {
  const ThreadPostRateFormParser({
    SiteUrlResolver urlResolver = const SiteUrlResolver(),
  }) : _urlResolver = urlResolver;

  final SiteUrlResolver _urlResolver;

  ThreadPostRateForm parse(String html, {required String fallbackRateUrl}) {
    final document = html_parser.parse(_extractCData(html) ?? html);
    final form = document.querySelector('form#rateform');
    if (form == null) {
      throw const ThreadPostRateFormParseException('评分表单缺失');
    }
    final actionUrl = _resolve(form.attributes['action']) ?? fallbackRateUrl;
    final formHash = _valueOf(form, 'formhash');
    final tid = _valueOf(form, 'tid');
    final pid = _valueOf(form, 'pid');
    final referer = _valueOf(form, 'referer');
    final scoreInput =
        form.querySelector('input[name^="score"]') ??
        form.querySelector('input[id^="score"]');
    final scoreName = scoreInput?.attributes['name']?.trim() ?? 'score1';
    final scoreRow = scoreInput?.parent?.parent;
    final scoreCells =
        scoreRow?.querySelectorAll('td') ?? const <html_dom.Element>[];
    final rangeText = scoreCells.length > 2
        ? _cleanText(scoreCells[2].text)
        : '';
    final remainingText = scoreCells.length > 3
        ? _cleanText(scoreCells[3].text)
        : '';
    final range = _parseScoreRange(rangeText);
    final reasonOptions = form
        .querySelectorAll('#reasonselect li')
        .map((node) => _cleanText(node.text))
        .where((value) => value.isNotEmpty)
        .toList(growable: false);

    if (actionUrl.trim().isEmpty ||
        formHash.isEmpty ||
        tid.isEmpty ||
        pid.isEmpty) {
      throw const ThreadPostRateFormParseException('评分表单关键字段缺失');
    }

    return ThreadPostRateForm(
      actionUrl: actionUrl,
      formHash: formHash,
      tid: tid,
      pid: pid,
      referer: referer,
      scoreName: scoreName,
      scoreMin: range.$1,
      scoreMax: range.$2,
      todayRemaining: int.tryParse(remainingText) ?? 0,
      reasonOptions: reasonOptions,
      notifyAuthorDefault:
          form.querySelector('input[name="sendreasonpm"][checked]') != null,
    );
  }

  String _valueOf(html_dom.Element form, String name) {
    return form.querySelector('[name="$name"]')?.attributes['value']?.trim() ??
        '';
  }

  (int, int) _parseScoreRange(String text) {
    final match = RegExp(r'(-?\d+)\s*~\s*(-?\d+)').firstMatch(text);
    final min = int.tryParse(match?.group(1) ?? '') ?? 0;
    final max = int.tryParse(match?.group(2) ?? '') ?? min;
    return (min, max);
  }

  String? _resolve(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return _urlResolver.resolve(value);
  }

  String _cleanText(String source) {
    return source
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
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
}

class DiscuzThreadPostRateRepository implements ThreadPostRateRepository {
  DiscuzThreadPostRateRepository({
    required YamiboHttpGateway gateway,
    required YamiboSessionStore sessionStore,
    ThreadPostRateFormParser parser = const ThreadPostRateFormParser(),
    ThreadPostRateFormFallbackBuilder fallbackBuilder =
        const ThreadPostRateFormFallbackBuilder(),
    SiteUrlResolver urlResolver = const SiteUrlResolver(),
  }) : _gateway = gateway,
       _sessionStore = sessionStore,
       _parser = parser,
       _fallbackBuilder = fallbackBuilder,
       _urlResolver = urlResolver;

  final YamiboHttpGateway _gateway;
  final YamiboSessionStore _sessionStore;
  final ThreadPostRateFormParser _parser;
  final ThreadPostRateFormFallbackBuilder _fallbackBuilder;
  final SiteUrlResolver _urlResolver;

  @override
  Future<ApiResult<ThreadPostRateForm>> loadForm(String rateUrl) async {
    final endpoint = _uriFrom(rateUrl);
    final tid = endpoint?.queryParameters['tid'] ?? '';
    final pid = endpoint?.queryParameters['pid'] ?? '';
    return _loadForm(
      ThreadPostRateFormSeed(rateUrl: rateUrl, tid: tid, pid: pid, referer: ''),
      endpoint: _rateFormUri(endpoint: endpoint, tid: tid, pid: pid),
    );
  }

  @override
  Future<ApiResult<ThreadPostRateForm>> loadFormFromSeed(
    ThreadPostRateFormSeed seed,
  ) async {
    return _loadForm(
      seed,
      endpoint: _rateFormUri(
        endpoint: _uriFrom(seed.rateUrl),
        tid: seed.tid,
        pid: seed.pid,
      ),
    );
  }

  Future<ApiResult<ThreadPostRateForm>> _loadForm(
    ThreadPostRateFormSeed seed, {
    required Uri? endpoint,
  }) async {
    if (endpoint == null) {
      return const ApiFailure<ThreadPostRateForm>(
        ApiError(type: ApiErrorType.business, message: '评分表单地址无效'),
      );
    }
    final response = await _gateway.getText(
      endpoint,
      context: const YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: 'thread.post.rate.form',
        pageKind: 'thread.detail',
      ),
      headers: const <String, String>{
        'User-Agent': BrowserUserAgents.desktop,
        'accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      },
    );
    if (response case ApiFailure(:final error)) {
      final fallback = _buildFallback(seed);
      if (fallback != null) {
        return ApiSuccess<ThreadPostRateForm>(fallback);
      }
      return ApiFailure<ThreadPostRateForm>(error);
    }
    try {
      return ApiSuccess<ThreadPostRateForm>(
        _parser.parse(
          response.dataOrNull?.body ?? '',
          fallbackRateUrl: _rateSubmitUri().toString(),
        ),
      );
    } on ThreadPostRateFormParseException catch (error) {
      final fallback = _buildFallback(seed);
      if (fallback != null) {
        return ApiSuccess<ThreadPostRateForm>(fallback);
      }
      return ApiFailure<ThreadPostRateForm>(
        ApiError(type: ApiErrorType.parse, message: error.message),
      );
    } catch (error) {
      final fallback = _buildFallback(seed);
      if (fallback != null) {
        return ApiSuccess<ThreadPostRateForm>(fallback);
      }
      return ApiFailure<ThreadPostRateForm>(
        ApiError(type: ApiErrorType.parse, message: '评分表单解析失败：$error'),
      );
    }
  }

  ThreadPostRateForm? _buildFallback(ThreadPostRateFormSeed seed) {
    return _fallbackBuilder.build(
      seed: seed,
      formHash: _sessionStore.readFreshFormhash(),
    );
  }

  @override
  Future<ApiResult<ThreadPostRateResult>> submit(
    ThreadPostRateDraft draft,
  ) async {
    final form = draft.form;
    final reason = draft.reason.trim();
    if (reason.isEmpty) {
      return const ApiFailure<ThreadPostRateResult>(
        ApiError(type: ApiErrorType.business, message: '请输入评分理由'),
      );
    }
    if (draft.score < form.scoreMin || draft.score > form.scoreMax) {
      return ApiFailure<ThreadPostRateResult>(
        ApiError(
          type: ApiErrorType.business,
          message: '评分应在 ${form.scoreMin}~${form.scoreMax} 之间',
        ),
      );
    }
    final endpoint = _rateSubmitUri();
    final response = await _gateway.postFormFields(
      endpoint,
      context: const YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: 'thread.post.rate.submit',
        pageKind: 'thread.detail',
      ),
      data: <MapEntry<String, String>>[
        MapEntry<String, String>('formhash', form.formHash),
        MapEntry<String, String>('tid', form.tid),
        MapEntry<String, String>('pid', form.pid),
        if (form.referer.trim().isNotEmpty)
          MapEntry<String, String>('referer', form.referer),
        const MapEntry<String, String>('handlekey', 'rate'),
        MapEntry<String, String>(form.scoreName, draft.score.toString()),
        MapEntry<String, String>('reason', reason),
        if (draft.notifyAuthor)
          const MapEntry<String, String>('sendreasonpm', 'on'),
        const MapEntry<String, String>('ratesubmit', 'true'),
      ],
      headers: <String, String>{
        'referer': form.referer.trim().isEmpty
            ? '${AppConfig.siteBaseUrl}/forum.php?mod=viewthread&tid=${form.tid}'
            : form.referer,
        'accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      },
    );
    if (response case ApiFailure(:final error)) {
      return ApiFailure<ThreadPostRateResult>(error);
    }
    final body = response.dataOrNull?.body ?? '';
    final parsed = _parseSubmitResponse(body);
    if (!parsed.success) {
      return ApiFailure<ThreadPostRateResult>(
        ApiError(
          type: ApiErrorType.business,
          message: parsed.message,
          code: parsed.code,
          raw: body,
          statusCode: response.dataOrNull?.statusCode,
        ),
      );
    }
    return ApiSuccess<ThreadPostRateResult>(
      ThreadPostRateResult(message: parsed.message),
    );
  }

  Uri? _uriFrom(String value) {
    final resolved = _urlResolver.resolve(value.trim());
    return resolved == null ? null : Uri.tryParse(resolved);
  }

  Uri? _rateFormUri({
    required Uri? endpoint,
    required String tid,
    required String pid,
  }) {
    if (endpoint == null) {
      return null;
    }
    final resolvedTid = tid.trim().isNotEmpty
        ? tid.trim()
        : endpoint.queryParameters['tid']?.trim() ?? '';
    final resolvedPid = pid.trim().isNotEmpty
        ? pid.trim()
        : endpoint.queryParameters['pid']?.trim() ?? '';
    if (resolvedTid.isEmpty || resolvedPid.isEmpty) {
      return endpoint;
    }
    return Uri.parse(AppConfig.siteBaseUrl).replace(
      path: '/forum.php',
      queryParameters: <String, String>{
        'mod': 'misc',
        'action': 'rate',
        'tid': resolvedTid,
        'pid': resolvedPid,
        'infloat': 'yes',
        'handlekey': 'rate',
        'inajax': '1',
      },
    );
  }

  Uri _rateSubmitUri() {
    return Uri.parse(AppConfig.siteBaseUrl).replace(
      path: '/forum.php',
      queryParameters: const <String, String>{
        'mod': 'misc',
        'action': 'rate',
        'ratesubmit': 'yes',
        'infloat': 'yes',
        'inajax': '1',
        'handlekey': 'rateform',
      },
    );
  }

  _ThreadPostRateParseResult _parseSubmitResponse(String body) {
    final html = _extractCData(body) ?? body;
    final json = _tryDecodeJson(body);
    if (json != null) {
      final messageNode = ParseUtils.asMap(json['Message']);
      final code = ParseUtils.asString(messageNode['messageval']);
      final message = ParseUtils.asString(
        messageNode['messagestr'],
        fallback: ParseUtils.asString(
          messageNode['messageval'],
          fallback: '评分结果未知',
        ),
      );
      return _ThreadPostRateParseResult(
        success: _isSuccess(code: code, message: message),
        message: message,
        code: code,
      );
    }
    final document = html_parser.parse(html);
    final message = _cleanText(
      document.querySelector('#messagetext p')?.text ??
          document.querySelector('.alert_info')?.text ??
          document.querySelector('.showmessage')?.text ??
          document.body?.text ??
          '',
    );
    if (message.isEmpty) {
      return const _ThreadPostRateParseResult(
        success: true,
        message: '评分成功',
        code: '',
      );
    }
    return _ThreadPostRateParseResult(
      success: _isSuccess(code: '', message: message),
      message: message,
      code: '',
    );
  }

  Map<String, dynamic>? _tryDecodeJson(String body) {
    final text = body.trimLeft();
    if (!text.startsWith('{')) {
      return null;
    }
    try {
      final decoded = jsonDecode(text);
      return ParseUtils.asMap(decoded);
    } catch (_) {
      return null;
    }
  }

  bool _isSuccess({required String code, required String message}) {
    final loweredCode = code.toLowerCase();
    final loweredMessage = message.toLowerCase();
    return loweredCode.contains('succeed') ||
        loweredCode.contains('success') ||
        loweredMessage.contains('成功') ||
        loweredMessage.contains('感谢');
  }

  String _cleanText(String source) {
    return source
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
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
}

class ThreadPostRateFormParseException implements Exception {
  const ThreadPostRateFormParseException(this.message);

  final String message;
}

final threadPostRateRepositoryProvider = Provider<ThreadPostRateRepository>((
  ref,
) {
  return DiscuzThreadPostRateRepository(
    gateway: ref.watch(yamiboHttpGatewayProvider),
    sessionStore: ref.watch(yamiboSessionStoreProvider),
  );
});

class _ThreadPostRateParseResult {
  const _ThreadPostRateParseResult({
    required this.success,
    required this.message,
    required this.code,
  });

  final bool success;
  final String message;
  final String code;
}
