import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

/// Data-layer boundary for the few App workflows that intentionally decode a
/// raw thread document without loading it through a repository.
final class ThreadDetailDocumentDecoder {
  const ThreadDetailDocumentDecoder(this._decode);

  final Y300ThreadDetailHtmlDecoder _decode;

  ThreadDetailData decode(
    String html, {
    required String fallbackTid,
    required int fallbackPage,
    String fallbackSubject = '',
  }) {
    return _decode(
      html,
      fallbackTid: fallbackTid,
      fallbackPage: fallbackPage,
      fallbackSubject: fallbackSubject,
    );
  }
}
