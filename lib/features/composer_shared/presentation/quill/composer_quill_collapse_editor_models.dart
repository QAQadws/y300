import 'package:flutter/foundation.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_preview_models.dart';

/// Visual collapse budget for one Quill surface.
///
/// Each editor route consumes one level before passing capabilities to its
/// body, so historical deeper embeds stay previewable without edit actions.
final class ComposerQuillCapabilities {
  const ComposerQuillCapabilities({
    required this.remainingEditableCollapseLevels,
  }) : assert(remainingEditableCollapseLevels >= 0);

  static const message = ComposerQuillCapabilities(
    remainingEditableCollapseLevels: 2,
  );

  final int remainingEditableCollapseLevels;

  bool get canCreateCollapse => remainingEditableCollapseLevels > 0;

  bool get canEditCollapse => remainingEditableCollapseLevels > 0;

  ComposerQuillCapabilities get nestedBody {
    if (remainingEditableCollapseLevels == 0) {
      return this;
    }
    return ComposerQuillCapabilities(
      remainingEditableCollapseLevels: remainingEditableCollapseLevels - 1,
    );
  }
}

final class ComposerCollapseDraft {
  const ComposerCollapseDraft({required this.title, required this.bodyBbCode});

  final String title;
  final String bodyBbCode;
}

enum ComposerCollapseCommitStatus { applied, conflict }

final class ComposerCollapseEditorHostSnapshot {
  const ComposerCollapseEditorHostSnapshot({
    required this.enabled,
    required this.documentGeneration,
    required this.isUploadingImages,
    required this.imageUploadCurrent,
    required this.imageUploadTotal,
    required this.imageAttachments,
    required this.attachmentResolver,
  });

  final bool enabled;
  final int documentGeneration;
  final bool isUploadingImages;
  final int imageUploadCurrent;
  final int imageUploadTotal;
  final List<ComposerImageAttachment> imageAttachments;
  final ComposerAttachmentPreviewResolver attachmentResolver;
}

final class ComposerCollapseEditorHostController
    extends ValueNotifier<ComposerCollapseEditorHostSnapshot> {
  ComposerCollapseEditorHostController(super.value);

  bool _active = true;

  bool get isActive => _active;

  void updateSnapshot(ComposerCollapseEditorHostSnapshot snapshot) {
    if (_active) {
      value = snapshot;
    }
  }

  void invalidate() {
    if (!_active) {
      return;
    }
    _active = false;
    notifyListeners();
  }
}
