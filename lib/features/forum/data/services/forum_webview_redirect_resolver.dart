import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';

final forumWebViewRedirectResolverProvider =
    Provider<ForumWebViewRedirectResolver>((ref) {
      return ForumWebViewRedirectResolver(
        gateway: ref.read(yamiboHttpGatewayProvider),
      );
    });

class ForumWebViewRedirectResolution {
  const ForumWebViewRedirectResolution({required this.finalUri});

  final Uri finalUri;
}

class ForumWebViewRedirectResolver {
  const ForumWebViewRedirectResolver({required YamiboHttpGateway gateway})
    : _gateway = gateway;

  final YamiboHttpGateway _gateway;

  Future<ApiResult<ForumWebViewRedirectResolution>> resolve(
    Uri sourceUri,
  ) async {
    final result = await _gateway.getText(
      sourceUri,
      context: const YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: 'forum.webview.redirect.resolve',
        pageKind: 'thread.detail',
        silent: true,
      ),
      followRedirects: true,
      validateStatus: (status) =>
          status != null && status >= 200 && status < 400,
    );
    return result.when(
      success: (response) =>
          ApiSuccess(ForumWebViewRedirectResolution(finalUri: response.uri)),
      failure: ApiFailure.new,
    );
  }
}
