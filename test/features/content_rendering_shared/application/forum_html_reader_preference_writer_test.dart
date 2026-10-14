import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/application/forum_html_reader_preference_writer.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

void main() {
  test('saves serialize and replace only the pending snapshot', () async {
    final repository = _Repository();
    final writer = ForumHtmlReaderPreferenceWriter(repository);
    final initial = await writer.load();
    final first = _font(initial, 1.2);
    final middle = _font(initial, 1.4);
    final latest = _font(initial, 1.8).copyWith(preserveAuthorFontSize: false);
    final a = writer.save(first);
    final b = writer.save(middle);
    final c = writer.save(latest);
    expect(repository.calls, [first]);
    repository.complete();
    await a;
    expect(repository.calls, [first, latest]);
    repository.complete();
    await Future.wait([b, c]);
    expect(repository.peak, 1);
    expect(repository.current, latest);
  });

  test(
    'returning to the loaded baseline still follows an active different save',
    () async {
      final repository = _Repository();
      final writer = ForumHtmlReaderPreferenceWriter(repository);
      final initial = await writer.load();
      final a = writer.save(_font(initial, 1.8));
      final b = writer.save(initial);
      repository.complete();
      await a;
      expect(repository.calls, [_font(initial, 1.8), initial]);
      repository.complete();
      await b;
      expect(repository.current, initial);
    },
  );

  test(
    'partial failure invalidates equality skipping and does not strand newer writes',
    () async {
      final repository = _Repository();
      final writer = ForumHtmlReaderPreferenceWriter(repository);
      final initial = await writer.load();
      final a = writer.save(_font(initial, 1.4));
      final failure = expectLater(a, throwsStateError);
      final b = writer.save(initial);
      repository.complete(error: StateError('partial write'));
      await failure;
      expect(repository.calls, [_font(initial, 1.4), initial]);
      repository.complete();
      await b;
      expect(writer.lastSuccessful, initial);
      await writer.save(initial);
      expect(repository.calls, hasLength(2));
    },
  );

  test(
    'a slow load cannot confirm an older snapshot after a newer save',
    () async {
      final repository = _Repository();
      final writer = ForumHtmlReaderPreferenceWriter(repository);
      final initial = repository.current;
      repository.loadCompletion = Completer<ForumHtmlReaderPreferences>();
      final load = writer.load();
      await Future<void>.delayed(Duration.zero);
      final changed = _font(initial, 1.7);
      final saving = writer.save(changed);
      expect(repository.calls, isEmpty);
      repository.loadCompletion!.complete(initial);
      expect(await load, initial);
      repository.complete();
      await saving;
      expect(writer.lastSuccessful, changed);
      final restoring = writer.save(initial);
      expect(repository.calls, [changed, initial]);
      repository.complete();
      await restoring;
      expect(repository.current, initial);
    },
  );

  test(
    'reload waits for an active save before reading durable preferences',
    () async {
      final repository = _Repository();
      final writer = ForumHtmlReaderPreferenceWriter(repository);
      final initial = await writer.load();
      final changed = _font(initial, 1.7);
      final save = writer.save(changed);
      final reload = writer.load();
      expect(repository.loads, 1);
      repository.complete();
      await save;
      expect(await reload, changed);
      expect(repository.loads, 2);
    },
  );
}

ForumHtmlReaderPreferences _font(
  ForumHtmlReaderPreferences value,
  double scale,
) => value.copyWith(typography: value.typography.copyWith(fontScale: scale));

class _Repository implements ForumHtmlReaderPreferencesRepository {
  ForumHtmlReaderPreferences current = ForumHtmlReaderPreferences.defaults();
  final calls = <ForumHtmlReaderPreferences>[];
  final pending = <Completer<void>>[];
  int active = 0;
  int peak = 0;
  int loads = 0;
  Completer<ForumHtmlReaderPreferences>? loadCompletion;
  @override
  Future<ForumHtmlReaderPreferences> load() async {
    loads++;
    return loadCompletion?.future ?? current;
  }

  @override
  Future<void> save(ForumHtmlReaderPreferences value) async {
    active++;
    if (active > peak) peak = active;
    calls.add(value);
    final completer = Completer<void>();
    pending.add(completer);
    try {
      await completer.future;
      current = value;
    } finally {
      active--;
    }
  }

  void complete({Object? error}) {
    final completer = pending.removeAt(0);
    if (error == null) {
      completer.complete();
    } else {
      completer.completeError(error);
    }
  }
}
