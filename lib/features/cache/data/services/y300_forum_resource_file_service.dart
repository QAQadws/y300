import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

class Y300ForumResourceFileService extends FileService {
  Y300ForumResourceFileService({
    required ForumResourceClient client,
    required Uri siteOrigin,
  }) : _client = client,
       _resolver = ForumResourceReferenceResolver(siteOrigin: siteOrigin);

  final ForumResourceClient _client;
  final ForumResourceReferenceResolver _resolver;

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final refererValue = _header(headers, 'referer');
    final referer = refererValue == null ? null : Uri.tryParse(refererValue);
    final reference = _resolver.resolve(url, referer: referer);
    if (reference == null) {
      throw const ForumResourceFileServiceException(
        ForumResourceFailure(
          kind: ForumResourceFailureKind.invalidReference,
          code: 'invalid_resource_reference',
        ),
      );
    }
    final result = await _client.open(
      ForumResourceRequest(
        reference: reference,
        ifNoneMatch: _header(headers, 'if-none-match'),
      ),
    );
    return switch (result) {
      ForumResourceSuccess success => _ForumResourceFileServiceResponse(
        success,
      ),
      ForumResourceError(:final failure) =>
        throw ForumResourceFileServiceException(failure),
    };
  }

  String? _header(Map<String, String>? headers, String name) {
    if (headers == null) return null;
    final expected = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == expected) {
        final value = entry.value.trim();
        return value.isEmpty ? null : value;
      }
    }
    return null;
  }
}

class ForumResourceFileServiceException implements Exception {
  const ForumResourceFileServiceException(this.failure);

  final ForumResourceFailure failure;

  @override
  String toString() => 'ForumResourceFileServiceException(${failure.code})';
}

class _ForumResourceFileServiceResponse implements FileServiceResponse {
  const _ForumResourceFileServiceResponse(this._response);

  final ForumResourceSuccess _response;

  @override
  Stream<List<int>> get content => _response.content;

  @override
  int? get contentLength => _response.contentLength;

  @override
  int get statusCode => _response.statusCode;

  @override
  DateTime get validTill => _response.validUntil;

  @override
  String? get eTag => _response.eTag;

  @override
  String get fileExtension => _response.fileExtension;
}
