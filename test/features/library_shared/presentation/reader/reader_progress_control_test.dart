import 'package:flutter/material.dart';
import '../../../../test_support/localized_test_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';

void main() {
  testWidgets('ReaderProgressControl renders current and total labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildProgress(
        config: ReaderProgressConfig(
          current: 3,
          total: 12,
          onChanged: (_) {},
          onChangeEnd: (_) {},
        ),
      ),
    );

    expect(find.text('3'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('single digit labels use compact symmetric slots', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildProgress(
        config: ReaderProgressConfig(
          current: 1,
          total: 9,
          onChanged: (_) {},
          onChangeEnd: (_) {},
        ),
      ),
    );

    final currentWidth = tester
        .getSize(find.byKey(const Key('shared-reader-current-label-slot')))
        .width;
    final totalWidth = tester
        .getSize(find.byKey(const Key('shared-reader-total-label-slot')))
        .width;

    expect(currentWidth, lessThan(24));
    expect(totalWidth, currentWidth);
  });

  testWidgets('the longest label keeps the slider geometry stable', (
    tester,
  ) async {
    Widget buildForCurrent(int current) {
      return _buildProgress(
        config: ReaderProgressConfig(
          current: current,
          total: 100,
          onChanged: (_) {},
          onChangeEnd: (_) {},
        ),
      );
    }

    await tester.pumpWidget(buildForCurrent(9));
    final before = tester.getRect(
      find.byKey(const Key('shared-reader-progress-slider')),
    );

    await tester.pumpWidget(buildForCurrent(10));
    final after = tester.getRect(
      find.byKey(const Key('shared-reader-progress-slider')),
    );

    expect(after.left, before.left);
    expect(after.right, before.right);
  });

  testWidgets('ReaderProgressControl emits slider callbacks', (tester) async {
    final events = <String>[];
    await tester.pumpWidget(
      _buildProgress(
        config: ReaderProgressConfig(
          current: 1,
          total: 5,
          onChangeStart: (value) => events.add('start'),
          onChanged: (value) => events.add('change'),
          onChangeEnd: (value) => events.add('end'),
        ),
      ),
    );

    final center = tester.getCenter(
      find.byKey(const Key('shared-reader-progress-slider')),
    );
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(80, 0));
    await gesture.up();
    await tester.pump();

    expect(events, containsAllInOrder(['start', 'change', 'end']));
  });

  testWidgets('continuous progress has custom labels and no divisions', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildProgress(
        config: ReaderProgressConfig.continuous(
          value: 0.42,
          leadingLabel: '42%',
          trailingLabel: '100%',
          onChanged: (_) {},
          onChangeEnd: (_) {},
        ),
      ),
    );

    final slider = tester.widget<Slider>(
      find.byKey(const Key('shared-reader-progress-slider')),
    );
    expect(slider.value, 0.42);
    expect(slider.divisions, isNull);
    expect(find.text('42%'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const Key('shared-reader-current-label-slot')))
          .width,
      tester
          .getSize(find.byKey(const Key('shared-reader-total-label-slot')))
          .width,
    );
  });

  testWidgets('narrow large-text layout preserves usable slider width', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildProgress(
        width: 220,
        textScaler: const TextScaler.linear(2),
        config: ReaderProgressConfig.discrete(
          current: 8,
          total: 100,
          leadingLabel: '88%',
          trailingLabel: '计算中',
          onChanged: (_) {},
          onChangeEnd: (_) {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester
          .getSize(find.byKey(const Key('shared-reader-progress-slider')))
          .width,
      greaterThanOrEqualTo(96),
    );
    final current = tester.widget<Text>(
      find.byKey(const Key('shared-reader-current-label')),
    );
    final total = tester.widget<Text>(
      find.byKey(const Key('shared-reader-total-label')),
    );
    expect(current.maxLines, 1);
    expect(total.maxLines, 1);
    expect(current.overflow, TextOverflow.ellipsis);
    expect(total.overflow, TextOverflow.ellipsis);
  });

  testWidgets('discrete progress derives page divisions', (tester) async {
    await tester.pumpWidget(
      _buildProgress(
        config: ReaderProgressConfig.discrete(
          current: 3,
          total: 8,
          onChanged: (_) {},
          onChangeEnd: (_) {},
        ),
      ),
    );

    final slider = tester.widget<Slider>(
      find.byKey(const Key('shared-reader-progress-slider')),
    );
    expect(slider.value, 2);
    expect(slider.divisions, 7);
  });

  testWidgets(
    'locked ReaderProgressControl preserves the enabled slider style',
    (tester) async {
      await tester.pumpWidget(
        _buildProgress(
          config: ReaderProgressConfig(
            current: 2,
            total: 5,
            interactionLocked: true,
            onChanged: (_) {},
            onChangeEnd: (_) {},
          ),
        ),
      );

      final slider = tester.widget<Slider>(
        find.byKey(const Key('shared-reader-progress-slider')),
      );
      expect(slider.onChanged, isNotNull);
    },
  );

  testWidgets('ReaderProgressControl disables previous and next buttons', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildProgress(
        config: ReaderProgressConfig(
          current: 1,
          total: 5,
          previousEnabled: false,
          nextEnabled: false,
          onPrevious: () {},
          onNext: () {},
          onChanged: (_) {},
          onChangeEnd: (_) {},
        ),
      ),
    );

    final previous = tester.widget<IconButton>(
      find.byKey(const Key('shared-reader-prev-button')),
    );
    final next = tester.widget<IconButton>(
      find.byKey(const Key('shared-reader-next-button')),
    );

    expect(previous.onPressed, isNull);
    expect(next.onPressed, isNull);
  });

  testWidgets('ReaderProgressControl supports custom button icons', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildProgress(
        config: ReaderProgressConfig(
          current: 1,
          total: 5,
          previousIcon: Icons.arrow_back,
          nextIcon: Icons.downloading_outlined,
          onChanged: (_) {},
          onChangeEnd: (_) {},
        ),
      ),
    );

    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.byIcon(Icons.downloading_outlined), findsOneWidget);
  });

  testWidgets('ReaderProgressControl clamps non-positive total to one', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildProgress(
        config: ReaderProgressConfig(
          current: 8,
          total: 0,
          onChanged: (_) {},
          onChangeEnd: (_) {},
        ),
      ),
    );

    final current = tester.widget<Text>(
      find.byKey(const Key('shared-reader-current-label')),
    );
    final total = tester.widget<Text>(
      find.byKey(const Key('shared-reader-total-label')),
    );

    expect(current.data, '1');
    expect(total.data, '1');
  });

  testWidgets('ReaderProgressControl uses reader chrome progress track color', (
    tester,
  ) async {
    final theme = AppTheme.dark();
    final palette = const ReaderChromePaletteResolver().resolve(theme);

    await tester.pumpWidget(
      _buildProgress(
        theme: theme,
        config: ReaderProgressConfig(
          current: 1,
          total: 5,
          onChanged: (_) {},
          onChangeEnd: (_) {},
        ),
      ),
    );

    final track = tester.widget<DecoratedBox>(
      find
          .ancestor(
            of: find.byKey(const Key('shared-reader-progress-slider')),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final decoration = track.decoration as BoxDecoration;

    expect(decoration.color, palette.progressTrackBackground);
  });
}

Widget _buildProgress({
  required ReaderProgressConfig config,
  ThemeData? theme,
  double? width,
  TextScaler? textScaler,
}) {
  return LocalizedTestApp(
    theme: theme,
    builder: textScaler == null
        ? null
        : (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          ),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: ReaderProgressControl(config: config),
        ),
      ),
    ),
  );
}
