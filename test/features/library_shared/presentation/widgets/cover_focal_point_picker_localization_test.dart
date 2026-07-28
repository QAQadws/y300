import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/presentation/widgets/cover_focal_point_picker.dart';
import 'package:y300/l10n/app_localizations_zh.dart';

import '../../../../test_support/localized_test_app.dart';

void main() {
  testWidgets('cover focal picker localizes its Traditional Chinese chrome', (
    tester,
  ) async {
    final l10n = AppLocalizationsZhTw();
    await tester.pumpWidget(
      LocalizedTestApp(
        locale: const Locale('zh', 'TW'),
        home: CoverFocalPointPicker(
          image: MemoryImage(Uint8List.fromList(const <int>[0])),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text(l10n.libraryCoverFocalTitle), findsOneWidget);
    expect(find.text(l10n.libraryCoverFocalHelp), findsOneWidget);
    expect(find.text(l10n.libraryCoverCenter), findsOneWidget);
    expect(find.text(l10n.commonCancel), findsOneWidget);
    expect(find.text(l10n.commonConfirm), findsOneWidget);
    expect(find.text(l10n.libraryCoverImageLoadFailed), findsOneWidget);
  });

  testWidgets('cover focal picker preserves an explicit title override', (
    tester,
  ) async {
    const rawTitle = 'Raw Cover 标题';
    await tester.pumpWidget(
      LocalizedTestApp(
        home: CoverFocalPointPicker(
          image: MemoryImage(Uint8List.fromList(const <int>[0])),
          title: rawTitle,
        ),
      ),
    );
    await tester.pump();

    expect(find.text(rawTitle), findsOneWidget);
  });
}
