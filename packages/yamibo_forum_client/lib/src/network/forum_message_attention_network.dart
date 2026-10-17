import 'dart:convert';

import '../adapters/discuz_message_attention_api_parser.dart';
import '../adapters/discuz_message_attention_html_parser.dart';
import '../contracts/forum_message_attention.dart';
import '../contracts/forum_resource.dart';
import '../parsing/discuz_html_document.dart';
import '../parsing/discuz_message_attention_source.dart';
import 'forum_multipart.dart';
import 'forum_network.dart';
import 'forum_request.dart';
import 'forum_response.dart';
import 'forum_transport.dart';

/// Adds passive observation while retaining the underlying transport's ports.
///
/// With no observer, the original transport is returned unchanged. Recovery,
/// retries, cookies, and streams remain entirely owned by that transport.
ForumClientNetwork createForumMessageAttentionNetwork({
  required ForumClientNetwork network,
  required Uri siteOrigin,
  required ForumMessageAttentionObserver? observer,
}) {
  if (observer == null) return network;
  final observing = _MessageAttentionNetwork(network, siteOrigin, observer);
  final resources = network is ForumResourceClient
      ? network as ForumResourceClient
      : null;
  final multipart = network is ForumMultipartClient
      ? network as ForumMultipartClient
      : null;
  if (resources != null && multipart != null) {
    return _MessageAttentionFullNetwork(observing, resources, multipart);
  }
  if (resources != null) {
    return _MessageAttentionResourceNetwork(observing, resources);
  }
  if (multipart != null) {
    return _MessageAttentionMultipartNetwork(observing, multipart);
  }
  return observing;
}

final class _MessageAttentionNetwork implements ForumClientNetwork {
  _MessageAttentionNetwork(this._network, this._siteOrigin, this._observer)
    : _html = DiscuzMessageAttentionHtmlParser(siteOrigin: _siteOrigin),
      _api = DiscuzMessageAttentionApiParser(siteOrigin: _siteOrigin);

  final ForumClientNetwork _network;
  final Uri _siteOrigin;
  final ForumMessageAttentionObserver _observer;
  final DiscuzMessageAttentionHtmlParser _html;
  final DiscuzMessageAttentionApiParser _api;

  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    ForumMessageAttentionRequestContext? context;
    try {
      if (_eligibleRequest(request)) context = _observer.captureRequest();
    } on Object {
      // Optional host state must not prevent the business request from running.
    }
    // Await the existing transport once. Its return is already after any
    // verified WAF replay; no intermediate challenge is ever sampled here.
    final result = await _network.send(request);
    if (context == null ||
        (request.cancellation?.isCancelled ?? false) ||
        result is! ForumTransportSuccess<ForumResponse<Object?>>) {
      return result;
    }
    final response = result.response;
    final status = response.statusCode;
    if (status == null || status < 200 || status >= 300) return result;
    try {
      final observation = switch (request.responseType) {
        ForumResponseType.text when response.body is String =>
          _html.parseDocument(
            DiscuzHtmlDocument.forResponse(response),
            sourceUri: response.uri,
            expectedUserId: context.viewerUserId,
          ),
        ForumResponseType.json => _api.parse(
          _decodedJson(response.body),
          sourceUri: response.uri,
          expectedUserId: context.viewerUserId,
        ),
        _ => null,
      };
      if (observation != null &&
          !(request.cancellation?.isCancelled ?? false)) {
        _observer.onObservation(observation, context: context);
      }
    } on Object {
      // Parsing and host delivery are best effort. Keep the exact successful
      // result/body for the source adapter; never expose observation errors.
    }
    return result;
  }

  bool _eligibleRequest(ForumRequest request) {
    if (request.method != ForumRequestMethod.get ||
        request.body != null ||
        const {
          'authentication',
          'formhash',
          'message.attention.probe',
        }.contains(request.context.pageKind) ||
        (request.cancellation?.isCancelled ?? false)) {
      return false;
    }
    return switch (request.responseType) {
      ForumResponseType.text => acceptsDiscuzMessageAttentionHtmlSource(
        request.uri,
        siteOrigin: _siteOrigin,
      ),
      ForumResponseType.json => acceptsDiscuzMessageAttentionApiSource(
        request.uri,
        siteOrigin: _siteOrigin,
      ),
      ForumResponseType.bytes => false,
    };
  }

  Object? _decodedJson(Object? body) {
    if (body is! String) return body;
    var text = body.trimLeft();
    // Match the existing API decoder's accepted BOM forms without changing
    // the response body or replacing the business decoder.
    while (text.startsWith('\uFEFF') || text.startsWith('ï»¿')) {
      text = text.startsWith('\uFEFF')
          ? text.substring(1).trimLeft()
          : text.substring(3).trimLeft();
    }
    return jsonDecode(text);
  }
}

abstract base class _DelegatingMessageAttentionNetwork
    implements ForumClientNetwork {
  _DelegatingMessageAttentionNetwork(this._observing);

  final _MessageAttentionNetwork _observing;

  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) => _observing.send(request);
}

final class _MessageAttentionResourceNetwork
    extends _DelegatingMessageAttentionNetwork
    implements ForumResourceClient {
  _MessageAttentionResourceNetwork(super.observing, this._resources);

  final ForumResourceClient _resources;

  @override
  Future<ForumResourceResult> open(ForumResourceRequest request) =>
      _resources.open(request);
}

final class _MessageAttentionMultipartNetwork
    extends _DelegatingMessageAttentionNetwork
    implements ForumMultipartClient {
  _MessageAttentionMultipartNetwork(super.observing, this._multipart);

  final ForumMultipartClient _multipart;

  @override
  Future<ForumTransportResult<ForumMultipartResponse>> sendMultipart(
    ForumMultipartRequest request,
  ) => _multipart.sendMultipart(request);
}

final class _MessageAttentionFullNetwork
    extends _DelegatingMessageAttentionNetwork
    implements ForumResourceClient, ForumMultipartClient {
  _MessageAttentionFullNetwork(
    super.observing,
    this._resources,
    this._multipart,
  );

  final ForumResourceClient _resources;
  final ForumMultipartClient _multipart;

  @override
  Future<ForumResourceResult> open(ForumResourceRequest request) =>
      _resources.open(request);

  @override
  Future<ForumTransportResult<ForumMultipartResponse>> sendMultipart(
    ForumMultipartRequest request,
  ) => _multipart.sendMultipart(request);
}
