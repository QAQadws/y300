import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';

final postEditNativeCapabilityClassifierProvider =
    Provider<PostEditNativeCapabilityClassifier>((ref) {
      return const PostEditNativeCapabilityClassifier();
    });

class PostEditNativeCapabilityClassifier {
  const PostEditNativeCapabilityClassifier({this.profileVersion = 1});

  final int profileVersion;

  PostEditNativeSupportDecision classify(PostEditFormSnapshot snapshot) {
    final evidence = snapshot.structureEvidence;
    if (evidence.hasSpecialEditorMarker) {
      return const PostEditWebViewOnly(
        reason: PostEditFallbackReason.unsupportedSpecialThread,
      );
    }
    if (evidence.hasThreadSortMarker) {
      return const PostEditWebViewOnly(
        reason: PostEditFallbackReason.unsupportedThreadSort,
      );
    }
    if (evidence.hasPluginMarker) {
      return const PostEditWebViewOnly(
        reason: PostEditFallbackReason.unsupportedPluginField,
      );
    }
    if (evidence.hasRegularAttachments) {
      return const PostEditWebViewOnly(
        reason: PostEditFallbackReason.unsupportedRegularAttachment,
      );
    }
    if (evidence.hasExternalFormOwnerControls ||
        evidence.hasUnsupportedControlType ||
        evidence.hasDestructiveField ||
        evidence.hasAuditMarker) {
      return const PostEditWebViewOnly(
        reason: PostEditFallbackReason.unknownSuccessfulControl,
      );
    }

    for (final field in snapshot.successfulControls) {
      final name = field.name.trim();
      final lowerName = name.toLowerCase();
      if (_isUnsafeTextMode(field)) {
        return const PostEditWebViewOnly(
          reason: PostEditFallbackReason.unsupportedHtmlMode,
        );
      }
      if (_isSpecialField(lowerName, field.value)) {
        return const PostEditWebViewOnly(
          reason: PostEditFallbackReason.unsupportedSpecialThread,
        );
      }
      if (_isSortField(lowerName, field.value)) {
        return const PostEditWebViewOnly(
          reason: PostEditFallbackReason.unsupportedThreadSort,
        );
      }
      if (_isPluginField(lowerName) || !_isAllowedField(name)) {
        return PostEditWebViewOnly(
          reason: _isPluginField(lowerName)
              ? PostEditFallbackReason.unsupportedPluginField
              : PostEditFallbackReason.unknownSuccessfulControl,
        );
      }
      if (_isDestructiveField(lowerName)) {
        return const PostEditWebViewOnly(
          reason: PostEditFallbackReason.unknownSuccessfulControl,
        );
      }
    }

    return PostEditNativeSupported(profileVersion: profileVersion);
  }

  static const Set<String> _allowedExactNames = <String>{
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
  };

  bool _isAllowedField(String name) {
    final lowerName = name.toLowerCase();
    if (_allowedExactNames.contains(lowerName)) {
      return true;
    }
    final match = _attachmentFieldPattern.firstMatch(name);
    if (match == null) {
      return false;
    }
    final key = match.group(2)!.replaceAll("'", '').replaceAll('"', '');
    return const <String>{'description', 'readperm', 'price'}.contains(key);
  }

  bool _isUnsafeTextMode(PostEditFormField field) {
    final name = field.name.toLowerCase();
    final value = field.value.trim();
    return (name == 'htmlon' || name == 'bbcodeoff' || name == 'imgcontent') &&
        value == '1';
  }

  bool _isSpecialField(String name, String value) {
    return (name == 'special' && value.trim() != '0') ||
        name == 'specialextra' ||
        name.startsWith('poll') ||
        name.startsWith('trade') ||
        name.startsWith('reward') ||
        name.startsWith('activity') ||
        name.startsWith('debate') ||
        name.startsWith('rushreply') ||
        name.startsWith('replycredit') ||
        name.startsWith('cronpublish');
  }

  bool _isSortField(String name, String value) {
    return (name == 'sortid' && value.trim() != '0') ||
        name.startsWith('typeoption[');
  }

  bool _isPluginField(String name) {
    return name.contains('plugin') || name.startsWith('ext_');
  }

  bool _isDestructiveField(String name) {
    return name == 'delete' ||
        name == 'delattachop' ||
        name.startsWith('delete[') ||
        name.startsWith('delattachop[');
  }

  static final RegExp _attachmentFieldPattern = RegExp(
    r'^(attachnew|attachupdate)\[[1-9]\d*\]\[([^\]]+)\]$',
  );
}
