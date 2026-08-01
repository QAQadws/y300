import 'package:dio/dio.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/features/posting/domain/models/posting_models.dart';

/// 发帖提交的 form-urlencoded 载荷。
///
/// 把"业务字段 → form key/value"集中在这里，让上层的 Repository / 测试
/// 不关心 Discuz 字段拼写细节。
class NewThreadSubmitForm {
  const NewThreadSubmitForm({required this.payload});

  final NewThreadDraftPayload payload;

  Map<String, String> toFormData() {
    final base = _baseFormData();
    base.addAll(_specialFormData());
    _writeTagsTo(base);
    if (payload.special == NewThreadSpecial.poll) {
      // poll == null 在 builder 阶段不会发生（payload 类型由 builder 兜底），
      // 这里仍兜一下：缺 poll 配置就不写 poll 字段，让服务端报参数错。
      final poll = payload.poll;
      if (poll != null) {
        _writePollTo(base, poll);
      }
    }
    return base;
  }

  /// 与 special / tags / poll 都无关的"始终要发"字段。
  ///
  /// 把基础字段独立出来后，新增 special 维度只追加 [_specialFormData] 与
  /// [_writePollTo]，base map 不会因此膨胀；测试也能精准断言"普通帖不写 poll"。
  Map<String, String> _baseFormData() {
    final attachmentAids = _normalizeAttachmentAids(
      payload.uploadedAttachmentAids,
    );
    return <String, String>{
      'formhash': payload.formHash,
      'topicsubmit': 'yes',
      'subject': payload.subject,
      'message': payload.message,
      'typeid': payload.typeid,
      'usesig': payload.useSignature ? '1' : '0',
      'allownoticeauthor': payload.allowNoticeAuthor ? '1' : '0',
      if (payload.bbCodeOff) 'bbcodeoff': '1',
      if (payload.smileyOff) 'smileyoff': '1',
      if (payload.parseUrlOff) 'parseurloff': '1',
      if (attachmentAids.isNotEmpty) 'allowphoto': '1',
      for (final aid in attachmentAids) 'attachnew[$aid][description]': '',
    };
  }

  Map<String, String> _specialFormData() {
    switch (payload.special) {
      case NewThreadSpecial.normal:
        return const <String, String>{'special': '0'};
      case NewThreadSpecial.poll:
        return const <String, String>{'special': '1'};
    }
  }

  /// 仅当 tags 非空时写 `tags=tag1,tag2`；空时连键都不发，避免 Discuz
  /// 把空字符串当成"清空已有标签"处理。
  void _writeTagsTo(Map<String, String> base) {
    if (payload.tags.isEmpty) return;
    base['tags'] = payload.tags.join(',');
  }

  /// 投票字段映射，与 docs/发帖资料搜集.md 的 form 一一对齐：
  ///
  ///   tpolloption=2                       使用多行 polloptions
  ///   polloptions=A\nB\nC                 字面 \n（dio 会按 form percent-encode）
  ///   maxchoices=1 | N                    单 / 多选
  ///   expiration=0..N                     截止天数；0 表示不过期
  ///   overt=0|1                           是否公开投票人
  ///   visibilitypoll=1                    仅当用户开启"投票后才显示结果"
  ///
  /// builder 已用 normalizer 收敛过 options / maxChoices / expirationDays，
  /// 这里只做字段命名映射，不再做边界裁剪。
  void _writePollTo(Map<String, String> base, NewThreadPollDraft poll) {
    base['tpolloption'] = '2';
    base['polloptions'] = poll.options.join('\n');
    base['maxchoices'] = poll.multiple ? poll.maxChoices.toString() : '1';
    base['expiration'] = poll.expirationDays.toString();
    base['overt'] = poll.overt ? '1' : '0';
    if (poll.visibilityPoll) {
      base['visibilitypoll'] = '1';
    }
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

class NewThreadRemoteResponse {
  const NewThreadRemoteResponse({required this.data, required this.statusCode});

  final dynamic data;
  final int? statusCode;
}

abstract class NewThreadRemoteDataSource {
  Future<NewThreadRemoteResponse> submit(NewThreadSubmitForm form);
}

class DiscuzNewThreadDioRemoteDataSource implements NewThreadRemoteDataSource {
  DiscuzNewThreadDioRemoteDataSource({required YamiboHttpGateway gateway})
    : _gateway = gateway;

  final YamiboHttpGateway _gateway;

  @override
  Future<NewThreadRemoteResponse> submit(NewThreadSubmitForm form) async {
    final endpoint = Uri.parse(AppConfig.apiBaseUrl).replace(
      queryParameters: <String, String>{
        'module': 'newthread',
        'version': '4',
        'fid': form.payload.fid,
      },
    );
    final response = await _gateway.postForm(
      endpoint,
      context: const YamiboRequestContext(
        kind: YamiboRequestKind.api,
        operation: 'posting.newThread.submit',
        module: 'newthread',
      ),
      data: form.toFormData(),
      headers: <String, String>{
        'referer':
            '${AppConfig.siteBaseUrl}/forum.php?mod=post&action=newthread&fid=${form.payload.fid}',
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
    return NewThreadRemoteResponse(
      data: data?.body,
      statusCode: data?.statusCode,
    );
  }
}
