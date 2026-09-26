import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/more/presentation/more_account_avatar.dart';
import 'package:y300/features/profile/presentation/current_account_avatar_controller.dart';
import 'package:y300/shared/widgets/forum_default_avatar.dart';

final _source = StateProvider<CurrentAccountAvatarState>(
  (_) => const CurrentAccountAvatarState(uid: '42'),
);

void main() {
  testWidgets(
    'cached frame is immediate, changed frame fades, invalid identity clears it',
    (tester) async {
      late Directory directory;
      late String firstPath;
      late String secondPath;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp(
          'account_avatar_widget_test',
        );
        firstPath = await _image(directory, 'first', Colors.red);
        secondPath = await _image(directory, 'second', Colors.blue);
      });
      addTearDown(() => directory.delete(recursive: true));
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final preloadContext = tester.element(find.byType(SizedBox).first);
      await tester.runAsync(() async {
        await precacheImage(FileImage(File(firstPath)), preloadContext);
        await precacheImage(FileImage(File(secondPath)), preloadContext);
      });
      final container = ProviderContainer(
        overrides: [
          currentAccountAvatarControllerProvider.overrideWith(_Controller.new),
        ],
      );
      addTearDown(container.dispose);
      container.read(_source.notifier).state = CurrentAccountAvatarState(
        uid: '42',
        localPath: firstPath,
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: MoreAccountAvatar(uid: '42', size: 72)),
          ),
        ),
      );
      await _decode(tester);
      expect(_imagePath(tester), firstPath);
      expect(
        tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher)).duration,
        Duration.zero,
      );
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Image && widget.image is AssetImage,
        ),
        findsNothing,
      );

      container.read(_source.notifier).state = CurrentAccountAvatarState(
        uid: '42',
        localPath: secondPath,
        animate: true,
      );
      await tester.pump();
      expect(_imagePath(tester), firstPath);
      await _decode(tester, settle: false);
      expect(
        tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher)).duration,
        const Duration(milliseconds: 300),
      );
      await tester.pumpAndSettle();
      expect(_imagePath(tester), secondPath);
      final imageElement = tester.element(find.byType(Image));
      container.read(_source.notifier).state = CurrentAccountAvatarState(
        uid: '42',
        localPath: secondPath,
        animate: true,
      );
      await tester.pump();
      expect(tester.element(find.byType(Image)), same(imageElement));

      container.read(_source.notifier).state =
          const CurrentAccountAvatarState();
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      expect(find.byKey(const Key('forum-avatar-placeholder')), findsOneWidget);
    },
  );

  testWidgets(
    'pending first avatar stays neutral; confirmed default uses the asset',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          currentAccountAvatarControllerProvider.overrideWith(_Controller.new),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: MoreAccountAvatar(uid: '42', size: 72),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      container.read(_source.notifier).state = const CurrentAccountAvatarState(
        uid: '42',
        useDefault: true,
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<Image>(find.byType(Image)).image,
        isA<AssetImage>().having(
          (image) => image.assetName,
          'asset',
          forumDefaultAvatarAsset,
        ),
      );
    },
  );
}

class _Controller extends CurrentAccountAvatarController {
  @override
  CurrentAccountAvatarState build() => ref.watch(_source);
}

Future<void> _decode(WidgetTester tester, {bool settle = true}) async {
  await tester.pump();
  if (settle) await tester.pumpAndSettle();
}

String _imagePath(WidgetTester tester) =>
    (tester.widget<Image>(find.byType(Image)).image as FileImage).file.path;

Future<String> _image(Directory directory, String name, Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(
    recorder,
  ).drawRect(const Rect.fromLTWH(0, 0, 2, 2), Paint()..color = color);
  final picture = recorder.endRecording();
  final image = await picture.toImage(2, 2);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('${directory.path}/$name.png');
  await file.writeAsBytes(data!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
  return file.path;
}
