import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../client/forum_client_config.dart';
import '../contracts/data_command_contract.dart';
import '../contracts/data_read_contract.dart';
import '../contracts/forum_image_attachments.dart';
import '../contracts/forum_resource.dart';
import '../network/forum_multipart.dart';
import '../network/forum_network.dart';
import '../network/forum_request.dart';
import '../network/forum_request_profile.dart';
import '../network/forum_response.dart';
import '../network/forum_transport.dart';
import '../session/forum_formhash_provider.dart';
import '../session/forum_session_store.dart';
import 'discuz_api_client.dart';

final class DiscuzImageAttachmentUploadAdapter
    implements
        ForumImageAttachmentUploadPreparationRepository,
        ForumImageAttachmentUploadCommand {
  DiscuzImageAttachmentUploadAdapter(
    this._api,
    this._config,
    this._multipart,
    this._sessions,
    this._requestProfiles,
  );

  static const _supportedExtensions = <String>{'jpg', 'jpeg', 'png', 'gif'};

  final DiscuzApiClient _api;
  final ForumClientConfig _config;
  final ForumMultipartClient? _multipart;
  final ForumSessionStore? _sessions;
  final ForumRequestProfileResolver _requestProfiles;

  @override
  ForumImageAttachmentUploadCapabilities get capabilities =>
      ForumImageAttachmentUploadCapabilities(
        values: DataCapabilitySet.from(
          supported: _multipart == null
              ? const <ForumImageAttachmentUploadCapability>[
                  ForumImageAttachmentUploadCapability.preparation,
                ]
              : ForumImageAttachmentUploadCapability.values,
          unsupported: _multipart == null
              ? const <ForumImageAttachmentUploadCapability>[
                  ForumImageAttachmentUploadCapability.streamedUpload,
                  ForumImageAttachmentUploadCapability.progress,
                  ForumImageAttachmentUploadCapability.cancellation,
                  ForumImageAttachmentUploadCapability.preciseServerRejection,
                ]
              : const <ForumImageAttachmentUploadCapability>[],
        ),
      );

  @override
  Future<
    DataReadResult<
      ForumImageAttachmentUploadPreparation,
      ForumImageAttachmentUploadCapabilities
    >
  >
  load(ForumImageAttachmentUploadPreparationRequest request) async {
    final fid = _positiveIdentity(request.fid);
    if (fid == null) {
      return _readFailure('attachment_fid_invalid');
    }
    final expectedSessionUid = _sessions?.readCurrent()?.userId.trim() ?? '';
    final result = await _api.get(
      module: 'checkpost',
      queryParameters: <String, Object?>{'version': '1', 'fid': fid},
      treatMessageAsBusinessError: false,
      cancellation: request.cancellation,
    );
    return switch (result) {
      ForumTransportError<ForumResponse<DiscuzApiEnvelope>>(:final failure) =>
        _transportReadFailure<
          ForumImageAttachmentUploadPreparation,
          ForumImageAttachmentUploadCapabilities
        >(failure),
      ForumTransportSuccess<ForumResponse<DiscuzApiEnvelope>>(
        :final response,
      ) =>
        _parsePreparation(fid, response.body, expectedSessionUid),
    };
  }

  DataReadResult<
    ForumImageAttachmentUploadPreparation,
    ForumImageAttachmentUploadCapabilities
  >
  _parsePreparation(
    String fid,
    DiscuzApiEnvelope envelope,
    String expectedSessionUid,
  ) {
    if (envelope.version.isNotEmpty && envelope.version != '1') {
      return _readFailure('checkpost_version_mismatch');
    }
    final variables = envelope.variables;
    final allowPerm = _mapOrNull(variables['allowperm']);
    final allowUpload = _mapOrNull(allowPerm?['allowupload']);
    final attachRemain = _mapOrNull(allowPerm?['attachremain']);
    final uid = _positiveIdentity(variables['member_uid']?.toString() ?? '');
    final uploadHash = allowPerm?['uploadhash']?.toString().trim() ?? '';
    if (allowPerm == null ||
        allowUpload == null ||
        attachRemain == null ||
        uid == null ||
        uploadHash.isEmpty) {
      return _readFailure('checkpost_upload_permission_invalid');
    }
    if (expectedSessionUid.isNotEmpty && expectedSessionUid != uid) {
      return _readFailure('checkpost_session_identity_mismatch');
    }
    final rules = <ForumImageAttachmentExtensionRule>[];
    for (final entry in allowUpload.entries) {
      final extension = entry.key.trim().toLowerCase().replaceFirst('.', '');
      if (!_supportedExtensions.contains(extension)) continue;
      final rawLimit = int.tryParse(entry.value?.toString().trim() ?? '');
      if (rawLimit == null) {
        return _readFailure('checkpost_upload_limit_invalid');
      }
      if (rawLimit == -1 || rawLimit > 0) {
        rules.add(
          ForumImageAttachmentExtensionRule(
            extension: extension,
            maximumBytes: rawLimit == -1 ? null : rawLimit,
          ),
        );
      }
    }
    if (rules.isEmpty) {
      return _readFailure('checkpost_image_upload_unsupported');
    }
    final remainingBytes = _remaining(attachRemain['size']);
    final remainingCount = _remaining(attachRemain['count']);
    if (remainingBytes == _RemainingMarker.invalid ||
        remainingCount == _RemainingMarker.invalid) {
      return _readFailure('checkpost_attachment_quota_invalid');
    }
    final token = _DiscuzImageUploadToken(
      fid: fid,
      uid: uid,
      uploadHash: uploadHash,
    );
    final preparation = ForumImageAttachmentUploadPreparation(
      fid: fid,
      extensionRules: List.unmodifiable(rules),
      remainingBytes: remainingBytes == _RemainingMarker.unlimited
          ? null
          : remainingBytes as int,
      remainingCount: remainingCount == _RemainingMarker.unlimited
          ? null
          : remainingCount as int,
      token: token,
    );
    return DataReadSuccess(
      data: preparation,
      capabilities: capabilities,
      metadata: const DataReadMetadata.network(),
    );
  }

  @override
  Future<DataCommandResult<ForumImageAttachmentUploadReceipt>> execute(
    ForumImageAttachmentUploadSubmission submission,
  ) async {
    final multipart = _multipart;
    if (multipart == null) {
      return const DataCommandUnsupported();
    }
    final preparation = submission.preparation;
    final token = preparation.token;
    final fid = _positiveIdentity(preparation.fid);
    if (token is! _DiscuzImageUploadToken || fid == null || token.fid != fid) {
      return _notSent('attachment_preparation_invalid');
    }
    if (submission.cancellation?.isCancelled ?? false) {
      return _notSent('cancelled', kind: DataCommandFailureKind.cancelled);
    }
    final content = submission.content;
    final fileName = _safeFileName(content.fileName);
    if (fileName == null) {
      return _notSent('attachment_file_invalid');
    }
    final extension = _fileExtension(fileName);
    final mimeType = content.mimeType.trim().toLowerCase();
    if (extension == null ||
        !_supportedExtensions.contains(extension) ||
        !mimeType.startsWith('image/') ||
        content.contentLength <= 0) {
      return _notSent('attachment_file_invalid');
    }
    final matchingRules = preparation.extensionRules
        .where((rule) => rule.extension == extension)
        .toList(growable: false);
    if (matchingRules.length != 1) {
      return _notSent('attachment_extension_not_allowed');
    }
    final maxBytes = matchingRules.single.maximumBytes;
    if (maxBytes != null && content.contentLength > maxBytes) {
      return _notSent('attachment_extension_file_size_exceeded');
    }
    if ((preparation.remainingBytes != null &&
            content.contentLength > preparation.remainingBytes!) ||
        (preparation.remainingCount != null &&
            preparation.remainingCount! <= 0)) {
      return _notSent('attachment_quota_exceeded');
    }
    final apiOrigin = _config.apiOrigin;
    if (apiOrigin == null) {
      return const DataCommandUnsupported();
    }
    final uri = apiOrigin.replace(
      queryParameters: <String, String>{
        'module': 'forumupload',
        'version': '4',
        'fid': fid,
        'type': 'image',
        'filetype': mimeType,
      },
    );
    final result = await multipart.sendMultipart(
      ForumMultipartRequest(
        uri: uri,
        context: const ForumRequestContext(
          operation: 'attachment.upload',
          module: 'forumupload',
        ),
        headers: <String, String>{
          ..._requestProfiles
              .resolve(ForumRequestProfileKind.discuzApi)
              .headers,
          'Accept': 'text/plain, */*',
        },
        fields: <String, String>{'uid': token.uid, 'hash': token.uploadHash},
        file: ForumMultipartFile(
          fieldName: 'Filedata',
          fileName: fileName,
          contentType: mimeType,
          contentLength: content.contentLength,
          openRead: content.openRead,
        ),
        cancellation: submission.cancellation,
        onSendProgress: (sent, total) {
          if (total > 0) {
            submission.onProgress?.call((sent / total).clamp(0, 1));
          }
        },
      ),
    );
    return switch (result) {
      ForumTransportError<ForumMultipartResponse>(:final failure) =>
        _unknownAfterSend(failure),
      ForumTransportSuccess<ForumMultipartResponse>(:final response) =>
        _uploadResponse(response),
    };
  }

  DataCommandResult<ForumImageAttachmentUploadReceipt> _uploadResponse(
    ForumMultipartResponse response,
  ) {
    final status = int.tryParse(response.body.trim());
    if (status != null && status > 0) {
      return DataCommandApplied(
        ForumImageAttachmentUploadReceipt(aid: status.toString()),
      );
    }
    if (status != null && status >= -13 && status <= -1) {
      return DataCommandRejected(
        DataCommandFailure(
          kind: _uploadRejectionKind(status),
          retryPolicy: _uploadRetryPolicy(status),
          code: _uploadStatusCode(status),
          statusCode: response.statusCode,
          diagnosticMessage: _uploadStatusCode(status),
        ),
      );
    }
    return DataCommandOutcomeUnknown(
      DataCommandFailure(
        kind: DataCommandFailureKind.parse,
        retryPolicy: DataCommandRetryPolicy.explicitOnly,
        code: 'attachment_upload_response_unconfirmed',
        statusCode: response.statusCode,
        diagnosticMessage: 'attachment_upload_response_unconfirmed',
      ),
    );
  }
}

final class DiscuzUnusedImageAttachmentAdapter
    implements
        ForumUnusedImageAttachmentDirectoryRepository,
        ForumUnusedImageAttachmentDeleteCommand {
  DiscuzUnusedImageAttachmentAdapter(
    this._config,
    this._network,
    this._requestProfiles,
    this._sessions,
    this._formhash,
  );

  final ForumClientConfig _config;
  final ForumClientNetwork _network;
  final ForumRequestProfileResolver _requestProfiles;
  final ForumSessionStore? _sessions;
  final ForumFormhashProvider _formhash;

  @override
  ForumUnusedImageAttachmentCapabilities get capabilities =>
      ForumUnusedImageAttachmentCapabilities(
        values: DataCapabilitySet.supported(
          ForumUnusedImageAttachmentCapability.values,
        ),
      );

  @override
  Future<
    DataReadResult<
      ForumUnusedImageAttachmentDirectory,
      ForumUnusedImageAttachmentCapabilities
    >
  >
  load(ForumUnusedImageAttachmentDirectoryRequest request) async {
    final uri = _config.siteOrigin.replace(
      path: '/forum.php',
      queryParameters: const <String, String>{
        'mod': 'ajax',
        'action': 'imagelist',
        'posttime': '0',
      },
    );
    final result = await _network.send(
      ForumRequest(
        method: ForumRequestMethod.get,
        uri: uri,
        context: const ForumRequestContext(
          operation: 'attachment.unused.list',
          pageKind: 'attachment.unused',
        ),
        headers: _requestProfiles
            .resolve(ForumRequestProfileKind.desktopHtml)
            .headers,
        responseType: ForumResponseType.text,
        cancellation: request.cancellation,
      ),
    );
    if (result case ForumTransportError<ForumResponse<Object?>>(
      :final failure,
    )) {
      return _transportReadFailure<
        ForumUnusedImageAttachmentDirectory,
        ForumUnusedImageAttachmentCapabilities
      >(failure);
    }
    final response =
        (result as ForumTransportSuccess<ForumResponse<Object?>>).response;
    if (response.body is! String) {
      return _directoryReadFailure('unused_attachment_catalog_invalid');
    }
    try {
      final items = _parseUnusedDirectory(
        body: response.body! as String,
        sourceUri: response.uri,
        siteOrigin: _config.siteOrigin,
        authenticated: _hasAuthenticatedSession(),
      );
      return DataReadSuccess(
        data: ForumUnusedImageAttachmentDirectory(
          items: items,
          token: _DiscuzUnusedDirectoryToken(
            aids: {for (final item in items) item.aid},
          ),
        ),
        capabilities: capabilities,
        metadata: const DataReadMetadata.network(),
      );
    } on FormatException {
      return _directoryReadFailure('unused_attachment_catalog_invalid');
    }
  }

  @override
  Future<DataCommandResult<ForumImageAttachmentDeleteReceipt>> execute(
    DeleteUnusedImageAttachmentRequest request,
  ) async {
    final aid = _positiveIdentity(request.aid);
    final token = request.directoryToken;
    if (aid == null ||
        token is! _DiscuzUnusedDirectoryToken ||
        !token.aids.contains(aid)) {
      return _deleteNotSent('unused_attachment_proof_invalid');
    }
    final direct = await _deleteAttachment(
      tid: '0',
      pid: '0',
      aid: aid,
      cancellation: request.cancellation,
    );
    if (direct case DataCommandApplied<ForumImageAttachmentDeleteReceipt>()) {
      return direct;
    }
    if (direct
        case DataCommandNotSent<ForumImageAttachmentDeleteReceipt>() ||
            DataCommandRejected<ForumImageAttachmentDeleteReceipt>()) {
      return direct;
    }
    if (request.cancellation?.isCancelled ?? false) return direct;
    final readBack = await load(
      ForumUnusedImageAttachmentDirectoryRequest(
        cancellation: request.cancellation,
      ),
    );
    if (readBack case DataReadSuccess<
      ForumUnusedImageAttachmentDirectory,
      ForumUnusedImageAttachmentCapabilities
    >(
      :final data,
    )) {
      if (data.items.every((item) => item.aid != aid)) {
        return DataCommandApplied(
          ForumImageAttachmentDeleteReceipt(aid: aid, deletedCount: 0),
        );
      }
      return DataCommandRejected(
        const DataCommandFailure(
          kind: DataCommandFailureKind.unknown,
          retryPolicy: DataCommandRetryPolicy.explicitOnly,
          code: 'unused_attachment_still_present',
          diagnosticMessage: 'unused_attachment_still_present',
        ),
      );
    }
    return DataCommandOutcomeUnknown(
      _deleteUnknownFailure('unused_attachment_readback_failed'),
    );
  }

  Future<DataCommandResult<ForumImageAttachmentDeleteReceipt>>
  _deleteAttachment({
    required String tid,
    required String pid,
    required String aid,
    required ForumRequestCancellation? cancellation,
  }) async {
    if (cancellation?.isCancelled ?? false) {
      return _deleteNotSent(
        'cancelled',
        kind: DataCommandFailureKind.cancelled,
      );
    }
    final formhashResult = await _formhash.loadFormhash(
      cancellation: cancellation,
    );
    if (formhashResult case ForumFormhashError(:final failure)) {
      return DataCommandNotSent(_formhashCommandFailure(failure));
    }
    final value = (formhashResult as ForumFormhashSuccess).value.trim();
    if (value.isEmpty) {
      return _deleteNotSent(
        'formhash_missing',
        kind: DataCommandFailureKind.staleFormhash,
        retryPolicy: DataCommandRetryPolicy.afterSessionRefresh,
      );
    }
    final uri = _config.siteOrigin.replace(
      path: '/forum.php',
      queryParameters: <String, String>{
        'mod': 'ajax',
        'action': 'deleteattach',
        'inajax': 'yes',
        'formhash': value,
        'tid': tid,
        'pid': pid,
        'aids[]': aid,
      },
    );
    final result = await _network.send(
      ForumRequest(
        method: ForumRequestMethod.get,
        uri: uri,
        context: const ForumRequestContext(
          operation: 'attachment.delete',
          pageKind: 'attachment.delete',
          silent: true,
        ),
        headers: _requestProfiles
            .resolve(ForumRequestProfileKind.desktopHtml)
            .headers,
        responseType: ForumResponseType.text,
        cancellation: cancellation,
      ),
    );
    if (result case ForumTransportError<ForumResponse<Object?>>(
      :final failure,
    )) {
      return DataCommandOutcomeUnknown(_transportCommandFailure(failure));
    }
    final response =
        (result as ForumTransportSuccess<ForumResponse<Object?>>).response;
    if (!_isDeleteUri(response.uri, _config.siteOrigin)) {
      return DataCommandOutcomeUnknown(
        _deleteUnknownFailure('attachment_delete_redirected'),
      );
    }
    final count = response.body is String
        ? _extractCdataInteger(response.body! as String)
        : null;
    if (count != null && count > 0) {
      return DataCommandApplied(
        ForumImageAttachmentDeleteReceipt(aid: aid, deletedCount: count),
      );
    }
    return DataCommandOutcomeUnknown(
      _deleteUnknownFailure('attachment_delete_unconfirmed'),
    );
  }

  bool _hasAuthenticatedSession() {
    final current = _sessions?.readCurrent();
    return current?.isLoggedIn == true &&
        _positiveIdentity(current?.userId ?? '') != null;
  }
}

final class DiscuzPostImageAttachmentDeleteAdapter
    implements ForumPostImageAttachmentDeleteCommand {
  DiscuzPostImageAttachmentDeleteAdapter({
    required ForumClientConfig config,
    required ForumClientNetwork network,
    required ForumRequestProfileResolver requestProfiles,
    required ForumFormhashProvider formhash,
  }) : _delegate = DiscuzUnusedImageAttachmentAdapter(
         config,
         network,
         requestProfiles,
         null,
         formhash,
       );

  final DiscuzUnusedImageAttachmentAdapter _delegate;

  @override
  Future<DataCommandResult<ForumImageAttachmentDeleteReceipt>> execute(
    DeletePostImageAttachmentRequest request,
  ) {
    final tid = _positiveIdentity(request.tid);
    final pid = _positiveIdentity(request.pid);
    final aid = _positiveIdentity(request.aid);
    if (tid == null || pid == null || aid == null) {
      return Future.value(_deleteNotSent('post_attachment_identity_invalid'));
    }
    return _delegate._deleteAttachment(
      tid: tid,
      pid: pid,
      aid: aid,
      cancellation: request.cancellation,
    );
  }
}

final class _DiscuzImageUploadToken
    implements ForumImageAttachmentUploadPreparationToken {
  const _DiscuzImageUploadToken({
    required this.fid,
    required this.uid,
    required this.uploadHash,
  });
  final String fid;
  final String uid;
  final String uploadHash;
}

final class _DiscuzUnusedDirectoryToken
    implements ForumUnusedImageAttachmentDirectoryToken {
  const _DiscuzUnusedDirectoryToken({required this.aids});
  final Set<String> aids;
}

enum _RemainingMarker { unlimited, invalid }

Object _remaining(Object? raw) {
  final parsed = int.tryParse(raw?.toString().trim() ?? '');
  if (parsed == -1) return _RemainingMarker.unlimited;
  if (parsed == null || parsed < 0) return _RemainingMarker.invalid;
  return parsed;
}

Map<String, Object?>? _mapOrNull(Object? value) {
  if (value is! Map) return null;
  return <String, Object?>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

String? _positiveIdentity(String raw) {
  final normalized = raw.trim();
  final parsed = int.tryParse(normalized);
  return parsed != null && parsed > 0 && parsed.toString() == normalized
      ? normalized
      : null;
}

String? _safeFileName(String raw) {
  final normalized = raw.trim().replaceAll('\\', '/');
  final value = normalized.split('/').last.trim();
  return value.isEmpty || value.contains('\u0000') ? null : value;
}

String? _fileExtension(String fileName) {
  final index = fileName.lastIndexOf('.');
  return index <= 0 || index == fileName.length - 1
      ? null
      : fileName.substring(index + 1).toLowerCase();
}

String _uploadStatusCode(int status) => switch (status) {
  -1 => 'attachment_extension_not_allowed',
  -2 => 'attachment_upload_invalid',
  -3 => 'attachment_group_file_size_exceeded',
  -4 => 'attachment_extension_banned',
  -5 => 'attachment_extension_file_size_exceeded',
  -6 => 'attachment_upload_permission_denied',
  -7 => 'attachment_invalid_image',
  -8 || -9 => 'attachment_save_failed',
  -10 => 'attachment_upload_hash_invalid',
  -11 => 'attachment_daily_quota_exceeded',
  -12 => 'attachment_filename_rejected',
  -13 => 'attachment_dimensions_exceeded',
  _ => 'attachment_upload_rejected',
};

DataCommandFailureKind _uploadRejectionKind(int status) => switch (status) {
  -6 => DataCommandFailureKind.permissionDenied,
  -10 => DataCommandFailureKind.staleFormhash,
  -1 ||
  -2 ||
  -3 ||
  -4 ||
  -5 ||
  -7 ||
  -11 ||
  -12 ||
  -13 => DataCommandFailureKind.validation,
  _ => DataCommandFailureKind.server,
};

DataCommandRetryPolicy _uploadRetryPolicy(int status) => switch (status) {
  -10 => DataCommandRetryPolicy.afterSessionRefresh,
  -1 ||
  -2 ||
  -3 ||
  -4 ||
  -5 ||
  -7 ||
  -11 ||
  -12 ||
  -13 => DataCommandRetryPolicy.afterInputChange,
  _ => DataCommandRetryPolicy.explicitOnly,
};

DataReadFailure<
  ForumImageAttachmentUploadPreparation,
  ForumImageAttachmentUploadCapabilities
>
_readFailure(String code) => DataReadFailure(
  kind: DataReadFailureKind.parse,
  code: code,
  diagnosticMessage: code,
);

DataReadFailure<T, C> _transportReadFailure<T, C>(
  ForumTransportFailure failure,
) => DataReadFailure<T, C>(
  kind: toReadFailureKind(failure.kind),
  code: failure.code,
  statusCode: failure.statusCode,
  diagnosticMessage: failure.code,
);

DataReadFailure<
  ForumUnusedImageAttachmentDirectory,
  ForumUnusedImageAttachmentCapabilities
>
_directoryReadFailure(String code) => DataReadFailure(
  kind: DataReadFailureKind.parse,
  code: code,
  diagnosticMessage: code,
);

DataCommandNotSent<ForumImageAttachmentUploadReceipt> _notSent(
  String code, {
  DataCommandFailureKind kind = DataCommandFailureKind.validation,
}) => DataCommandNotSent(
  DataCommandFailure(
    kind: kind,
    retryPolicy: kind == DataCommandFailureKind.cancelled
        ? DataCommandRetryPolicy.never
        : DataCommandRetryPolicy.afterInputChange,
    code: code,
    diagnosticMessage: code,
  ),
);

DataCommandOutcomeUnknown<ForumImageAttachmentUploadReceipt> _unknownAfterSend(
  ForumTransportFailure failure,
) => DataCommandOutcomeUnknown(_transportCommandFailure(failure));

DataCommandFailure _transportCommandFailure(ForumTransportFailure failure) {
  final security =
      failure.code.startsWith('security_') || failure.code.startsWith('waf_');
  return DataCommandFailure(
    kind: security
        ? DataCommandFailureKind.securityChallenge
        : switch (failure.kind) {
            ForumTransportFailureKind.network => DataCommandFailureKind.network,
            ForumTransportFailureKind.timeout => DataCommandFailureKind.timeout,
            ForumTransportFailureKind.server => DataCommandFailureKind.server,
            ForumTransportFailureKind.unauthorized =>
              DataCommandFailureKind.unauthenticated,
            ForumTransportFailureKind.parse => DataCommandFailureKind.parse,
            ForumTransportFailureKind.business =>
              DataCommandFailureKind.unknown,
            ForumTransportFailureKind.cancelled =>
              DataCommandFailureKind.cancelled,
            ForumTransportFailureKind.unknown => DataCommandFailureKind.unknown,
          },
    retryPolicy: DataCommandRetryPolicy.explicitOnly,
    code: failure.code,
    statusCode: failure.statusCode,
    diagnosticMessage: failure.code,
  );
}

DataCommandNotSent<ForumImageAttachmentDeleteReceipt> _deleteNotSent(
  String code, {
  DataCommandFailureKind kind = DataCommandFailureKind.validation,
  DataCommandRetryPolicy retryPolicy = DataCommandRetryPolicy.afterInputChange,
}) => DataCommandNotSent(
  DataCommandFailure(
    kind: kind,
    retryPolicy: retryPolicy,
    code: code,
    diagnosticMessage: code,
  ),
);

DataCommandFailure _deleteUnknownFailure(String code) => DataCommandFailure(
  kind: DataCommandFailureKind.parse,
  retryPolicy: DataCommandRetryPolicy.explicitOnly,
  code: code,
  diagnosticMessage: code,
);

DataCommandFailure _formhashCommandFailure(ForumTransportFailure failure) {
  final (kind, retryPolicy) = switch (failure.kind) {
    ForumTransportFailureKind.cancelled => (
      DataCommandFailureKind.cancelled,
      DataCommandRetryPolicy.never,
    ),
    ForumTransportFailureKind.unauthorized => (
      DataCommandFailureKind.unauthenticated,
      DataCommandRetryPolicy.afterSessionRefresh,
    ),
    ForumTransportFailureKind.business => (
      DataCommandFailureKind.staleFormhash,
      DataCommandRetryPolicy.afterSessionRefresh,
    ),
    ForumTransportFailureKind.timeout => (
      DataCommandFailureKind.timeout,
      DataCommandRetryPolicy.explicitOnly,
    ),
    ForumTransportFailureKind.network => (
      DataCommandFailureKind.network,
      DataCommandRetryPolicy.explicitOnly,
    ),
    ForumTransportFailureKind.server => (
      DataCommandFailureKind.server,
      DataCommandRetryPolicy.explicitOnly,
    ),
    ForumTransportFailureKind.parse => (
      DataCommandFailureKind.parse,
      DataCommandRetryPolicy.explicitOnly,
    ),
    ForumTransportFailureKind.unknown => (
      DataCommandFailureKind.unknown,
      DataCommandRetryPolicy.explicitOnly,
    ),
  };
  return DataCommandFailure(
    kind: kind,
    retryPolicy: retryPolicy,
    code: failure.code,
    statusCode: failure.statusCode,
    diagnosticMessage: failure.code,
  );
}

List<ForumUnusedImageAttachment> _parseUnusedDirectory({
  required String body,
  required Uri sourceUri,
  required Uri siteOrigin,
  required bool authenticated,
}) {
  if (!_isCatalogUri(sourceUri, siteOrigin)) {
    throw const FormatException('catalog_uri');
  }
  final payload = _extractCdata(body);
  if (payload == null) throw const FormatException('catalog_cdata');
  if (payload.trim().isEmpty) {
    if (!authenticated) throw const FormatException('catalog_session');
    return const <ForumUnusedImageAttachment>[];
  }
  final fragment = html_parser.parseFragment(payload);
  if (fragment.nodes.whereType<Text>().any(
        (node) => node.data.trim().isNotEmpty,
      ) ||
      fragment.children.length != 1 ||
      fragment.children.single.localName != 'table' ||
      !fragment.children.single.classes.contains('imgl')) {
    throw const FormatException('catalog_structure');
  }
  final cells = fragment.querySelectorAll('td');
  final imageCells = cells.where((cell) => cell.id.startsWith('image_td_'));
  if (cells
      .where((cell) => !cell.id.startsWith('image_td_'))
      .any(
        (cell) =>
            cell.text.trim().isNotEmpty || cell.querySelector('img') != null,
      )) {
    throw const FormatException('catalog_structure');
  }
  final byAid = <String, ForumUnusedImageAttachment>{};
  for (final cell in imageCells) {
    final aid = _positiveIdentity(cell.id.substring('image_td_'.length));
    if (aid == null) {
      throw const FormatException('catalog_aid');
    }
    final images = cell.querySelectorAll('img[src]');
    final anchors = cell.querySelectorAll('#imageattach$aid');
    if (images.length != 1 ||
        images.single.id != 'image_$aid' ||
        anchors.length != 1) {
      throw const FormatException('catalog_image');
    }
    final raw = (images.single.attributes['src'] ?? '').replaceAll(
      '&amp;',
      '&',
    );
    final thumbnailUri = sourceUri.resolve(raw);
    final thumbnailMods =
        thumbnailUri.queryParametersAll['mod'] ?? const <String>[];
    final thumbnailAids =
        thumbnailUri.queryParametersAll['aid'] ?? const <String>[];
    if (!_sameOrigin(thumbnailUri, siteOrigin) ||
        thumbnailUri.path != '/forum.php' ||
        thumbnailMods.length != 1 ||
        thumbnailMods.single != 'image' ||
        thumbnailAids.length != 1 ||
        thumbnailAids.single != aid) {
      throw const FormatException('catalog_thumbnail');
    }
    final descriptions = cell.querySelectorAll(
      'input[name="attachnew[$aid][description]"]',
    );
    if (descriptions.length > 1) {
      throw const FormatException('catalog_description');
    }
    final parsed = ForumUnusedImageAttachment(
      aid: aid,
      thumbnail: ForumResourceReference(
        uri: thumbnailUri,
        referer: sourceUri,
        kind: ForumResourceKind.image,
        origin: ForumResourceOrigin.sameSite,
      ),
      fileName: anchors.single.attributes['title']?.trim() ?? '',
      description: descriptions.isEmpty
          ? ''
          : descriptions.single.attributes['value']?.trim() ?? '',
    );
    final previous = byAid[aid];
    if (previous != null) {
      if (previous.thumbnail.uri != parsed.thumbnail.uri ||
          previous.thumbnail.referer != parsed.thumbnail.referer ||
          previous.fileName != parsed.fileName ||
          previous.description != parsed.description) {
        throw const FormatException('catalog_aid_conflict');
      }
      continue;
    }
    byAid[aid] = parsed;
  }
  if (byAid.isEmpty) {
    final knownEmpty = cells.every(
      (cell) => cell.text.trim().isEmpty && cell.querySelector('img') == null,
    );
    if (!knownEmpty || !authenticated) {
      throw const FormatException('catalog_empty');
    }
  }
  return List.unmodifiable(byAid.values);
}

String? _extractCdata(String body) {
  final match = RegExp(
    r'<root(?:\s[^>]*)?>[\s\S]*?<!\[CDATA\[([\s\S]*?)\]\]>[\s\S]*?</root\s*>',
    caseSensitive: false,
  ).firstMatch(body.trim());
  return match?.group(1);
}

int? _extractCdataInteger(String body) =>
    int.tryParse(_extractCdata(body)?.trim() ?? '');

bool _isCatalogUri(Uri uri, Uri origin) =>
    _sameOrigin(uri, origin) &&
    uri.path == '/forum.php' &&
    uri.queryParameters['mod'] == 'ajax' &&
    uri.queryParameters['action'] == 'imagelist' &&
    uri.queryParameters['posttime'] == '0';

bool _isDeleteUri(Uri uri, Uri origin) =>
    _sameOrigin(uri, origin) &&
    uri.path == '/forum.php' &&
    uri.queryParameters['mod'] == 'ajax' &&
    uri.queryParameters['action'] == 'deleteattach';

bool _sameOrigin(Uri left, Uri right) =>
    left.scheme.toLowerCase() == right.scheme.toLowerCase() &&
    left.host.toLowerCase() == right.host.toLowerCase() &&
    left.port == right.port;
