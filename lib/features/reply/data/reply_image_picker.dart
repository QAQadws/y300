import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:y300/features/reply/domain/models/reply_models.dart';

typedef PickMultiImage = Future<List<XFile>> Function();
typedef PickImageFiles = Future<FilePickerResult?> Function();

abstract class ReplyImagePicker {
  Future<List<ReplyPickedImage>> pickImagesInOrder();
}

class ReplyImagePickerException implements Exception {
  const ReplyImagePickerException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() {
    return 'ReplyImagePickerException($message)';
  }
}

class ImagePickerReplyImagePicker implements ReplyImagePicker {
  ImagePickerReplyImagePicker({
    ImagePicker? imagePicker,
    PickMultiImage? pickMultiImage,
    PickImageFiles? pickImageFiles,
    TargetPlatform? platform,
  })  : _imagePicker = imagePicker ?? ImagePicker(),
        _pickMultiImage = pickMultiImage,
        _pickImageFiles = pickImageFiles,
        _platform = platform;

  final ImagePicker _imagePicker;
  final PickMultiImage? _pickMultiImage;
  final PickImageFiles? _pickImageFiles;
  final TargetPlatform? _platform;

  @override
  Future<List<ReplyPickedImage>> pickImagesInOrder() async {
    try {
      if (_usesSystemImagePicker) {
        final pickMultiImage = _pickMultiImage;
        final files = pickMultiImage == null
            ? await _imagePicker.pickMultiImage()
            : await pickMultiImage();
        return [
          for (var index = 0; index < files.length; index += 1)
            _pickedFromXFile(files[index], index),
        ];
      }

      final pickImageFiles = _pickImageFiles;
      final result = pickImageFiles == null
          ? await FilePicker.pickFiles(
              type: FileType.image,
              allowMultiple: true,
            )
          : await pickImageFiles();
      final files = result?.files ?? const <PlatformFile>[];
      return [
        for (var index = 0; index < files.length; index += 1)
          if (files[index].path != null)
            _pickedFromPlatformFile(files[index], index),
      ];
    } catch (error) {
      throw ReplyImagePickerException('选择图片失败，请重试', error);
    }
  }

  bool get _usesSystemImagePicker {
    final platform = _platform ?? defaultTargetPlatform;
    return platform == TargetPlatform.android || platform == TargetPlatform.iOS;
  }

  ReplyPickedImage _pickedFromXFile(XFile file, int index) {
    return ReplyPickedImage(
      path: file.path,
      fileName: _fileName(file.path),
      mimeType: file.mimeType ?? _mimeType(file.path),
      originalIndex: index,
    );
  }

  ReplyPickedImage _pickedFromPlatformFile(PlatformFile file, int index) {
    final path = file.path!;
    return ReplyPickedImage(
      path: path,
      fileName: file.name.isNotEmpty ? file.name : _fileName(path),
      mimeType: _mimeType(path),
      originalIndex: index,
    );
  }

  String _fileName(String path) {
    final name = p.basename(path);
    return name.isEmpty ? 'image' : name;
  }

  String _mimeType(String path) {
    return lookupMimeType(path) ?? 'application/octet-stream';
  }
}
