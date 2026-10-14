import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/application/forum_html_typography_preview.dart';
import 'package:y300/features/content_rendering_shared/domain/models/forum_html_reader_preferences.dart';

void main() {
  test(
    'a burst previews its first and latest values and saves only the final draft',
    () {
      fakeAsync((clock) {
        final initial = ForumHtmlReaderPreferences.defaults().typography;
        final previews = <double>[];
        final saves = <double>[];
        final session = ForumHtmlTypographyPreview(
          initialValue: initial,
          preview: (value) => previews.add(value.fontScale),
          commit: (value) async => saves.add(value.fontScale),
          onError: (error, stack) => fail('$error'),
        );
        session.change(initial.copyWith(fontScale: 1.2));
        clock.elapse(const Duration(milliseconds: 20));
        session.change(initial.copyWith(fontScale: 1.4));
        session.change(initial.copyWith(fontScale: 1.8));
        expect(previews, [1.2]);
        expect(session.value.fontScale, 1.8);
        clock.elapse(const Duration(milliseconds: 70));
        expect(previews, [1.2, 1.8]);
        expect(saves, isEmpty);
        session.flush();
        clock.flushMicrotasks();
        expect(saves, [1.8]);
        clock.elapse(const Duration(seconds: 1));
        expect(saves, [1.8]);
        session.cancel();
      });
    },
  );

  test(
    'closing commits a pending draft after disposal and cancellation retires it',
    () {
      fakeAsync((clock) {
        final initial = ForumHtmlReaderPreferences.defaults().typography;
        final previews = <double>[];
        final saves = <double>[];
        ForumHtmlTypographyPreview create() => ForumHtmlTypographyPreview(
          initialValue: initial,
          preview: (value) => previews.add(value.fontScale),
          commit: (value) async => saves.add(value.fontScale),
          onError: (error, stack) => fail('$error'),
        );
        final closing = create();
        closing.change(initial.copyWith(fontScale: 1.3));
        closing.change(initial.copyWith(fontScale: 1.7));
        closing.close();
        expect(saves, isEmpty);
        clock.flushMicrotasks();
        expect(previews, [1.3, 1.7]);
        expect(saves, [1.7]);
        final retired = create();
        retired.change(initial.copyWith(fontScale: 1.4));
        retired.change(initial.copyWith(fontScale: 1.9));
        retired.close();
        retired.cancel();
        clock.elapse(const Duration(seconds: 1));
        clock.flushMicrotasks();
        expect(previews, [1.3, 1.7, 1.4]);
        expect(saves, [1.7]);
      });
    },
  );

  test(
    'quiet keyboard or accessibility changes are persisted without a drag end',
    () {
      fakeAsync((clock) {
        final initial = ForumHtmlReaderPreferences.defaults().typography;
        final saves = <double>[];
        final session = ForumHtmlTypographyPreview(
          initialValue: initial,
          preview: (_) {},
          commit: (value) async => saves.add(value.lineHeightScale),
          onError: (error, stack) => fail('$error'),
        );
        session.change(initial.copyWith(lineHeightScale: 1.9));
        clock.elapse(const Duration(milliseconds: 520));
        clock.flushMicrotasks();
        expect(saves, [1.9]);
        session.cancel();
      });
    },
  );
}
