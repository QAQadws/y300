import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:y300/features/reply/data/reply_image_picker.dart';

void main() {
  group('ImagePickerReplyImagePicker', () {
    test('keeps image picker order on Android and assigns originalIndex', () async {
      final picker = ImagePickerReplyImagePicker(
        platform: TargetPlatform.android,
        pickMultiImage: () async {
          return [
            XFile('/gallery/first.jpg', mimeType: 'image/jpeg'),
            XFile('/gallery/second.png', mimeType: 'image/png'),
          ];
        },
      );

      final images = await picker.pickImagesInOrder();

      expect(images.map((image) => image.path), [
        '/gallery/first.jpg',
        '/gallery/second.png',
      ]);
      expect(images.map((image) => image.originalIndex), [0, 1]);
      expect(images.map((image) => image.mimeType), ['image/jpeg', 'image/png']);
    });

    test('returns empty list when picker is cancelled', () async {
      final picker = ImagePickerReplyImagePicker(
        platform: TargetPlatform.iOS,
        pickMultiImage: () async => const <XFile>[],
      );

      expect(await picker.pickImagesInOrder(), isEmpty);
    });

    test('infers mime type from extension when image picker has no mime', () async {
      final picker = ImagePickerReplyImagePicker(
        platform: TargetPlatform.android,
        pickMultiImage: () async => [XFile('/gallery/photo.gif')],
      );

      final images = await picker.pickImagesInOrder();

      expect(images.single.mimeType, 'image/gif');
      expect(images.single.fileName, 'photo.gif');
    });

    test('uses file picker fallback on desktop platforms', () async {
      final picker = ImagePickerReplyImagePicker(
        platform: TargetPlatform.windows,
        pickImageFiles: () async {
          return FilePickerResult([
            PlatformFile(name: 'first.jpg', size: 1, path: 'C:/first.jpg'),
            PlatformFile(name: 'second.png', size: 1, path: 'C:/second.png'),
          ]);
        },
      );

      final images = await picker.pickImagesInOrder();

      expect(images.map((image) => image.fileName), ['first.jpg', 'second.png']);
      expect(images.map((image) => image.originalIndex), [0, 1]);
    });

    test('wraps picker errors', () async {
      final picker = ImagePickerReplyImagePicker(
        platform: TargetPlatform.android,
        pickMultiImage: () async => throw StateError('boom'),
      );

      expect(
        picker.pickImagesInOrder(),
        throwsA(isA<ReplyImagePickerException>()),
      );
    });
  });
}
