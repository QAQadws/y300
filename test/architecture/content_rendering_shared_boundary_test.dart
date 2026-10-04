import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_dependency_directives.dart';

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
  '${_sharedRoot}presentation/contracts/forum_html_preparation_image_policy.dart',
  '${_sharedRoot}presentation/contracts/forum_html_prepared_image_resource.dart',
  '${_sharedRoot}application/host/forum_cache_html_preparation_image_policy.dart',
  '${_sharedRoot}application/host/cache_forum_html_prepared_image_resource.dart',
};
const _cacheNeutralPreparationFiles = {
  '${_sharedRoot}presentation/contracts/forum_html_preparation_image_policy.dart',
  '${_sharedRoot}presentation/contracts/forum_html_prepared_image_resource.dart',
  '${_sharedRoot}presentation/html_rendering/forum_html_prepared_render_document.dart',
  '${_sharedRoot}presentation/html_rendering/forum_html_render_preparer.dart',
  '${_sharedRoot}presentation/html_rendering/forum_html_image_deduplicator.dart',
};
const _cacheNeutralDisplayFiles = {
  '${_sharedRoot}presentation/contracts/forum_html_image_host.dart',
  '${_sharedRoot}presentation/contracts/forum_html_display_image.dart',
  '${_sharedRoot}presentation/html_rendering/forum_html_image_widget_factory.dart',
  '${_sharedRoot}presentation/html_rendering/forum_html_render_callbacks.dart',
  '${_sharedRoot}presentation/services/forum_html_image_viewport_coordinator.dart',
};

void main() {
  test('shared rendering keeps Host ownership and one public entry', () {
    final violations = <String>[];
    for (final file in Directory(
      'lib',
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
import
  'package:y300/features/thread/presentation/services/new_session.dart';
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
import
  '../../content_rendering_shared/presentation/html_rendering/new_renderer.dart';
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
'''),
      {
        'package:flutter/widgets.dart',
        '${_sharedRoot}application/new_controller.dart',
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
export '../contracts/forum_html_prepared_image_resource.dart'
  if (dart.library.io) '../../application/host/new_cache_adapter.dart';
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
import 'package:y300/features/content_rendering_shared/domain/models/forum_html_content_layout.dart';
'''),
          isEmpty,
        );
      }
    },
  );
}

Set<String> _violationTargets(String source, String contents) => {
  for (final uri in dartDependencyDirectiveUris(contents))
    if (_isForbidden(source, resolveDartDependencyTarget(source, uri)))
      resolveDartDependencyTarget(source, uri),
};

bool _isForbidden(String source, String target) {
  if (_retiredThreadEntries.contains(target)) return true;
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
