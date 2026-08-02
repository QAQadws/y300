import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_attach_bbcode_grammar.dart';
import 'package:y300/features/composer_shared/domain/services/composer_image_attachment_expiry_policy.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_submit_models.dart';
import 'package:y300/features/thread/domain/services/post_edit_native_capability_classifier.dart';

final class PostEditSubmitPayloadBuilder {
  const PostEditSubmitPayloadBuilder({
    this.expiryPolicy = const ComposerImageAttachmentExpiryPolicy(),
    this.capabilityClassifier = const PostEditNativeCapabilityClassifier(),
  });

  final ComposerImageAttachmentExpiryPolicy expiryPolicy;
  final PostEditNativeCapabilityClassifier capabilityClassifier;
  static const _grammar = ComposerAttachBbCodeGrammar();

  PostEditSubmitPayload build(PostEditSubmitCommand command) {
    if (command.snapshot.target != command.target) {
      throw const PostEditSubmitPayloadBuildException(
        PostEditSubmitPayloadBuildFailure.targetMismatch,
      );
    }
    if (capabilityClassifier.classify(command.snapshot)
        is! PostEditNativeSupported) {
      throw const PostEditSubmitPayloadBuildException(
        PostEditSubmitPayloadBuildFailure.unsupportedControl,
      );
    }
    if (!_isManagedSubmitUri(command.snapshot.submitUri, command.target)) {
      throw const PostEditSubmitPayloadBuildException(
        PostEditSubmitPayloadBuildFailure.invalidSubmitUri,
      );
    }
    if (!_matchesTargetControls(
      command.snapshot.successfulControls,
      command.target,
    )) {
      throw const PostEditSubmitPayloadBuildException(
        PostEditSubmitPayloadBuildFailure.targetMismatch,
      );
    }
    if (command.attachmentSession.deletingAids.isNotEmpty) {
      throw const PostEditSubmitPayloadBuildException(
        PostEditSubmitPayloadBuildFailure.deletionInProgress,
      );
    }
    if (command.imageAttachments.any(
      (attachment) =>
          attachment.status == ComposerImageAttachmentStatus.uploading,
    )) {
      throw const PostEditSubmitPayloadBuildException(
        PostEditSubmitPayloadBuildFailure.uploadInProgress,
      );
    }

    final messageFields = command.snapshot.successfulControls
        .where((field) => field.name.trim().toLowerCase() == 'message')
        .length;
    if (messageFields != 1) {
      throw const PostEditSubmitPayloadBuildException(
        PostEditSubmitPayloadBuildFailure.duplicateMessage,
      );
    }
    final subjectFields = command.snapshot.successfulControls
        .where((field) => field.name.trim().toLowerCase() == 'subject')
        .length;
    if (subjectFields != 1) {
      throw const PostEditSubmitPayloadBuildException(
        PostEditSubmitPayloadBuildFailure.duplicateSubject,
      );
    }

    final referencedAids = <String>[];
    final seenReferencedAids = <String>{};
    final danglingAids = <String>[];
    final seenDanglingAids = <String>{};
    final localByAid = <String, ComposerImageAttachment>{
      for (final attachment in command.imageAttachments)
        if (attachment.aid?.trim().isNotEmpty == true)
          attachment.aid!.trim(): attachment,
    };
    final existingByAid = command.attachmentSession.existingImagesByAid;

    for (final token in _grammar.scan(command.message)) {
      final aid = token.aid.trim();
      if (seenReferencedAids.add(aid)) {
        referencedAids.add(aid);
      }
      final local = localByAid[aid];
      final isLocalUsable =
          local != null &&
          local.status == ComposerImageAttachmentStatus.uploaded &&
          !expiryPolicy.isExpired(
            uploadedAt: local.uploadedAt,
            now: command.now,
          );
      final isExistingUsable = existingByAid.containsKey(aid);
      if (command.attachmentSession.deletedAidTombstones.contains(aid) ||
          (!isLocalUsable && !isExistingUsable)) {
        if (seenDanglingAids.add(aid)) {
          danglingAids.add(aid);
        }
      }
    }

    final existingAttachmentAids = <String>{};
    final fields = <MapEntry<String, String>>[];
    var messageWritten = false;
    var subjectWritten = false;
    var editsubmitWritten = false;
    for (final field in command.snapshot.successfulControls) {
      final name = field.name.trim();
      final lowerName = name.toLowerCase();
      final attachmentField = _attachmentField(name);
      if (_isFilteredField(lowerName) ||
          (attachmentField != null &&
              command.attachmentSession.deletedAidTombstones.contains(
                attachmentField.aid,
              ))) {
        continue;
      }
      if (attachmentField != null) {
        existingAttachmentAids.add(attachmentField.aid);
      }
      if (lowerName == 'message') {
        if (messageWritten) {
          throw const PostEditSubmitPayloadBuildException(
            PostEditSubmitPayloadBuildFailure.duplicateMessage,
          );
        }
        messageWritten = true;
        fields.add(MapEntry(name, command.message));
        continue;
      }
      if (lowerName == 'subject') {
        if (subjectWritten) {
          throw const PostEditSubmitPayloadBuildException(
            PostEditSubmitPayloadBuildFailure.duplicateSubject,
          );
        }
        subjectWritten = true;
        fields.add(MapEntry(name, command.subject.trim()));
        continue;
      }
      if (lowerName == 'editsubmit') {
        if (!editsubmitWritten) {
          editsubmitWritten = true;
          fields.add(MapEntry(name, 'yes'));
        }
        continue;
      }
      if (!_isAllowedField(name)) {
        throw const PostEditSubmitPayloadBuildException(
          PostEditSubmitPayloadBuildFailure.unsupportedControl,
        );
      }
      fields.add(MapEntry(name, field.value));
    }
    if (!messageWritten) {
      throw const PostEditSubmitPayloadBuildException(
        PostEditSubmitPayloadBuildFailure.duplicateMessage,
      );
    }
    if (!subjectWritten) {
      throw const PostEditSubmitPayloadBuildException(
        PostEditSubmitPayloadBuildFailure.duplicateSubject,
      );
    }
    if (!editsubmitWritten) {
      fields.add(const MapEntry('editsubmit', 'yes'));
    }

    final attachNewAids = <String>[];
    for (final aid in referencedAids) {
      final local = localByAid[aid];
      if (local == null ||
          local.status != ComposerImageAttachmentStatus.uploaded ||
          expiryPolicy.isExpired(
            uploadedAt: local.uploadedAt,
            now: command.now,
          ) ||
          command.attachmentSession.deletedAidTombstones.contains(aid) ||
          existingAttachmentAids.contains(aid)) {
        continue;
      }
      attachNewAids.add(aid);
      fields.add(MapEntry('attachnew[$aid][description]', ''));
    }

    final query = <String, String>{
      for (final entry in command.snapshot.submitUri.queryParameters.entries)
        if (entry.key.toLowerCase() != 'formhash') entry.key: entry.value,
      'editsubmit': 'yes',
      'handlekey': 'postform',
      'inajax': '1',
    };
    return PostEditSubmitPayload(
      submitUri: command.snapshot.submitUri.replace(queryParameters: query),
      fields: fields,
      danglingAids: danglingAids,
      attachNewAids: attachNewAids,
    );
  }

  bool _isManagedSubmitUri(Uri uri, PostEditTarget target) {
    if (uri.scheme.toLowerCase() != target.editUri.scheme.toLowerCase() ||
        uri.host.toLowerCase() != target.editUri.host.toLowerCase() ||
        uri.port != target.editUri.port ||
        uri.path.toLowerCase() != '/forum.php') {
      return false;
    }
    final query = uri.queryParametersAll;
    return _single(query, 'mod')?.toLowerCase() == 'post' &&
        _single(query, 'action')?.toLowerCase() == 'edit' &&
        _single(query, 'editsubmit')?.toLowerCase() == 'yes';
  }

  bool _isAllowedField(String name) {
    final lower = name.toLowerCase();
    if (const <String>{
      'formhash',
      'posttime',
      'fid',
      'tid',
      'pid',
      'page',
      'subject',
      'message',
      'editsubmit',
      'typeid',
      'readperm',
      'price',
      'tags',
      'isanonymous',
      'hiddenreplies',
      'ordertype',
      'allownoticeauthor',
      'usesig',
      'parseurloff',
      'smileyoff',
      'bbcodeoff',
      'htmlon',
      'imgcontent',
    }.contains(lower)) {
      return true;
    }
    return _attachmentField(name) != null;
  }

  bool _matchesTargetControls(
    List<PostEditFormField> fields,
    PostEditTarget target,
  ) {
    return _singleControlValue(fields, 'fid') == target.fid &&
        _singleControlValue(fields, 'tid') == target.tid &&
        _singleControlValue(fields, 'pid') == target.pid;
  }

  String? _singleControlValue(List<PostEditFormField> fields, String name) {
    final matches = fields
        .where((field) => field.name.trim().toLowerCase() == name)
        .map((field) => field.value.trim())
        .toList(growable: false);
    if (matches.length != 1) {
      return null;
    }
    return matches.single;
  }

  bool _isFilteredField(String lowerName) {
    return lowerName == 'delete' ||
        lowerName.startsWith('delete[') ||
        lowerName == 'delattachop' ||
        lowerName.startsWith('delattachop[') ||
        lowerName == 'filedata' ||
        lowerName.startsWith('filedata[');
  }

  _AttachmentField? _attachmentField(String name) {
    final match = RegExp(
      r'^(attachnew|attachupdate)\[([1-9]\d*)\]\[(.+)\]$',
      caseSensitive: false,
    ).firstMatch(name.trim());
    if (match == null) {
      return null;
    }
    final key = match.group(3)!.replaceAll("'", '').replaceAll('"', '');
    if (!const <String>{'description', 'readperm', 'price'}.contains(key)) {
      return null;
    }
    return _AttachmentField(aid: match.group(2)!, key: key);
  }

  String? _single(Map<String, List<String>> values, String name) {
    final items = values[name];
    if (items == null || items.length != 1 || items.single.trim().isEmpty) {
      return null;
    }
    return items.single.trim();
  }
}

final class _AttachmentField {
  const _AttachmentField({required this.aid, required this.key});

  final String aid;
  final String key;
}
