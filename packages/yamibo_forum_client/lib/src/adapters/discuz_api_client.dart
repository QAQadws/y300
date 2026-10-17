// ignore_for_file: public_member_api_docs

import 'dart:convert';

import '../client/forum_client_config.dart';
import '../network/forum_network.dart';
import '../network/forum_request.dart';
import '../network/forum_request_profile.dart';
import '../network/forum_response.dart';
import '../network/forum_transport.dart';
import '../parsing/discuz_message_attention_identity.dart';
import '../session/forum_session_store.dart';

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
    this.sessionStore,
  });

  final ForumClientConfig config;
  final ForumClientNetwork network;
  final ForumRequestProfileResolver requestProfiles;
  final ForumSessionStore? sessionStore;

  Future<ForumTransportResult<ForumResponse<DiscuzApiEnvelope>>> get({
    required String module,
    Map<String, Object?> queryParameters = const {},
    bool treatMessageAsBusinessError = true,
    ForumRequestCancellation? cancellation,
    ForumRequestContext? requestContext,
    String? expectedUserId,
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
        context:
            requestContext ??
            ForumRequestContext(operation: module, module: module),
        headers: requestProfiles
            .resolve(ForumRequestProfileKind.discuzApi)
            .headers,
        responseType: ForumResponseType.json,
        cancellation: cancellation,
      ),
    );
    final ForumTransportResult<ForumResponse<DiscuzApiEnvelope>> decoded =
        switch (response) {
          ForumTransportError<ForumResponse<Object?>>(:final failure) =>
            ForumTransportError<ForumResponse<DiscuzApiEnvelope>>(failure),
          ForumTransportSuccess<ForumResponse<Object?>>(:final response) =>
            _decode(
              response,
              treatMessageAsBusinessError: treatMessageAsBusinessError,
              expectedSource: expectedUserId == null ? null : uri,
            ),
        };
    if (decoded case ForumTransportSuccess<ForumResponse<DiscuzApiEnvelope>>(
      :final response,
    )) {
      if (expectedUserId != null && (cancellation?.isCancelled ?? false)) {
        return const ForumTransportError(
          ForumTransportFailure(
            kind: ForumTransportFailureKind.cancelled,
            code: 'request_cancelled',
          ),
        );
      }
      if (expectedUserId != null &&
          discuzMessageAttentionIdentity(
                response.body.variables['member_uid'],
              ) !=
              expectedUserId) {
        return ForumTransportError(
          ForumTransportFailure(
            kind: ForumTransportFailureKind.unauthorized,
            code: 'message_viewer_mismatch',
            statusCode: response.statusCode,
          ),
        );
      }
      await _mergeSession(response.body.variables, source: 'api:$module');
    }
    return decoded;
  }

  Future<ForumTransportResult<ForumResponse<DiscuzApiEnvelope>>> postForm({
    required String module,
    required Map<String, String> form,
    Map<String, Object?> queryParameters = const <String, Object?>{},
    bool treatMessageAsBusinessError = true,
    Uri? referer,
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
    final profile = requestProfiles.resolve(
      ForumRequestProfileKind.discuzApi,
      referer: referer,
    );
    final response = await network.send(
      ForumRequest(
        method: ForumRequestMethod.post,
        uri: uri,
        context: ForumRequestContext(operation: module, module: module),
        headers: <String, String>{
          ...profile.headers,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: form,
        responseType: ForumResponseType.json,
        cancellation: cancellation,
      ),
    );
    final ForumTransportResult<ForumResponse<DiscuzApiEnvelope>> decoded =
        switch (response) {
          ForumTransportError<ForumResponse<Object?>>(:final failure) =>
            ForumTransportError<ForumResponse<DiscuzApiEnvelope>>(failure),
          ForumTransportSuccess<ForumResponse<Object?>>(:final response) =>
            _decode(
              response,
              treatMessageAsBusinessError: treatMessageAsBusinessError,
            ),
        };
    if (decoded case ForumTransportSuccess<ForumResponse<DiscuzApiEnvelope>>(
      :final response,
    )) {
      await _mergeSession(response.body.variables, source: 'api:$module');
    }
    return decoded;
  }

  /// Posts ordered form fields while preserving duplicate names.
  Future<ForumTransportResult<ForumResponse<DiscuzApiEnvelope>>>
  postFormFields({
    required String module,
    required ForumFormFields form,
    Map<String, Object?> queryParameters = const <String, Object?>{},
    bool treatMessageAsBusinessError = true,
    Uri? referer,
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
    final profile = requestProfiles.resolve(
      ForumRequestProfileKind.discuzApi,
      referer: referer,
    );
    final result = await network.send(
      ForumRequest(
        method: ForumRequestMethod.post,
        uri: uri,
        context: ForumRequestContext(operation: module, module: module),
        headers: <String, String>{
          ...profile.headers,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: form,
        responseType: ForumResponseType.json,
        cancellation: cancellation,
      ),
    );
    final decoded = switch (result) {
      ForumTransportError<ForumResponse<Object?>>(:final failure) =>
        ForumTransportError<ForumResponse<DiscuzApiEnvelope>>(failure),
      ForumTransportSuccess<ForumResponse<Object?>>(:final response) => _decode(
        response,
        treatMessageAsBusinessError: treatMessageAsBusinessError,
      ),
    };
    if (decoded case ForumTransportSuccess<ForumResponse<DiscuzApiEnvelope>>(
      :final response,
    )) {
      await _mergeSession(response.body.variables, source: 'api:$module');
    }
    return decoded;
  }

  Future<void> _mergeSession(
    Map<String, Object?> variables, {
    required String source,
  }) async {
    final store = sessionStore;
    if (store == null) return;
    final rawSpace = variables['space'];
    final space = rawSpace is Map
        ? <String, Object?>{
            for (final entry in rawSpace.entries)
              entry.key.toString(): entry.value,
          }
        : const <String, Object?>{};
    final userId = _firstNonEmpty(<Object?>[
      variables['member_uid'],
      space['uid'],
    ]);
    final username = _firstNonEmpty(<Object?>[
      variables['member_username'],
      space['username'],
    ]);
    final formhash = variables['formhash']?.toString().trim() ?? '';
    final auth = variables['auth']?.toString().trim() ?? '';
    if (userId.isEmpty &&
        username.isEmpty &&
        formhash.isEmpty &&
        auth.isEmpty) {
      return;
    }
    final now = DateTime.now();
    try {
      await store.merge(
        ForumSessionSnapshot(
          isLoggedIn: (userId.isNotEmpty && userId != '0') || auth.isNotEmpty,
          userId: userId,
          username: username,
          formhash: formhash,
          updatedAt: now,
          source: source,
          formhashUpdatedAt: formhash.isEmpty ? null : now,
        ),
      );
    } on Object {
      // Session data is a reproducible projection. A Host persistence failure
      // must not turn an otherwise valid forum response into a read failure.
    }
  }

  String _firstNonEmpty(Iterable<Object?> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  ForumTransportResult<ForumResponse<DiscuzApiEnvelope>> _decode(
    ForumResponse<Object?> response, {
    required bool treatMessageAsBusinessError,
    Uri? expectedSource,
  }) {
    try {
      final root = _jsonMap(response.body);
      // Opt-in message reads must prove the actual consuming response before
      // merging any session values. Other API compatibility paths stay intact.
      if (expectedSource != null &&
          (!_matchesExpectedReadSource(response, expectedSource) ||
              switch (root['Version']) {
                String value =>
                  value != expectedSource.queryParameters['version'],
                int value =>
                  value.toString() != expectedSource.queryParameters['version'],
                _ => true,
              })) {
        return ForumTransportError(
          ForumTransportFailure(
            kind: ForumTransportFailureKind.parse,
            code: 'message_response_unverified',
            statusCode: response.statusCode,
          ),
        );
      }
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

  bool _matchesExpectedReadSource(
    ForumResponse<Object?> response,
    Uri expected,
  ) {
    final status = response.statusCode;
    final uri = response.uri;
    final origin = config.siteOrigin;
    if (status == null ||
        status < 200 ||
        status >= 300 ||
        !const {'http', 'https'}.contains(origin.scheme) ||
        origin.host.isEmpty ||
        origin.userInfo.isNotEmpty ||
        uri.scheme != origin.scheme ||
        uri.host.toLowerCase() != origin.host.toLowerCase() ||
        uri.port != origin.port ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.path != '/api/mobile/index.php') {
      return false;
    }
    try {
      final actual = uri.queryParametersAll;
      final wanted = expected.queryParametersAll;
      return actual.length == wanted.length &&
          wanted.entries.every((entry) {
            final values = actual[entry.key];
            return values != null &&
                values.length == 1 &&
                entry.value.length == 1 &&
                values.single == entry.value.single;
          });
    } on FormatException {
      return false;
    }
  }
}
