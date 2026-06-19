import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/reply/domain/services/reply_form_parser.dart';

abstract class ReplyFormPreparationDataSource {
  Future<ReplyPreparation> fetchReplyPreparation(Uri replyFormUri);
}

class DiscuzReplyFormPreparationDataSource
    implements ReplyFormPreparationDataSource {
  DiscuzReplyFormPreparationDataSource({
    required YamiboHttpGateway gateway,
    ReplyFormParser parser = const ReplyFormParser(),
  }) : _gateway = gateway,
       _parser = parser;

  final YamiboHttpGateway _gateway;
  final ReplyFormParser _parser;

  @override
  Future<ReplyPreparation> fetchReplyPreparation(Uri replyFormUri) async {
    final response = await _gateway.getText(
      replyFormUri,
      context: const YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: 'reply.prepareForm',
        pageKind: 'reply.form',
      ),
      headers: const <String, String>{
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      },
    );
    if (response case ApiFailure(:final error)) {
      throw ReplyFormParseException(error.message);
    }
    final html = response.dataOrNull?.body ?? '';
    final parsed = _parser.parse(sourceUri: replyFormUri, html: html);
    if (parsed case ApiSuccess<ReplyPreparation>(:final data)) {
      return data;
    }
    final error = (parsed as ApiFailure<ReplyPreparation>).error;
    throw ReplyFormParseException(error.message);
  }
}

class ReplyFormParseException implements Exception {
  const ReplyFormParseException(this.message);

  final String message;

  @override
  String toString() => message;
}
