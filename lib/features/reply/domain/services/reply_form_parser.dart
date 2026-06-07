import 'package:html/parser.dart' as html_parser;
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/utils/parse_utils.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';

class ReplyFormParser {
  const ReplyFormParser();

  ApiResult<ReplyPreparation> parse({
    required Uri sourceUri,
    required String html,
  }) {
    final document = html_parser.parse(html);
    final form = document.querySelector('#postform');
    if (form == null) {
      return const ApiFailure<ReplyPreparation>(
        ApiError(type: ApiErrorType.parse, message: '未找到楼层回复表单'),
      );
    }

    final hiddenValues = <String, String>{};
    for (final input in form.querySelectorAll('input')) {
      final name = input.attributes['name']?.trim();
      if (name == null || name.isEmpty) {
        continue;
      }
      hiddenValues[name] = input.attributes['value'] ?? '';
    }

    final actionUri = _resolveActionUri(
      sourceUri: sourceUri,
      action: form.attributes['action'],
    );
    final queryValues = <String, String>{
      ...sourceUri.queryParameters,
      if (actionUri != null) ...actionUri.queryParameters,
    };

    final fid = _firstNonEmpty(
      hiddenValues['fid'],
      queryValues['fid'],
    );
    final tid = _firstNonEmpty(
      hiddenValues['tid'],
      queryValues['tid'],
    );
    final repquote = _firstNonEmpty(
      queryValues['repquote'],
      hiddenValues['repquote'],
    );
    final repPost = _firstNonEmpty(hiddenValues['reppost'], repquote);
    final repPid = _firstNonEmpty(hiddenValues['reppid'], repquote);
    final pid = _firstNonEmpty(repquote, repPost, repPid);

    if (fid == null || tid == null || pid == null) {
      return const ApiFailure<ReplyPreparation>(
        ApiError(type: ApiErrorType.parse, message: '楼层回复参数缺失'),
      );
    }

    return ApiSuccess<ReplyPreparation>(
      ReplyPreparation(
        target: ReplyTarget.post(
          fid: fid,
          tid: tid,
          pid: pid,
          sourceUri: sourceUri,
        ),
        reference: ReplyReference(
          formHash: _firstNonEmpty(hiddenValues['formhash']),
          noticeAuthor: _firstNonEmpty(hiddenValues['noticeauthor']),
          noticeTrimStr: _firstNonEmpty(hiddenValues['noticetrimstr']),
          noticeAuthorMsg: _firstNonEmpty(hiddenValues['noticeauthormsg']),
          repPid: repPid,
          repPost: repPost,
          rawQuotePreview: _extractQuotePreview(form.text),
        ),
      ),
    );
  }

  Uri? _resolveActionUri({
    required Uri sourceUri,
    required String? action,
  }) {
    final trimmed = action?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return sourceUri.resolve(trimmed.replaceAll('&amp;', '&'));
  }

  String? _extractQuotePreview(String rawText) {
    final normalized = ParseUtils.asString(rawText)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  String? _firstNonEmpty(String? first, [String? second, String? third]) {
    for (final value in <String?>[first, second, third]) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return null;
  }
}
