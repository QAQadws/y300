import 'dart:convert';

import '../client/forum_client_config.dart';
import '../network/forum_network.dart';
import '../network/forum_request.dart';
import '../network/forum_request_profile.dart';
import '../network/forum_response.dart';
import '../network/forum_transport.dart';

final class DiscuzApiEnvelope {
  const DiscuzApiEnvelope({
    required this.variables,
    this.version = '',
    this.charset = '',
    this.message,
  });

  final Map<String, Object?> variables;
  final String version;
  final String charset;
  final Map<String, Object?>? message;
}

final class DiscuzApiClient {
  const DiscuzApiClient({
    required this.config,
    required this.network,
    required this.requestProfiles,
  });

  final ForumClientConfig config;
  final ForumClientNetwork network;
  final ForumRequestProfileResolver requestProfiles;

  Future<ForumTransportResult<ForumResponse<DiscuzApiEnvelope>>> get({
    required String module,
    Map<String, Object?> queryParameters = const {},
    bool treatMessageAsBusinessError = true,
    ForumRequestCancellation? cancellation,
  }) async {
    final apiOrigin = config.apiOrigin;
    if (apiOrigin == null) {
      return const ForumTransportError(
        ForumTransportFailure(
          kind: ForumTransportFailureKind.business,
          code: 'api_origin_unavailable',
        ),
      );
    }
    final uri = apiOrigin.replace(
      queryParameters: <String, String>{
        'module': module,
        ...{
          for (final entry in queryParameters.entries)
            entry.key: entry.value.toString(),
        },
        if (!queryParameters.containsKey('version')) 'version': '4',
      },
    );
    final response = await network.send(
      ForumRequest(
        method: ForumRequestMethod.get,
        uri: uri,
        context: ForumRequestContext(operation: module, module: module),
        headers: requestProfiles
            .resolve(ForumRequestProfileKind.discuzApi)
            .headers,
        responseType: ForumResponseType.json,
        cancellation: cancellation,
      ),
    );
    return switch (response) {
      ForumTransportError<ForumResponse<Object?>>(:final failure) =>
        ForumTransportError(failure),
      ForumTransportSuccess<ForumResponse<Object?>>(:final response) => _decode(
        response,
        treatMessageAsBusinessError: treatMessageAsBusinessError,
      ),
    };
  }

  ForumTransportResult<ForumResponse<DiscuzApiEnvelope>> _decode(
    ForumResponse<Object?> response, {
    required bool treatMessageAsBusinessError,
  }) {
    try {
      final root = _jsonMap(response.body);
      final variables = _map(root['Variables']);
      final message = root['Message'] == null ? null : _map(root['Message']);
      if (treatMessageAsBusinessError &&
          message != null &&
          message.isNotEmpty) {
        final code = _text(message['messageval']);
        return ForumTransportError(
          ForumTransportFailure(
            kind: ForumTransportFailureKind.business,
            code: code.isEmpty ? 'discuz_business_error' : code,
            statusCode: response.statusCode,
          ),
        );
      }
      return ForumTransportSuccess(
        ForumResponse<DiscuzApiEnvelope>(
          uri: response.uri,
          statusCode: response.statusCode,
          headers: response.headers,
          body: DiscuzApiEnvelope(
            variables: variables,
            version: _text(root['Version']),
            charset: _text(root['Charset']),
            message: message?.isEmpty == true ? null : message,
          ),
        ),
      );
    } on FormatException {
      return ForumTransportError(
        ForumTransportFailure(
          kind: ForumTransportFailureKind.parse,
          code: 'discuz_response_invalid',
          statusCode: response.statusCode,
        ),
      );
    }
  }

  Map<String, Object?> _jsonMap(Object? value) {
    Object? decoded = value;
    if (value is String) {
      var text = value.trimLeft();
      while (text.startsWith('\uFEFF') || text.startsWith('ï»¿')) {
        text = text.startsWith('\uFEFF')
            ? text.substring(1).trimLeft()
            : text.substring(3).trimLeft();
      }
      decoded = jsonDecode(text);
    }
    return _map(decoded);
  }

  Map<String, Object?> _map(Object? value) {
    if (value is! Map) throw const FormatException('map_expected');
    return {
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }

  String _text(Object? value) => value?.toString().trim() ?? '';
}
