import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_diagnostics.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';

void main() {
  const event = TextConversionDiagnosticEvent(
    surface: TextConversionSurface.threadDetail,
    mode: TextConversionMode.toTraditional,
    converterId: 'opencc:s2t',
    sourceRevision: 'https://bbs.yamibo.com/thread?formhash=secret 正文 alice',
    plainSourceCount: 12,
    htmlFragmentCount: 4,
    convertedTextNodeCount: 18,
    elapsedMs: 27,
    cacheHit: true,
    usedIndividualFallback: false,
    failureType: 'StateError',
  );

  test('safe log fields contain metrics but no source or credentials', () {
    final fields = event.toSafeLogFields();

    expect(fields, contains('surface=threadDetail'));
    expect(fields, contains('mode=toTraditional'));
    expect(fields, contains('converter=opencc:s2t'));
    expect(fields, contains('plain=12'));
    expect(fields, contains('html=4'));
    expect(fields, contains('nodes=18'));
    expect(fields, contains('elapsedMs=27'));
    expect(fields, contains('cacheHit=true'));
    expect(fields, contains('failure=StateError'));
    expect(fields, isNot(contains('https://')));
    expect(fields, isNot(contains('formhash')));
    expect(fields, isNot(contains('secret')));
    expect(fields, isNot(contains('正文')));
    expect(fields, isNot(contains('alice')));
    expect(fields, matches(RegExp(r'revision=[0-9a-f]{16}')));
  });

  test('debug factory records safe fields and release factory is noop', () {
    final logs = <String>[];
    final debugRecorder = createTextConversionDiagnosticRecorder(
      isDebugMode: true,
      writeLog: logs.add,
    );
    final releaseRecorder = createTextConversionDiagnosticRecorder(
      isDebugMode: false,
      writeLog: logs.add,
    );

    expect(debugRecorder, isA<DeveloperTextConversionDiagnosticRecorder>());
    expect(releaseRecorder, isA<NoopTextConversionDiagnosticRecorder>());

    debugRecorder.record(event);
    releaseRecorder.record(event);

    expect(logs, hasLength(1));
    expect(logs.single, event.toSafeLogFields());
  });

  test('developer recorder swallows logging failures', () {
    final recorder = DeveloperTextConversionDiagnosticRecorder(
      writeLog: (_) => throw StateError('logger unavailable'),
    );

    expect(() => recorder.record(event), returnsNormally);
  });
}
