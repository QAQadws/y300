import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_insertion_models.dart';

/// Picker order is independent of event arrival and the editor's current list.
final class ComposerUploadBatch {
  ComposerUploadBatch({
    required this.anchor,
    required Iterable<String> localIds,
  }) : localIds = List<String>.unmodifiable(localIds);

  final ComposerInsertionAnchor? anchor;
  final List<String> localIds;

  List<String> successfulAids(Iterable<ComposerImageAttachment> attachments) {
    final byLocalId = <String, ComposerImageAttachment>{
      for (final attachment in attachments) attachment.localId: attachment,
    };
    final seen = <String>{};
    return [
      for (final localId in localIds)
        if (byLocalId[localId] case final attachment?)
          if (attachment.canEnterSubmitPayload &&
              seen.add(attachment.aid!.trim()))
            attachment.aid!.trim(),
    ];
  }
}
