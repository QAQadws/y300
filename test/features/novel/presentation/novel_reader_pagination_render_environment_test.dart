import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_render_environment.dart';

void main() {
  testWidgets('restores local reader inheritance outside its original host', (
    tester,
  ) async {
    late NovelReaderPaginationRenderEnvironment environment;
    const requested = TextStyle(
      fontSize: 20,
      fontFamily: 'serif',
      fontWeight: FontWeight.w700,
    );
    await tester.pumpWidget(
      _captureApp(
        onCapture: (value) => environment = value,
        style: requested,
        alignment: TextAlign.center,
        direction: TextDirection.rtl,
        scaler: const _NonlinearTestScaler(),
      ),
    );

    late BuildContext wrappedContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(scaffoldBackgroundColor: Colors.red),
        home: Scaffold(
          body: environment.wrap(
            Builder(
              builder: (context) {
                wrappedContext = context;
                return const Text('reader layout');
              },
            ),
          ),
        ),
      ),
    );

    final inherited = DefaultTextStyle.of(wrappedContext);
    expect(inherited.style.fontSize, 20);
    expect(inherited.style.fontFamily, 'serif');
    expect(inherited.style.fontWeight, FontWeight.w700);
    expect(inherited.style.letterSpacing, 1.25);
    expect(inherited.textAlign, TextAlign.center);
    expect(Directionality.of(wrappedContext), TextDirection.rtl);
    expect(Theme.of(wrappedContext).scaffoldBackgroundColor, Colors.green);
    // The compatibility getter is 1.5 even though its 14px sample is 1.25.
    // Both layout paths preserve fwfh's factor rather than the sample ratio.
    expect(environment.textScaler.scale(28), 42);
    expect(MediaQuery.textScalerOf(wrappedContext).scale(28), 42);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'layout signatures follow resolved style and inherited geometry',
    (tester) async {
      late NovelReaderPaginationRenderEnvironment environment;
      Future<NovelReaderPaginationRenderEnvironment> capture({
        TextStyle style = const TextStyle(fontSize: 20),
        TextAlign alignment = TextAlign.start,
        TextDirection direction = TextDirection.ltr,
        TextScaler scaler = TextScaler.noScaling,
      }) async {
        await tester.pumpWidget(
          _captureApp(
            onCapture: (value) => environment = value,
            style: style,
            alignment: alignment,
            direction: direction,
            scaler: scaler,
          ),
        );
        return environment;
      }

      final initial = await capture();
      final equivalent = await capture();
      expect(equivalent.layoutSignature, initial.layoutSignature);
      expect(equivalent.sessionSignature, initial.sessionSignature);
      final font = await capture(
        style: const TextStyle(
          fontSize: 20,
          fontFamily: 'serif',
          fontWeight: FontWeight.w700,
        ),
      );
      final alignment = await capture(alignment: TextAlign.justify);
      final direction = await capture(direction: TextDirection.rtl);
      final scale = await capture(scaler: const TextScaler.linear(1.4));
      for (final changed in [font, alignment, direction, scale]) {
        expect(changed.layoutSignature, isNot(initial.layoutSignature));
        expect(changed.sessionSignature, isNot(initial.sessionSignature));
      }
    },
  );
}

Widget _captureApp({
  required ValueChanged<NovelReaderPaginationRenderEnvironment> onCapture,
  required TextStyle style,
  required TextAlign alignment,
  required TextDirection direction,
  required TextScaler scaler,
}) => MaterialApp(
  home: Builder(
    builder: (context) => Theme(
      data: ThemeData(scaffoldBackgroundColor: Colors.green),
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: scaler),
        child: Directionality(
          textDirection: direction,
          child: DefaultTextStyle(
            style: const TextStyle(fontSize: 11, letterSpacing: 1.25),
            child: Builder(
              builder: (context) {
                onCapture(
                  NovelReaderPaginationRenderEnvironment.capture(
                    context,
                    textStyle: style,
                    textAlign: alignment,
                  ),
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    ),
  ),
);

final class _NonlinearTestScaler extends TextScaler {
  const _NonlinearTestScaler();

  @override
  double scale(double fontSize) => fontSize == 14 ? 17.5 : fontSize * 1.2;

  @override
  double get textScaleFactor => 1.5;
}
