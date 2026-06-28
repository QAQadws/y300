import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/core/utils/parse_utils.dart';

class ThreadPollVoteRequest {
  const ThreadPollVoteRequest({
    required this.tid,
    required this.actionUrl,
    required this.formHash,
    required this.optionIds,
  });

  final String tid;
  final String actionUrl;
  final String formHash;
  final List<String> optionIds;
}

class ThreadPollVoteResult {
  const ThreadPollVoteResult({required this.message});

  final String message;
}

abstract class ThreadPollVoteRepository {
  Future<ApiResult<ThreadPollVoteResult>> vote(ThreadPollVoteRequest request);
}

class DiscuzThreadPollVoteRepository implements ThreadPollVoteRepository {
  DiscuzThreadPollVoteRepository({
    required YamiboHttpGateway gateway,
    SiteUrlResolver urlResolver = const SiteUrlResolver(),
  }) : _gateway = gateway,
       _urlResolver = urlResolver;

  final YamiboHttpGateway _gateway;
  final SiteUrlResolver _urlResolver;

  @override
  Future<ApiResult<ThreadPollVoteResult>> vote(
    ThreadPollVoteRequest request,
  ) async {
    final actionUrl = request.actionUrl.trim();
    final formHash = request.formHash.trim();
    final optionIds = _normalizeOptionIds(request.optionIds);
    if (actionUrl.isEmpty) {
      return const ApiFailure<ThreadPollVoteResult>(
        ApiError(type: ApiErrorType.business, message: '投票提交地址缺失'),
      );
    }
    if (formHash.isEmpty) {
      return const ApiFailure<ThreadPollVoteResult>(
        ApiError(type: ApiErrorType.business, message: '投票 formhash 缺失'),
      );
    }
    if (optionIds.isEmpty) {
      return const ApiFailure<ThreadPollVoteResult>(
        ApiError(type: ApiErrorType.business, message: '请选择投票选项'),
      );
    }

    final endpointText = _urlResolver.resolve(actionUrl);
    final endpoint = endpointText == null ? null : Uri.tryParse(endpointText);
    if (endpoint == null) {
      return const ApiFailure<ThreadPollVoteResult>(
        ApiError(type: ApiErrorType.business, message: '投票提交地址无效'),
      );
    }

    final response = await _gateway.postFormFields(
      endpoint,
      context: const YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: 'thread.poll.vote',
        pageKind: 'thread.detail',
      ),
      data: <MapEntry<String, String>>[
        MapEntry<String, String>('formhash', formHash),
        for (final optionId in optionIds)
          MapEntry<String, String>('pollanswers[]', optionId),
      ],
      headers: <String, String>{
        'referer':
            '${AppConfig.siteBaseUrl}/forum.php?mod=viewthread&tid=${request.tid}',
        'accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      },
    );
    if (response case ApiFailure(:final error)) {
      return ApiFailure<ThreadPollVoteResult>(error);
    }

    final body = response.dataOrNull?.body ?? '';
    final parsed = _parseSubmitResponse(body);
    if (!parsed.success) {
      return ApiFailure<ThreadPollVoteResult>(
        ApiError(
          type: ApiErrorType.business,
          message: parsed.message,
          code: parsed.code,
          raw: body,
          statusCode: response.dataOrNull?.statusCode,
        ),
      );
    }
    return ApiSuccess<ThreadPollVoteResult>(
      ThreadPollVoteResult(message: parsed.message),
    );
  }

  List<String> _normalizeOptionIds(Iterable<String> optionIds) {
    final seen = <String>{};
    final normalized = <String>[];
    for (final optionId in optionIds) {
      final trimmed = optionId.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) {
        continue;
      }
      normalized.add(trimmed);
    }
    return normalized;
  }

  _ThreadPollVoteParseResult _parseSubmitResponse(String body) {
    final json = _tryDecodeJson(body);
    if (json != null) {
      final messageNode = ParseUtils.asMap(json['Message']);
      final code = ParseUtils.asString(messageNode['messageval']);
      final message = ParseUtils.asString(
        messageNode['messagestr'],
        fallback: ParseUtils.asString(
          messageNode['messageval'],
          fallback: '投票结果未知',
        ),
      );
      return _ThreadPollVoteParseResult(
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
      return const _ThreadPollVoteParseResult(
        success: true,
        message: '投票已提交',
        code: '',
      );
    }
    return _ThreadPollVoteParseResult(
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
        loweredCode == 'thread_poll_succeed' ||
        loweredMessage.contains('成功') ||
        loweredMessage.contains('投票成功') ||
        loweredMessage.contains('感谢您的参与');
  }

  String _cleanText(String source) {
    return source
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

final threadPollVoteRepositoryProvider = Provider<ThreadPollVoteRepository>((
  ref,
) {
  return DiscuzThreadPollVoteRepository(
    gateway: ref.watch(yamiboHttpGatewayProvider),
  );
});

class _ThreadPollVoteParseResult {
  const _ThreadPollVoteParseResult({
    required this.success,
    required this.message,
    required this.code,
  });

  final bool success;
  final String message;
  final String code;
}
