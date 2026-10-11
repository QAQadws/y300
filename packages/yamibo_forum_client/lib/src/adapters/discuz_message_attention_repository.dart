import 'dart:convert';

import '../client/forum_client_config.dart';
import '../contracts/data_read_contract.dart';
import '../contracts/forum_message_attention.dart';
import '../network/forum_network.dart';
import '../network/forum_request.dart';
import '../network/forum_request_profile.dart';
import '../network/forum_response.dart';
import '../network/forum_transport.dart';
import '../parsing/discuz_message_attention_identity.dart';
import '../parsing/discuz_message_attention_source.dart';
import 'discuz_message_attention_api_parser.dart';

/// Reads Discuz's non-consuming `forumindex checknotice=1` arrival variables.
///
/// This uses the existing Host transport and never reads `mypm`, `mynotelist`,
/// or `checknewpm`. The caller owns cancellation and calibration policy.
final class DiscuzMessageAttentionRepository
    implements ForumMessageAttentionRepository {
  /// Creates the source around existing request and transport ports.
  DiscuzMessageAttentionRepository({
    required this.config,
    required this.network,
    required this.requestProfiles,
  }) : _parser = DiscuzMessageAttentionApiParser(siteOrigin: config.siteOrigin);

  /// Forum and API origins shared with the other client sources.
  final ForumClientConfig config;

  /// The existing Host transport, including its session and WAF behavior.
  final ForumClientNetwork network;

  /// The client's established Discuz API request identity.
  final ForumRequestProfileResolver requestProfiles;
  final DiscuzMessageAttentionApiParser _parser;

  @override
  ForumMessageAttentionSourceCapabilities get capabilities =>
      ForumMessageAttentionSourceCapabilities(
        values: DataCapabilitySet.supported(
          ForumMessageAttentionCapability.values,
        ),
      );

  @override
  Future<
    DataReadResult<
      ForumMessageAttentionObservation,
      ForumMessageAttentionReadCapabilities
    >
  >
  load(ForumMessageAttentionQuery query) async {
    if (discuzMessageAttentionIdentity(query.expectedUserId) == null) {
      return _failure(
        DataReadFailureKind.business,
        'message_attention_viewer_invalid',
      );
    }
    if (query.cancellation?.isCancelled ?? false) return _cancelled();
    final apiOrigin = config.apiOrigin;
    if (apiOrigin == null) {
      return _failure(
        DataReadFailureKind.unsupported,
        'message_attention_api_unavailable',
      );
    }
    final uri = apiOrigin.replace(
      queryParameters: const {
        'module': 'forumindex',
        'version': '1',
        'checknotice': '1',
      },
    );
    if (!_isProbeSource(uri)) {
      return _failure(
        DataReadFailureKind.unsupported,
        'message_attention_api_unavailable',
      );
    }
    final result = await network.send(
      ForumRequest(
        method: ForumRequestMethod.get,
        uri: uri,
        context: const ForumRequestContext(
          operation: 'message.attention.probe',
          pageKind: 'message.attention.probe',
          module: 'forumindex',
          silent: true,
        ),
        headers: requestProfiles
            .resolve(ForumRequestProfileKind.discuzApi)
            .headers,
        responseType: ForumResponseType.json,
        cancellation: query.cancellation,
      ),
    );
    if (query.cancellation?.isCancelled ?? false) return _cancelled();
    if (result case ForumTransportError<ForumResponse<Object?>>(
      :final failure,
    )) {
      return _failure(
        toReadFailureKind(failure.kind),
        'message_attention_probe_transport_failed',
        statusCode: failure.statusCode,
      );
    }
    final response =
        (result as ForumTransportSuccess<ForumResponse<Object?>>).response;
    final status = response.statusCode;
    if (status == null || status < 200 || status >= 300) {
      return _failure(
        status == 401 || status == 403
            ? DataReadFailureKind.unauthorized
            : DataReadFailureKind.server,
        'message_attention_probe_status_invalid',
        statusCode: status,
      );
    }
    if (!_isProbeSource(response.uri)) {
      return _failure(
        DataReadFailureKind.parse,
        'message_attention_probe_source_invalid',
      );
    }
    try {
      final decoded = _decode(response.body);
      if (decoded is! Map<Object?, Object?> ||
          switch (decoded['Version']) {
            String value => value != '1',
            int value => value != 1,
            _ => true,
          }) {
        return _failure(
          DataReadFailureKind.parse,
          'message_attention_probe_unverified',
        );
      }
      final observation = _parser.parse(
        decoded,
        sourceUri: response.uri,
        expectedUserId: query.expectedUserId,
      );
      if (observation == null) {
        return _failure(
          DataReadFailureKind.parse,
          'message_attention_probe_unverified',
        );
      }
      return DataReadSuccess(
        data: observation,
        capabilities: ForumMessageAttentionReadCapabilities(
          values: DataCapabilitySet({
            ForumMessageAttentionCapability.viewerIdentity:
                DataCapabilitySupport.supported,
            if (observation.privateMessages !=
                ForumMessageAttentionState.unknown)
              ForumMessageAttentionCapability.privateMessageArrival:
                  DataCapabilitySupport.supported,
            if (observation.notifications != ForumMessageAttentionState.unknown)
              ForumMessageAttentionCapability.notificationArrival:
                  DataCapabilitySupport.supported,
            if (observation.notificationCount != null)
              ForumMessageAttentionCapability.notificationCount:
                  DataCapabilitySupport.supported,
          }),
        ),
        metadata: const DataReadMetadata.network(),
      );
    } on FormatException {
      return _failure(
        DataReadFailureKind.parse,
        'message_attention_probe_unverified',
      );
    }
  }

  bool _isProbeSource(Uri uri) {
    if (!acceptsDiscuzMessageAttentionApiSource(
      uri,
      siteOrigin: config.siteOrigin,
    )) {
      return false;
    }
    // A redirect to another ordinary read is not proof of this explicit probe.
    final query = uri.queryParameters;
    return query.length == 3 &&
        query['module'] == 'forumindex' &&
        query['version'] == '1' &&
        query['checknotice'] == '1';
  }

  Object? _decode(Object? body) {
    if (body is! String) return body;
    var text = body.trimLeft();
    while (text.startsWith('\uFEFF') || text.startsWith('ï»¿')) {
      text = text.startsWith('\uFEFF')
          ? text.substring(1).trimLeft()
          : text.substring(3).trimLeft();
    }
    return jsonDecode(text);
  }

  DataReadFailure<
    ForumMessageAttentionObservation,
    ForumMessageAttentionReadCapabilities
  >
  _cancelled() => _failure(DataReadFailureKind.cancelled, 'request_cancelled');

  DataReadFailure<
    ForumMessageAttentionObservation,
    ForumMessageAttentionReadCapabilities
  >
  _failure(DataReadFailureKind kind, String code, {int? statusCode}) =>
      DataReadFailure(
        kind: kind,
        code: code,
        diagnosticMessage: code,
        statusCode: statusCode,
      );
}
