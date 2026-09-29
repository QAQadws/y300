import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:flutter/foundation.dart';
import 'package:y300/features/composer_shared/data/services/composer_image_picker.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

/// Transient album-upload progress for one native blog editor route.
final class BlogEditorMediaState {
  const BlogEditorMediaState({
    this.busy = false,
    this.current = 0,
    this.total = 0,
    this.progress = 0,
    this.failure,
    this.outcomeUnknown = false,
  });

  final bool busy;
  final int current;
  final int total;
  final double progress;
  final DataCommandFailure? failure;
  final bool outcomeUnknown;
}

/// Reuses local image picking without treating album pictures as forum aids.
/// Selected files are borrowed for preview; the controller never deletes them.
final class BlogEditorMediaController
    extends ValueNotifier<BlogEditorMediaState> {
  BlogEditorMediaController({
    required ComposerImagePicker picker,
    required UserBlogMediaOperations service,
    required UserBlogEditorPreparation? Function() preparation,
    required String? Function() currentActor,
    required bool Function() isSessionCurrent,
    required void Function(UserBlogUploadedImage image, String localPath)
    onUploaded,
    FileSystem fileSystem = const LocalFileSystem(),
  }) : _picker = picker,
       _service = service,
       _preparation = preparation,
       _currentActor = currentActor,
       _isSessionCurrent = isSessionCurrent,
       _onUploaded = onUploaded,
       _fileSystem = fileSystem,
       super(const BlogEditorMediaState());

  final ComposerImagePicker _picker;
  final UserBlogMediaOperations _service;
  final UserBlogEditorPreparation? Function() _preparation;
  final String? Function() _currentActor;
  final bool Function() _isSessionCurrent;
  final void Function(UserBlogUploadedImage image, String localPath)
  _onUploaded;
  final FileSystem _fileSystem;
  final List<UserBlogUploadedImage> _uploadedImages = [];
  final Map<String, String> _previewPaths = {};
  ForumRequestCancellation? _cancellation;
  int _generation = 0;
  bool _disposed = false;
  bool _expired = false;

  List<UserBlogUploadedImage> get uploadedImages =>
      List.unmodifiable(_uploadedImages);
  Map<String, String> get previewPaths => Map.unmodifiable(_previewPaths);

  Future<void> pickImages() async {
    if (_disposed || _expired || value.busy) return;
    final prepared = _preparation();
    if (prepared == null || prepared.imageUploadLimits == null) return;
    if (!_checkSession(prepared)) return;
    final generation = ++_generation;
    final cancellation = _cancellation = ForumRequestCancellation();
    value = const BlogEditorMediaState(busy: true);
    try {
      final picked = await _picker.pickImagesInOrder();
      if (!_accept(generation, cancellation, prepared)) return;
      final images = picked.toList(growable: false)
        ..sort((a, b) => a.originalIndex.compareTo(b.originalIndex));
      for (var index = 0; index < images.length; index++) {
        final image = images[index];
        if (!_accept(generation, cancellation, prepared)) return;
        value = BlogEditorMediaState(
          busy: true,
          current: index + 1,
          total: images.length,
        );
        final file = _fileSystem.file(image.path);
        final exists = await file.exists();
        if (!_accept(generation, cancellation, prepared)) return;
        if (!exists) {
          _fail(_fileMissing);
          return;
        }
        final contentLength = await file.length();
        if (!_accept(generation, cancellation, prepared)) return;
        if (contentLength == 0) {
          _fail(_emptyFile);
          return;
        }
        final result = await _service.uploadImage(
          UserBlogImageUploadSubmission(
            preparation: prepared,
            actorUserId: prepared.target.actorUserId,
            content: ForumImageAttachmentContent(
              fileName: image.fileName,
              mimeType: image.mimeType,
              contentLength: contentLength,
              openRead: file.openRead,
            ),
            cancellation: cancellation,
            onProgress: (progress) {
              if (!_accept(generation, cancellation, prepared)) return;
              value = BlogEditorMediaState(
                busy: true,
                current: index + 1,
                total: images.length,
                progress: progress.isFinite
                    ? progress.clamp(0, 1).toDouble()
                    : 0,
              );
            },
          ),
        );
        if (!_accept(generation, cancellation, prepared)) return;
        if (result case DataCommandApplied(:final receipt)) {
          _uploadedImages.add(receipt);
          _previewPaths[receipt.imageUri.toString()] = image.path;
          _onUploaded(receipt, image.path);
          if (!_accept(generation, cancellation, prepared)) return;
          value = BlogEditorMediaState(
            busy: true,
            current: index + 1,
            total: images.length,
            progress: 1,
          );
        } else {
          // Stop this batch, including unknown outcomes. A fresh user selection
          // is a separate operation; no failed upload is queued for replay.
          _fail(
            result.failureOrNull!,
            outcomeUnknown: result is DataCommandOutcomeUnknown,
          );
          return;
        }
      }
    } on ComposerImagePickerException {
      if (_accept(generation, cancellation, prepared)) _fail(_pickerFailed);
    } catch (_) {
      if (_accept(generation, cancellation, prepared)) {
        _fail(_uploadUnknown, outcomeUnknown: true);
      }
    } finally {
      if (!_disposed && generation == _generation) {
        _cancellation = null;
        value = BlogEditorMediaState(
          current: value.current,
          total: value.total,
          progress: value.progress,
          failure: value.failure,
          outcomeUnknown: value.outcomeUnknown,
        );
      }
    }
  }

  bool _checkSession(UserBlogEditorPreparation prepared) {
    if (_isSessionCurrent() && _currentActor() == prepared.target.actorUserId) {
      return true;
    }
    expire();
    return false;
  }

  bool _accept(
    int generation,
    ForumRequestCancellation cancellation,
    UserBlogEditorPreparation prepared,
  ) =>
      !_disposed &&
      !_expired &&
      generation == _generation &&
      !cancellation.isCancelled &&
      _checkSession(prepared) &&
      identical(_preparation(), prepared);

  void _fail(DataCommandFailure failure, {bool outcomeUnknown = false}) {
    value = BlogEditorMediaState(
      current: value.current,
      total: value.total,
      progress: value.progress,
      failure: failure,
      outcomeUnknown: outcomeUnknown,
    );
  }

  /// Stops pending work while retaining already confirmed uploads.
  void cancel() {
    if (_disposed) return;
    ++_generation;
    _cancellation?.cancel();
    _cancellation = null;
    value = const BlogEditorMediaState();
  }

  /// Invalidates the old account's editor and releases its transient previews.
  void expire() {
    if (_disposed || _expired) return;
    _expired = true;
    _uploadedImages.clear();
    _previewPaths.clear();
    cancel();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _cancellation?.cancel();
    _cancellation = null;
    _uploadedImages.clear();
    _previewPaths.clear();
    super.dispose();
  }
}

const _pickerFailed = DataCommandFailure(
  kind: DataCommandFailureKind.unknown,
  retryPolicy: DataCommandRetryPolicy.explicitOnly,
  code: 'blog_image_picker_failed',
  diagnosticMessage: 'blog_image_picker_failed',
);
const _fileMissing = DataCommandFailure(
  kind: DataCommandFailureKind.validation,
  retryPolicy: DataCommandRetryPolicy.afterInputChange,
  code: 'blog_image_file_missing',
  diagnosticMessage: 'blog_image_file_missing',
);
const _emptyFile = DataCommandFailure(
  kind: DataCommandFailureKind.validation,
  retryPolicy: DataCommandRetryPolicy.afterInputChange,
  code: 'blog_image_file_empty',
  diagnosticMessage: 'blog_image_file_empty',
);
const _uploadUnknown = DataCommandFailure(
  kind: DataCommandFailureKind.unknown,
  retryPolicy: DataCommandRetryPolicy.never,
  code: 'blog_image_upload_unknown',
  diagnosticMessage: 'blog_image_upload_unknown',
);
