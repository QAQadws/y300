import 'package:y300/features/thread/domain/models/post_edit_models.dart';

final class PostEditAttachmentDeleteUriBuilder {
  const PostEditAttachmentDeleteUriBuilder();

  Uri build(PostEditAttachmentDeleteCommand command) {
    return command.target.editUri.replace(
      path: '/forum.php',
      queryParameters: <String, String>{
        'mod': 'ajax',
        'action': 'deleteattach',
        'inajax': 'yes',
        'aids[]': command.aid,
        'tid': command.target.tid,
        'pid': command.target.pid,
        'formhash': command.formHash,
      },
    );
  }
}
