import 'package:dio/dio.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';

class ReplySubmitPayload {
  const ReplySubmitPayload({
    required this.formHash,
    required this.fid,
    required this.tid,
    required this.message,
    required this.useSignature,
    this.repPid,
    this.repPost,
    this.noticeAuthor,
    this.noticeTrimStr,
    this.noticeAuthorMsg,
    this.uploadedAttachmentAids = const <String>[],
  });

  final String formHash;
  final String fid;
  final String tid;
  final String message;
  final bool useSignature;
  final String? repPid;
  final String? repPost;
  final String? noticeAuthor;
  final String? noticeTrimStr;
  final String? noticeAuthorMsg;
  final List<String> uploadedAttachmentAids;

  Map<String, String> toFormData() {
    final attachmentAids = _normalizeAttachmentAids(uploadedAttachmentAids);
    return <String, String>{
      'formhash': formHash,
      'fid': fid,
      'tid': tid,
      'message': message,
      'replysubmit': 'yes',
      'usesig': useSignature ? '1' : '0',
      if (attachmentAids.isNotEmpty) 'allowphoto': '1',
      for (final aid in attachmentAids) 'attachnew[$aid][description]': '',
      if ((repPid ?? '').isNotEmpty) 'reppid': repPid!,
      if ((repPost ?? '').isNotEmpty) 'reppost': repPost!,
      if ((noticeAuthor ?? '').isNotEmpty) 'noticeauthor': noticeAuthor!,
      if ((noticeTrimStr ?? '').isNotEmpty) 'noticetrimstr': noticeTrimStr!,
      if ((noticeAuthorMsg ?? '').isNotEmpty)
        'noticeauthormsg': noticeAuthorMsg!,
    };
  }

  factory ReplySubmitPayload.fromDraft({
    required ReplyDraft draft,
    required String formHash,
    required String message,
  }) {
    return ReplySubmitPayload(
      formHash: formHash,
      fid: draft.fid,
      tid: draft.tid,
      message: message,
      useSignature: draft.useSignature,
      repPid: draft.repPid,
      repPost: draft.repPost,
      noticeAuthor: draft.noticeAuthor,
      noticeTrimStr: draft.noticeTrimStr,
      noticeAuthorMsg: draft.noticeAuthorMsg,
      uploadedAttachmentAids: draft.uploadedAttachmentAids,
    );
  }

  static List<String> _normalizeAttachmentAids(Iterable<String> aids) {
    final seen = <String>{};
    final normalized = <String>[];
    for (final aid in aids) {
      final trimmed = aid.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) {
        continue;
      }
      normalized.add(trimmed);
    }
    return normalized;
  }
}

class ReplyRemoteResponse {
  const ReplyRemoteResponse({required this.data, required this.statusCode});

  final dynamic data;
  final int? statusCode;
}

abstract class DiscuzReplyRemoteDataSource {
  Future<ReplyRemoteResponse> sendReply(ReplySubmitPayload payload);
}

class DiscuzReplyDioRemoteDataSource implements DiscuzReplyRemoteDataSource {
  DiscuzReplyDioRemoteDataSource({required YamiboHttpGateway gateway})
    : _gateway = gateway;

  final YamiboHttpGateway _gateway;

  @override
  Future<ReplyRemoteResponse> sendReply(ReplySubmitPayload payload) async {
    final endpoint = Uri.parse(AppConfig.apiBaseUrl).replace(
      queryParameters: const <String, String>{
        'module': 'sendreply',
        'version': '4',
      },
    );
    final response = await _gateway.postForm(
      endpoint,
      context: const YamiboRequestContext(
        kind: YamiboRequestKind.api,
        operation: 'reply.submit',
        module: 'sendreply',
      ),
      data: payload.toFormData(),
      headers: <String, String>{
        'referer':
            '${AppConfig.siteBaseUrl}/forum.php?mod=viewthread&tid=${payload.tid}&mobile=2',
        'accept': 'application/json, text/plain, */*',
      },
    );
    if (response case ApiFailure(:final error)) {
      throw DioException(
        requestOptions: RequestOptions(path: endpoint.toString()),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: endpoint.toString()),
          statusCode: error.statusCode,
          data: error.raw,
        ),
        message: error.message,
      );
    }
    final data = response.dataOrNull;
    return ReplyRemoteResponse(data: data?.body, statusCode: data?.statusCode);
  }
}
