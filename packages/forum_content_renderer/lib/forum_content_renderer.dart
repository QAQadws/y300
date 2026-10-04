/// Shared HTML rendering contracts, policies and widgets.
library;

export 'src/helpers/discuz_font_size_policy.dart' show DiscuzFontSizePolicy;
export 'src/helpers/forum_collapse_chrome.dart' show ForumCollapseChrome;
export 'src/helpers/rich_text_color_contrast.dart'
    show RichTextColorContrast, FlutterRichTextColorContrast;
export 'src/helpers/rich_text_tone_resolver.dart'
    show
        RichTextToneResolver,
        MaterialRichTextToneResolver,
        RichTextToneResolutionFailure;
export 'src/models/forum_html_content_layout.dart';
export 'src/models/forum_html_render_options.dart';
export 'src/contracts/forum_html_collapse_labels.dart';
export 'src/contracts/forum_html_display_image.dart';
export 'src/contracts/forum_html_image_host.dart';
export 'src/contracts/forum_html_preparation_image_policy.dart';
export 'src/contracts/forum_html_prepared_image_resource.dart';
export 'src/contracts/forum_html_render_palette.dart';
export 'src/html_rendering/forum_html_fragment_codec.dart';
export 'src/html_rendering/forum_html_image_deduplicator.dart';
export 'src/html_rendering/forum_html_prepared_render_document.dart';
export 'src/html_rendering/forum_html_render_callbacks.dart';
export 'src/html_rendering/forum_html_render_theme_factory.dart';
export 'src/html_rendering/forum_html_render_style_policy.dart';
export 'src/html_rendering/forum_html_render_text_style_resolver.dart';
export 'src/html_rendering/forum_html_preparation_pipeline.dart';
export 'src/html_rendering/forum_html_renderer.dart';
export 'src/html_rendering/theme/css_author_color_parser.dart';
export 'src/html_rendering/theme/css_inline_style_declarations.dart';
export 'src/html_rendering/theme/forum_html_author_color_style.dart';
export 'src/html_rendering/theme/forum_html_background_tone_resolver.dart';
export 'src/html_rendering/theme/forum_html_color_adaptation_policy.dart';
export 'src/html_rendering/theme/forum_html_resolved_color_state.dart';
export 'src/html_rendering/theme/forum_html_theme_adaptation_result.dart';
export 'src/html_rendering/theme/forum_html_theme_adapter.dart';
export 'src/html_rendering/theme/forum_html_theme_context.dart';
export 'src/html_rendering/widgets/forum_collapse_block.dart';
export 'src/services/forum_html_body_presentation.dart';
export 'src/services/forum_html_image_viewport_coordinator.dart';
