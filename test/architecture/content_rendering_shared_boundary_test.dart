import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_dependency_directives.dart';

const _packageRoot = 'packages/forum_content_renderer/';
const _packageLib = '${_packageRoot}lib/';
const _packageEntry = '${_packageLib}forum_content_renderer.dart';
const _sharedRoot = 'lib/features/content_rendering_shared/';
const _publicEntry = '${_sharedRoot}content_rendering.dart';
const _threadHtmlRoot = 'lib/features/thread/presentation/html_rendering/';
const _retiredThreadEntries = {
  '${_threadHtmlRoot}forum_html_cached_image_widget_factory.dart',
  '${_threadHtmlRoot}forum_html_content_layout.dart',
  '${_threadHtmlRoot}forum_html_content_view.dart',
  '${_threadHtmlRoot}forum_html_fragment_codec.dart',
  '${_threadHtmlRoot}forum_html_image_deduplicator.dart',
  '${_threadHtmlRoot}forum_html_prepared_render_document.dart',
  '${_threadHtmlRoot}forum_html_reader_preferences_provider.dart',
  '${_threadHtmlRoot}forum_html_reader_settings_sheet.dart',
  '${_threadHtmlRoot}forum_html_render_callbacks.dart',
  '${_threadHtmlRoot}forum_html_render_preparer.dart',
  '${_threadHtmlRoot}forum_html_render_theme_factory.dart',
  '${_threadHtmlRoot}forum_html_style_policy.dart',
  '${_threadHtmlRoot}forum_html_text_style_resolver.dart',
  '${_threadHtmlRoot}forum_html_widget_post_renderer.dart',
  '${_threadHtmlRoot}theme/css_author_color_parser.dart',
  '${_threadHtmlRoot}theme/css_inline_style_declarations.dart',
  '${_threadHtmlRoot}theme/forum_html_author_color_style.dart',
  '${_threadHtmlRoot}theme/forum_html_background_tone_resolver.dart',
  '${_threadHtmlRoot}theme/forum_html_color_adaptation_policy.dart',
  '${_threadHtmlRoot}theme/forum_html_resolved_color_state.dart',
  '${_threadHtmlRoot}theme/forum_html_theme_adaptation_result.dart',
  '${_threadHtmlRoot}theme/forum_html_theme_adapter.dart',
  '${_threadHtmlRoot}theme/forum_html_theme_context.dart',
  '${_threadHtmlRoot}widgets/forum_collapse_block.dart',
  'lib/features/thread/presentation/services/thread_post_body_presentation.dart',
  'lib/features/thread/presentation/services/thread_image_viewport_coordinator.dart',
};
const _preparationPolicyFiles = {
  '${_packageLib}src/contracts/forum_html_preparation_image_policy.dart',
  '${_packageLib}src/contracts/forum_html_prepared_image_resource.dart',
  '${_sharedRoot}application/host/forum_cache_html_preparation_image_policy.dart',
  '${_sharedRoot}application/host/cache_forum_html_prepared_image_resource.dart',
};
const _cacheNeutralPreparationFiles = {
  '${_packageLib}src/contracts/forum_html_preparation_image_policy.dart',
  '${_packageLib}src/contracts/forum_html_prepared_image_resource.dart',
  '${_packageLib}src/html_rendering/forum_html_prepared_render_document.dart',
  '${_packageLib}src/html_rendering/forum_html_preparation_pipeline.dart',
  '${_packageLib}src/html_rendering/forum_html_image_deduplicator.dart',
};
const _cacheNeutralDisplayFiles = {
  '${_packageLib}src/contracts/forum_html_image_host.dart',
  '${_packageLib}src/contracts/forum_html_display_image.dart',
  '${_packageLib}src/html_rendering/forum_html_image_widget_factory.dart',
  '${_packageLib}src/html_rendering/forum_html_render_callbacks.dart',
  '${_packageLib}src/services/forum_html_image_viewport_coordinator.dart',
};

void main() {
  test('package exposes one public API and retires helper copies', () {
    expect(
      Directory(_packageLib)
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .map((file) => normalizeDartSourcePath(file.path)),
      [_packageEntry],
    );
    for (final path in [
      'lib/features/reader_shared/domain/rich_text/typography/discuz_font_size_policy.dart',
      'lib/features/reader_shared/presentation/rich_text/color/rich_text_color_contrast.dart',
      'lib/features/reader_shared/presentation/rich_text/color/rich_text_tone_resolver.dart',
      'lib/shared/widgets/forum_collapse_chrome.dart',
    ]) {
      expect(File(path).existsSync(), isFalse, reason: path);
    }
    final entry = File(_packageEntry).readAsStringSync(encoding: utf8);
    expect(entry, isNot(contains('forum_html_image_widget_factory.dart')));
    for (final uri in dartDependencyDirectiveUris(entry)) {
      final path = _target(_packageEntry, uri);
      expect(path, startsWith('${_packageLib}src/'));
      expect(File(path).existsSync(), isTrue, reason: path);
    }
  });

  test('package rejects App, private entry and transport bypasses', () {
    const source = '${_packageLib}src/html_rendering/new_renderer.dart';
    expect(
      _violationTargets(source, '''
import 'package:y300/features/content_rendering_shared/domain/models/forum_html_reader_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:http/http.dart';
import 'dart:io';
import 'dart:ffi';
'''),
      {
        '${_sharedRoot}domain/models/forum_html_reader_preferences.dart',
        'package:flutter_riverpod/flutter_riverpod.dart',
        _packageEntry,
        'package:yamibo_forum_client/yamibo_forum_client.dart',
        'package:http/http.dart',
        'dart:io',
        'dart:ffi',
      },
    );
    expect(
      _violationTargets('${_packageRoot}test/new_test.dart', '''
import 'package:forum_content_renderer/forum_content_renderer.dart'
  if (dart.library.io == 'true') 'package:forum_content_renderer/src/private.dart';
import '../../../test/test_support/localized_test_app.dart';
'''),
      {
        '${_packageLib}src/private.dart',
        'test/test_support/localized_test_app.dart',
      },
    );
  });

  test('shared rendering keeps Host ownership and one public entry', () {
    final violations = <String>[];
    for (final root in [
      'lib',
      'test',
      '${_packageRoot}lib',
      '${_packageRoot}test',
      '${_packageRoot}example',
    ]) {
      for (final file in Directory(
        root,
      ).listSync(recursive: true, followLinks: false).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final path = normalizeDartSourcePath(file.path);
        violations.addAll(
          _violationTargets(
            path,
            file.readAsStringSync(encoding: utf8),
          ).map((target) => '$path -> $target'),
        );
      }
    }
    expect(Directory(_sharedRoot).existsSync(), isTrue);
    for (final source in _cacheNeutralDisplayFiles) {
      expect(File(source).existsSync(), isTrue, reason: source);
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('shared code rejects thread and app Host dependencies', () {
    const source =
        '${_sharedRoot}presentation/html_rendering/new_renderer.dart';
    expect(
      _violationTargets(source, '''
import 'package:y300/features/thread/presentation/services/new_session.dart';
export '../../../thread/presentation/thread_detail_page.dart';
import 'package:y300/app/content_rendering/new_host.dart';
'''),
      {
        'lib/features/thread/presentation/services/new_session.dart',
        'lib/features/thread/presentation/thread_detail_page.dart',
        'lib/app/content_rendering/new_host.dart',
      },
    );
  });

  test(
    'consumers cannot bypass the facade or reuse retired thread entries',
    () {
      const source = 'lib/features/novel/presentation/new_reader.dart';
      expect(
        _violationTargets(source, '''
import '../../content_rendering_shared/presentation/html_rendering/new_renderer.dart';
export 'package:y300/features/content_rendering_shared/domain/models/new_model.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_content_view.dart';
'''),
        {
          '${_sharedRoot}presentation/html_rendering/new_renderer.dart',
          '${_sharedRoot}domain/models/new_model.dart',
          '${_threadHtmlRoot}forum_html_content_view.dart',
        },
      );
    },
  );

  test('domain and controllers do not depend on preference implementations', () {
    const controller =
        '${_sharedRoot}application/forum_html_reader_preferences_controller.dart';
    expect(
      _violationTargets(controller, '''
import '../data/repositories/new_repository.dart';
import 'package:y300/core/preferences/preferences_store.dart';
'''),
      {
        '${_sharedRoot}data/repositories/new_repository.dart',
        'lib/core/preferences/preferences_store.dart',
      },
    );
    expect(
      _violationTargets('${_sharedRoot}domain/models/new_model.dart', '''
import 'package:flutter/widgets.dart';
export '../../application/new_controller.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
'''),
      {
        'package:flutter/widgets.dart',
        '${_sharedRoot}application/new_controller.dart',
        _packageEntry,
      },
    );
  });

  test('preparation image policy remains safe for background preparation', () {
    expect(
      _violationTargets(_preparationPolicyFiles.first, '''
import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
'''),
      {
        'dart:ui',
        'package:flutter_riverpod/flutter_riverpod.dart',
        'lib/features/cache/data/providers/image_cache_providers.dart',
      },
    );
  });

  test('comments, conditional URIs, and allowed contracts are handled', () {
    const source =
        '${_sharedRoot}presentation/html_rendering/new_renderer.dart';
    expect(
      _violationTargets(source, '''
/* example /* nested comment */
import 'package:y300/features/thread/presentation/thread_detail_page.dart';
*/
import 'package:flutter/material.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/reader_shared/domain/rich_text/typography/rich_text_typography.dart';
import '../contracts/forum_html_render_preparer.dart';
import '../contracts/new_adapter.dart'
  if (dart.library.io == 'true')
    'package:y300/features/thread/data/new_adapter.dart';
const example = """
export 'package:y300/app/new_host.dart';
""";
'''),
      {'lib/features/thread/data/new_adapter.dart'},
    );
    expect(
      _violationTargets('lib/features/profile/presentation/new_page.dart', '''
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/app/content_rendering/native_forum_html_render_theme_factory.dart';
'''),
      isEmpty,
    );
  });

  test('prepared images and pipeline consume neutral Host contracts', () {
    for (final source in _cacheNeutralPreparationFiles) {
      expect(
        _violationTargets(source, '''
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
export 'package:forum_content_renderer/src/contracts/forum_html_prepared_image_resource.dart'
  if (dart.library.io) 'package:y300/features/content_rendering_shared/application/host/new_cache_adapter.dart';
'''),
        {
          'lib/features/cache/domain/models/forum_image_load_spec.dart',
          'lib/core/network/site_url_resolver.dart',
          _publicEntry,
          '${_sharedRoot}application/host/new_cache_adapter.dart',
        },
      );
    }
  });

  test(
    'image UI consumes explicit Host contracts without cache or providers',
    () {
      for (final source in _cacheNeutralDisplayFiles) {
        expect(
          _violationTargets(source, '''
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/riverpod.dart';
import 'package:provider/provider.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
export 'package:y300/features/content_rendering_shared/application/forum_html_image_host_provider.dart';
import 'package:y300/features/content_rendering_shared/data/new_repository.dart';
'''),
          {
            'lib/features/cache/domain/models/forum_image_load_spec.dart',
            'package:flutter_riverpod/flutter_riverpod.dart',
            'package:riverpod/riverpod.dart',
            'package:provider/provider.dart',
            _publicEntry,
            '${_sharedRoot}application/forum_html_image_host_provider.dart',
            '${_sharedRoot}data/new_repository.dart',
          },
        );
        expect(
          _violationTargets(source, '''
import 'package:flutter/widgets.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart';
import 'package:forum_content_renderer/src/models/forum_html_content_layout.dart';
'''),
          isEmpty,
        );
      }
    },
  );
}

Set<String> _violationTargets(String source, String contents) => {
  for (final uri in dartDependencyDirectiveUris(contents))
    if (_isForbidden(source, _target(source, uri))) _target(source, uri),
};

String _target(String source, String uri) =>
    uri.startsWith('package:forum_content_renderer/')
    ? normalizeDartSourcePath(
        '$_packageLib${uri.substring('package:forum_content_renderer/'.length)}',
      )
    : uri.startsWith('package:forum_content_renderer_example/')
    ? normalizeDartSourcePath(
        '${_packageRoot}example/lib/${uri.substring('package:forum_content_renderer_example/'.length)}',
      )
    : resolveDartDependencyTarget(source, uri);

bool _isForbidden(String source, String target) {
  if (_retiredThreadEntries.contains(target)) return true;
  if (source.startsWith(_packageRoot)) {
    final library = source.startsWith(_packageLib);
    if (_preparationPolicyFiles.contains(source) &&
        (target == 'dart:ui' ||
            target == 'dart:io' ||
            target.startsWith('package:flutter'))) {
      return true;
    }
    if (target.startsWith(_packageRoot)) {
      if (library) {
        return !target.startsWith('${_packageLib}src/');
      }
      return target != _packageEntry &&
          !target.startsWith('${_packageRoot}test/') &&
          !target.startsWith('${_packageRoot}example/');
    }
    return !((library
            ? const {
                'dart:async',
                'dart:collection',
                'dart:convert',
                'dart:core',
                'dart:math',
                'dart:typed_data',
                'dart:ui',
              }.contains(target)
            : target.startsWith('dart:')) ||
        target.startsWith('package:flutter/') ||
        (!library && target.startsWith('package:flutter_test/')) ||
        target.startsWith('package:flutter_widget_from_html_core/') ||
        target.startsWith('package:html/') ||
        target.startsWith('package:csslib/') ||
        target.startsWith('package:material_color_utilities/') ||
        target ==
            'package:yamibo_forum_client/yamibo_forum_client_contracts.dart');
  }
  if (target.startsWith(_packageRoot) && target != _packageEntry) return true;
  // App adapter tests may inspect their own Host internals, but never pkg src.
  if (source.startsWith('test/')) return false;
  if (!source.startsWith(_sharedRoot)) {
    return target.startsWith(_sharedRoot) && target != _publicEntry;
  }
  if (target.startsWith('lib/features/thread/') ||
      target.startsWith('lib/app/')) {
    return true;
  }
  if (source == _publicEntry &&
      (target.contains('/data/') || target.contains('/application/host/'))) {
    return true;
  }
  if (_cacheNeutralPreparationFiles.contains(source) &&
      (target == _publicEntry ||
          target.startsWith('lib/features/cache/') ||
          target.startsWith('lib/core/network/') ||
          target.contains('/application/') ||
          target.contains('/data/'))) {
    return true;
  }
  if (_cacheNeutralDisplayFiles.contains(source) &&
      (target == _publicEntry ||
          target.startsWith('lib/features/cache/') ||
          target.contains('/application/') ||
          target.contains('/data/') ||
          target.startsWith('package:flutter_riverpod/') ||
          target.startsWith('package:riverpod/') ||
          target.startsWith('package:provider/'))) {
    return true;
  }
  final domain = source.startsWith('${_sharedRoot}domain/');
  final policy = _preparationPolicyFiles.contains(source);
  if (domain || policy) {
    if (domain && target == _packageEntry) return true;
    if (target.contains('/data/') ||
        (target.contains('/application/') &&
            !(source ==
                    '${_sharedRoot}application/host/forum_cache_html_preparation_image_policy.dart' &&
                target ==
                    '${_sharedRoot}application/host/cache_forum_html_prepared_image_resource.dart')) ||
        target.startsWith('lib/core/preferences/') ||
        target.startsWith('package:flutter_') ||
        target.startsWith('package:shared_preferences/') ||
        target == 'dart:ui' ||
        target == 'dart:io') {
      return true;
    }
    if (target.startsWith('package:flutter/') &&
        target != 'package:flutter/foundation.dart') {
      return true;
    }
    if (domain && target.contains('/presentation/')) return true;
  }
  if (source.startsWith('${_sharedRoot}presentation/') &&
      target.contains('/data/')) {
    return true;
  }
  return source ==
          '${_sharedRoot}application/forum_html_reader_preferences_controller.dart' &&
      (target.contains('/data/') || target.startsWith('lib/core/preferences/'));
}
