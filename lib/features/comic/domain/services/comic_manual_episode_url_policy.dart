import 'package:y300/core/config/app_config.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

/// 手动添加章节的解析结果。
class ManualEpisodeTarget {
  const ManualEpisodeTarget({required this.tid, required this.sourceUrl});

  /// 帖子 tid，章节写库后作为 `source_tid`，阅读器的接口请求与原帖跳转都复用它。
  final String tid;

  /// 归一化后的帖子地址，仅用于展示与回溯来源。
  final String sourceUrl;
}

enum ComicManualEpisodeInputErrorCode {
  emptyInput,
  invalidUrl,
  unsupportedScheme,
  unexpectedHost,
  unsupportedThreadUrl,
  missingTid,
}

class ComicManualEpisodeInputException implements Exception {
  const ComicManualEpisodeInputException(this.code, {this.expectedHost});

  final ComicManualEpisodeInputErrorCode code;
  final String? expectedHost;

  @override
  String toString() => 'ComicManualEpisodeInputException(${code.name})';
}

/// 校验并归一化用户手动输入的章节地址。
///
/// 用户可能从站内任意位置复制链接（网页版 forum.php、伪静态 thread-*.html、
/// 移动端 api/mobile），三种形态携带的有效信息只有 tid。这里统一收敛成 tid，
/// 让下游完全不必关心用户从哪一种页面复制的。
class ComicManualEpisodeUrlPolicy {
  const ComicManualEpisodeUrlPolicy({
    ForumReferenceResolver threadUrlParser = const ForumReferenceResolver(),
  }) : _threadUrlParser = threadUrlParser;

  final ForumReferenceResolver _threadUrlParser;

  static final RegExp _tidPattern = RegExp(r'^[1-9][0-9]*$');

  /// Parses input and reports expected validation failures with stable codes.
  ManualEpisodeTarget parse(String rawInput) {
    final value = rawInput.trim();
    if (value.isEmpty) {
      throw const ComicManualEpisodeInputException(
        ComicManualEpisodeInputErrorCode.emptyInput,
      );
    }

    // 纯数字直接当 tid：输入里唯一有用的信息本来就是它，没必要强迫用户拼一个
    // 完整链接再被解析回来。
    if (_tidPattern.hasMatch(value)) {
      return ManualEpisodeTarget(tid: value, sourceUrl: _viewThreadUrl(value));
    }

    final inputUri = Uri.tryParse(value);
    if (inputUri == null) {
      throw const ComicManualEpisodeInputException(
        ComicManualEpisodeInputErrorCode.invalidUrl,
      );
    }
    if (inputUri.isAbsolute &&
        inputUri.scheme != 'http' &&
        inputUri.scheme != 'https') {
      throw const ComicManualEpisodeInputException(
        ComicManualEpisodeInputErrorCode.unsupportedScheme,
      );
    }
    final siteHost = Uri.parse(AppConfig.siteBaseUrl).host;
    if (inputUri.isAbsolute &&
        inputUri.host.toLowerCase() != siteHost.toLowerCase()) {
      throw ComicManualEpisodeInputException(
        ComicManualEpisodeInputErrorCode.unexpectedHost,
        expectedHost: siteHost,
      );
    }

    final normalized = _threadUrlParser.normalizeHref(value);
    if (normalized == null) {
      throw const ComicManualEpisodeInputException(
        ComicManualEpisodeInputErrorCode.invalidUrl,
      );
    }

    final uri = Uri.tryParse(normalized);
    if (uri == null) {
      throw const ComicManualEpisodeInputException(
        ComicManualEpisodeInputErrorCode.invalidUrl,
      );
    }
    if (uri.hasScheme && uri.scheme != 'http' && uri.scheme != 'https') {
      throw const ComicManualEpisodeInputException(
        ComicManualEpisodeInputErrorCode.unsupportedScheme,
      );
    }

    if (uri.host.isNotEmpty &&
        uri.host.toLowerCase() != siteHost.toLowerCase()) {
      throw ComicManualEpisodeInputException(
        ComicManualEpisodeInputErrorCode.unexpectedHost,
        expectedHost: siteHost,
      );
    }

    if (!_threadUrlParser.isSupportedThreadUrl(normalized)) {
      throw const ComicManualEpisodeInputException(
        ComicManualEpisodeInputErrorCode.unsupportedThreadUrl,
      );
    }

    final tid = _threadUrlParser.extractTid(normalized);
    if (tid == null || !_tidPattern.hasMatch(tid)) {
      throw const ComicManualEpisodeInputException(
        ComicManualEpisodeInputErrorCode.missingTid,
      );
    }
    return ManualEpisodeTarget(tid: tid, sourceUrl: _viewThreadUrl(tid));
  }

  /// 统一回写成网页版帖子地址：入库地址与用户输入形态解耦，列表展示才稳定。
  String _viewThreadUrl(String tid) {
    return Uri.parse(
      '${AppConfig.siteBaseUrl}/',
    ).resolve('forum.php?mod=viewthread&tid=$tid').toString();
  }
}
