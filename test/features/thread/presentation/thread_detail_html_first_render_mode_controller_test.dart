import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/thread/data/repositories/thread_detail_html_first_render_mode_repository.dart';
import 'package:y300/features/thread/domain/models/thread_detail_html_first_render_mode.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('SharedPrefsThreadDetailHtmlFirstRenderModeRepository', () {
    test('loads legacy by default', () async {
      const repository = SharedPrefsThreadDetailHtmlFirstRenderModeRepository();

      final mode = await repository.load();

      expect(mode, ThreadDetailHtmlFirstRenderMode.legacy);
    });

    test('persists html-first render mode', () async {
      const repository = SharedPrefsThreadDetailHtmlFirstRenderModeRepository();

      await repository.save(ThreadDetailHtmlFirstRenderMode.htmlFirst);

      expect(
        await repository.load(),
        ThreadDetailHtmlFirstRenderMode.htmlFirst,
      );
    });
  });
}
