import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/shared/widgets/shelf/shelf_cover_image.dart';

void main() {
  testWidgets('ShelfCoverImage keeps remote-only covers as placeholder', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ShelfCoverImage(
          coverKey: 'cover-1',
          remoteUrl: 'https://img.test/cover.jpg',
          fit: BoxFit.cover,
          placeholder: SizedBox(key: Key('placeholder')),
        ),
      ),
    );

    expect(find.byKey(const Key('placeholder')), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('ShelfCoverImage uses FileImage with gapless playback for local covers', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ShelfCoverImage(
          coverKey: 'cover-1',
          // The widget can be verified from the Image provider itself. Using a
          // synthetic path avoids starting real image decoding in widget tests,
          // which can hold file handles open on Windows runners.
          localPath: 'E:/synthetic/shelf-cover.jpg',
          fit: BoxFit.cover,
          placeholder: SizedBox(key: Key('placeholder')),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<FileImage>());
    expect(image.gaplessPlayback, isTrue);
    expect(find.byKey(const Key('placeholder')), findsNothing);
  });
}
