import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/core/utils/parse_utils.dart';

class ThreadPostCommentForm {
  const ThreadPostCommentForm({
    required this.actionUrl,
    required this.formHash,
    required this.handleKey,
    required this.tid,
    required this.pid,
    required this.referer,
    required this.maxLength,
  });

  final String actionUrl;
  final String formHash;
  final String handleKey;
  final String tid;
  final String pid;
  final String referer;
  final int maxLength;
}

class ThreadPostCommentDraft {
  const ThreadPostCommentDraft({required this.form, required this.message});

  final ThreadPostCommentForm form;
  final String message;
}

class ThreadPostCommentResult {
  const ThreadPostCommentResult({required this.message});

  final String message;
}

class ThreadPostCommentFormSeed {
  const ThreadPostCommentFormSeed({
    required this.commentUrl,
    required this.tid,
    required this.pid,
    required this.page,
  });

  final String commentUrl;
  final String tid;
  final String pid;
  final int page;
}

abstract class ThreadPostCommentRepository {
  Future<ApiResult<ThreadPostCommentForm>> loadForm(String commentUrl);

  Future<ApiResult<ThreadPostCommentForm>> loadFormFromSeed(
    ThreadPostCommentFormSeed seed,
  );

  Future<ApiResult<ThreadPostCommentResult>> submit(
    ThreadPostCommentDraft draft,
  );
}

class ThreadPostCommentFormParser {
  const ThreadPostCommentFormParser({
    SiteUrlResolver urlResolver = const SiteUrlResolver(),
  }) : _urlResolver = urlResolver;

  final SiteUrlResolver _urlResolver;

  ThreadPostCommentForm parse(
    String html, {
    required String fallbackCommentUrl,
  }) {
    final document = html_parser.parse(_extractCData(html) ?? html);
    final form = document.querySelector('form#commentform');
    if (form == null) {
      final prompt = _promptMessage(document);
      throw ThreadPostCommentFormParseException(
        prompt.isEmpty ? '点评表单缺失' : prompt,
      );
    }

    final actionUrl = _resolve(form.attributes['action']) ?? fallbackCommentUrl;
    final actionUri = Uri.tryParse(actionUrl);
    final fallbackUri = Uri.tryParse(
      _urlResolver.resolve(fallbackCommentUrl) ?? fallbackCommentUrl,
    );
    final tid =
        actionUri?.queryParameters['tid'] ??
        fallbackUri?.queryParameters['tid'] ??
        '';
    final pid =
        actionUri?.queryParameters['pid'] ??
        fallbackUri?.queryParameters['pid'] ??
        '';
    final formHash = _valueOf(form, 'formhash');
    final handleKey = _valueOf(form, 'handlekey');
    final maxLength =
        int.tryParse(
          _cleanText(document.querySelector('#checklen')?.text ?? ''),
        ) ??
        200;

    if (actionUrl.trim().isEmpty ||
        formHash.isEmpty ||
        tid.isEmpty ||
        pid.isEmpty) {
      throw const ThreadPostCommentFormParseException('点评表单关键字段缺失');
    }

    return ThreadPostCommentForm(
      actionUrl: actionUrl,
      formHash: formHash,
      handleKey: handleKey.isEmpty ? 'comment' : handleKey,
      tid: tid,
      pid: pid,
      referer: '${AppConfig.siteBaseUrl}/forum.php?mod=viewthread&tid=$tid',
      maxLength: maxLength,
    );
  }

  String _valueOf(html_dom.Element form, String name) {
    return form.querySelector('[name="$name"]')?.attributes['value']?.trim() ??
        '';
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

  String _promptMessage(html_dom.Document document) {
    final prompt =
        document.querySelector('.alert_error') ??
        document.querySelector('.alert_info') ??
        document.querySelector('#messagetext p') ??
        document.querySelector('.showmessage');
    if (prompt == null) {
      return '';
    }
    final cleanPrompt = prompt.clone(true);
    cleanPrompt.querySelectorAll('script').forEach((node) => node.remove());
    return _cleanText(cleanPrompt.text);
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

class DiscuzThreadPostCommentRepository implements ThreadPostCommentRepository {
  DiscuzThreadPostCommentRepository({
    required YamiboHttpGateway gateway,
    ThreadPostCommentFormParser parser = const ThreadPostCommentFormParser(),
    SiteUrlResolver urlResolver = const SiteUrlResolver(),
  }) : _gateway = gateway,
       _parser = parser,
       _urlResolver = urlResolver;

  final YamiboHttpGateway _gateway;
  final ThreadPostCommentFormParser _parser;
  final SiteUrlResolver _urlResolver;

  @override
  Future<ApiResult<ThreadPostCommentForm>> loadForm(String commentUrl) async {
    return _loadForm(
      endpoint: _commentFormUri(endpoint: _uriFrom(commentUrl)),
      fallbackCommentUrl: commentUrl,
    );
  }

  @override
  Future<ApiResult<ThreadPostCommentForm>> loadFormFromSeed(
    ThreadPostCommentFormSeed seed,
  ) async {
    final endpoint = _commentFormUri(
      endpoint: _uriFrom(seed.commentUrl),
      tid: seed.tid,
      pid: seed.pid,
      page: seed.page,
    );
    return _loadForm(
      endpoint: endpoint,
      fallbackCommentUrl: endpoint?.toString() ?? seed.commentUrl,
    );
  }

  Future<ApiResult<ThreadPostCommentForm>> _loadForm({
    required Uri? endpoint,
    required String fallbackCommentUrl,
  }) async {
    if (endpoint == null) {
      return const ApiFailure<ThreadPostCommentForm>(
        ApiError(type: ApiErrorType.business, message: '点评表单地址无效'),
      );
    }
    final response = await _gateway.getText(
      endpoint,
      context: const YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: 'thread.post.comment.form',
        pageKind: 'thread.detail',
      ),
      headers: const <String, String>{
        'User-Agent': DiscuzImageRequestHeaderBuilder.browserUserAgent,
        'accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      },
    );
    if (response case ApiFailure(:final error)) {
      return ApiFailure<ThreadPostCommentForm>(error);
    }
    try {
      return ApiSuccess<ThreadPostCommentForm>(
        _parser.parse(
          response.dataOrNull?.body ?? '',
          fallbackCommentUrl: fallbackCommentUrl,
        ),
      );
    } on ThreadPostCommentFormParseException catch (error) {
      return ApiFailure<ThreadPostCommentForm>(
        ApiError(type: ApiErrorType.parse, message: error.message),
      );
    } catch (error) {
      return ApiFailure<ThreadPostCommentForm>(
        ApiError(type: ApiErrorType.parse, message: '点评表单解析失败：$error'),
      );
    }
  }

  @override
  Future<ApiResult<ThreadPostCommentResult>> submit(
    ThreadPostCommentDraft draft,
  ) async {
    final form = draft.form;
    final message = draft.message.trim();
    if (message.isEmpty) {
      return const ApiFailure<ThreadPostCommentResult>(
        ApiError(type: ApiErrorType.business, message: '请输入点评内容'),
      );
    }
    if (form.maxLength > 0 && message.length > form.maxLength) {
      return ApiFailure<ThreadPostCommentResult>(
        ApiError(
          type: ApiErrorType.business,
          message: '点评最多 ${form.maxLength} 个字符',
        ),
      );
    }
    final endpoint = _uriFrom(form.actionUrl);
    if (endpoint == null) {
      return const ApiFailure<ThreadPostCommentResult>(
        ApiError(type: ApiErrorType.business, message: '点评提交地址无效'),
      );
    }

    final response = await _gateway.postFormFields(
      endpoint,
      context: const YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: 'thread.post.comment.submit',
        pageKind: 'thread.detail',
      ),
      data: <MapEntry<String, String>>[
        MapEntry<String, String>('formhash', form.formHash),
        MapEntry<String, String>('handlekey', form.handleKey),
        MapEntry<String, String>('message', message),
        const MapEntry<String, String>('commentsubmit', 'true'),
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
      return ApiFailure<ThreadPostCommentResult>(error);
    }

    final body = response.dataOrNull?.body ?? '';
    final parsed = _parseSubmitResponse(body);
    if (!parsed.success) {
      return ApiFailure<ThreadPostCommentResult>(
        ApiError(
          type: ApiErrorType.business,
          message: parsed.message,
          code: parsed.code,
          raw: body,
          statusCode: response.dataOrNull?.statusCode,
        ),
      );
    }
    return ApiSuccess<ThreadPostCommentResult>(
      ThreadPostCommentResult(message: parsed.message),
    );
  }

  Uri? _uriFrom(String value) {
    final resolved = _urlResolver.resolve(value.trim());
    return resolved == null ? null : Uri.tryParse(resolved);
  }

  Uri? _commentFormUri({
    required Uri? endpoint,
    String? tid,
    String? pid,
    int? page,
  }) {
    final resolvedTid = _firstNonEmpty(tid, endpoint?.queryParameters['tid']);
    final resolvedPid = _firstNonEmpty(pid, endpoint?.queryParameters['pid']);
    if (resolvedTid.isEmpty || resolvedPid.isEmpty) {
      return endpoint;
    }
    final resolvedPage = _resolvePage(page, endpoint);
    return Uri.parse(AppConfig.siteBaseUrl).replace(
      path: '/forum.php',
      queryParameters: <String, String>{
        'mod': 'misc',
        'action': 'comment',
        'tid': resolvedTid,
        'pid': resolvedPid,
        'extra': '',
        'page': resolvedPage.toString(),
        'infloat': 'yes',
        'handlekey': 'comment',
        'inajax': '1',
        'ajaxtarget': 'fwin_content_comment',
      },
    );
  }

  int _resolvePage(int? page, Uri? endpoint) {
    final seedPage = page == null || page <= 0 ? null : page;
    if (seedPage != null) {
      return seedPage;
    }
    return int.tryParse(endpoint?.queryParameters['page'] ?? '') ?? 1;
  }

  String _firstNonEmpty(String? first, String? second) {
    final firstValue = first?.trim();
    if (firstValue != null && firstValue.isNotEmpty) {
      return firstValue;
    }
    return second?.trim() ?? '';
  }

  _ThreadPostCommentParseResult _parseSubmitResponse(String body) {
    final json = _tryDecodeJson(body);
    if (json != null) {
      final messageNode = ParseUtils.asMap(json['Message']);
      final code = ParseUtils.asString(messageNode['messageval']);
      final message = ParseUtils.asString(
        messageNode['messagestr'],
        fallback: ParseUtils.asString(
          messageNode['messageval'],
          fallback: '点评结果未知',
        ),
      );
      return _ThreadPostCommentParseResult(
        success: _isSuccess(code: code, message: message),
        message: message,
        code: code,
      );
    }
    final document = html_parser.parse(body);
    final message = _cleanText(
      document.querySelector('#messagetext p')?.text ??
          document.querySelector('.alert_info')?.text ??
          document.querySelector('.showmessage')?.text ??
          document.body?.text ??
          '',
    );
    if (message.isEmpty) {
      return const _ThreadPostCommentParseResult(
        success: true,
        message: '点评成功',
        code: '',
      );
    }
    return _ThreadPostCommentParseResult(
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
        loweredCode == 'comment_add_succeed' ||
        loweredMessage.contains('成功') ||
        loweredMessage.contains('点评成功') ||
        loweredMessage.contains('发布成功');
  }

  String _cleanText(String source) {
    return source
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

class ThreadPostCommentFormParseException implements Exception {
  const ThreadPostCommentFormParseException(this.message);

  final String message;
}

final threadPostCommentRepositoryProvider =
    Provider<ThreadPostCommentRepository>((ref) {
      return DiscuzThreadPostCommentRepository(
        gateway: ref.watch(yamiboHttpGatewayProvider),
      );
    });

class _ThreadPostCommentParseResult {
  const _ThreadPostCommentParseResult({
    required this.success,
    required this.message,
    required this.code,
  });

  final bool success;
  final String message;
  final String code;
}
