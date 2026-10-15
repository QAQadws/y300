import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:y300/features/composer_shared/data/services/composer_image_picker.dart';

void main() {
  group('ImagePickerComposerImagePicker', () {
    test(
      'keeps image picker order on Android and assigns originalIndex',
      () async {
        final picker = ImagePickerComposerImagePicker(
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
        expect(images.map((image) => image.mimeType), [
          'image/jpeg',
          'image/png',
        ]);
      },
    );

    test('returns empty list when picker is cancelled', () async {
      final picker = ImagePickerComposerImagePicker(
        platform: TargetPlatform.iOS,
        pickMultiImage: () async => const <XFile>[],
      );

      expect(await picker.pickImagesInOrder(), isEmpty);
    });

    test(
      'infers mime type from extension when image picker has no mime',
      () async {
        final picker = ImagePickerComposerImagePicker(
          platform: TargetPlatform.android,
          pickMultiImage: () async => [XFile('/gallery/photo.gif')],
        );

        final images = await picker.pickImagesInOrder();

        expect(images.single.mimeType, 'image/gif');
        expect(images.single.fileName, 'photo.gif');
      },
    );

    test('uses file picker fallback on desktop platforms', () async {
      final picker = ImagePickerComposerImagePicker(
        platform: TargetPlatform.windows,
        pickImageFiles: () async {
          return [
            _PickedFile('first.jpg', Uri.file('C:/first.jpg', windows: true)),
            _PickedFile('second.png', Uri.file('C:/second.png', windows: true)),
          ];
        },
      );

      final images = await picker.pickImagesInOrder();

      expect(images.map((image) => image.fileName), [
        'first.jpg',
        'second.png',
      ]);
      expect(images.map((image) => image.originalIndex), [0, 1]);
    });

    test('returns empty list when desktop picker is cancelled', () async {
      final picker = ImagePickerComposerImagePicker(
        platform: TargetPlatform.windows,
        pickImageFiles: () async => const <PlatformFile>[],
      );

      expect(await picker.pickImagesInOrder(), isEmpty);
    });

    test('skips non-local files and preserves selection order', () async {
      final picker = ImagePickerComposerImagePicker(
        platform: TargetPlatform.windows,
        pickImageFiles: () async => [
          _PickedFile('first.jpg', Uri.file('C:/first.jpg', windows: true)),
          _PickedFile('remote.png', Uri.https('example.com', '/remote.png')),
          _PickedFile('third.gif', Uri.file('C:/third.gif', windows: true)),
        ],
      );

      final images = await picker.pickImagesInOrder();

      expect(images.map((image) => image.fileName), ['first.jpg', 'third.gif']);
      expect(images.map((image) => image.originalIndex), [0, 2]);
      expect(images.map((image) => image.mimeType), [
        'image/jpeg',
        'image/gif',
      ]);
    });

    test('wraps picker errors', () async {
      final picker = ImagePickerComposerImagePicker(
        platform: TargetPlatform.android,
        pickMultiImage: () async => throw StateError('boom'),
      );

      expect(
        picker.pickImagesInOrder(),
        throwsA(isA<ComposerImagePickerException>()),
      );
    });
  });
}

final class _PickedFile extends PlatformFile {
  _PickedFile(this.name, this.uri);

  @override
  final String name;

  @override
  final Uri uri;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
