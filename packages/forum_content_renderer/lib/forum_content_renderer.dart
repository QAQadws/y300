/// Shared HTML rendering contracts, policies and widgets.
library;

export 'src/block/forum_body_block_box.dart';
export 'src/pagination/forum_body_image_frame.dart';
export 'src/block/forum_body_block_flow_cursor.dart';
export 'src/document/forum_body_document.dart';
export 'src/document/forum_body_collapse_layout.dart';
export 'src/document/forum_body_parser.dart';
export 'src/table/forum_body_table_grid.dart';
export 'src/flow/forum_body_styled_flow_cursor.dart';
export 'src/flow/forum_body_text_flow_cursor.dart';
export 'src/flow/forum_body_inline_flow_content.dart';
export 'src/inline/forum_body_inline_span_content.dart'
    show
        ForumBodyInlineSpanContent,
        ForumBodyInlinePaintInput,
        ForumBodyInlineContext,
        ForumBodyInlineEmphasisGlyphInput,
        ForumBodyInlineEmphasisGlyphPreparation;
export 'src/inline/forum_body_inline_paragraph_layout.dart';
export 'src/inline/forum_body_inline_image_input.dart';
export 'src/inline/forum_body_inline_emphasis_child_bands.dart';
export 'src/inline/forum_body_inline_emphasis_row_placement.dart';
export 'src/inline/forum_body_inline_emphasis_children_plan.dart';
export 'src/inline/forum_body_inline_emphasis_reflow_reference.dart';
export 'src/inline/forum_body_inline_emphasis_reflow_preparation.dart';
export 'src/inline/forum_body_inline_emphasis_parent_preparation.dart';
export 'src/inline/forum_body_inline_emphasis_isolation_preparation.dart';
export 'src/inline/forum_body_inline_emphasis_row_allocation.dart';
export 'src/inline/forum_body_inline_row_reference.dart';
export 'src/inline/forum_body_inline_parent_rows.dart';
export 'src/inline/forum_body_inline_logical_paint_rows.dart';
export 'src/inline/forum_body_inline_emphasis_paint_reference.dart';
export 'src/inline/forum_body_inline_emphasis_paint_view.dart';
export 'src/inline/forum_body_inline_emphasis_paint_preparation.dart';
export 'src/inline/forum_body_inline_emphasis_marker_preparation.dart';
export 'src/inline/forum_body_inline_paint_row.dart';
export 'src/inline/forum_body_inline_paint_command.dart';
export 'src/pagination/forum_body_inline_page_preparation.dart'
    show
        ForumBodyInlineEmphasisChildView,
        ForumBodyInlineEmphasisChildPreparation;
export 'src/inline/forum_body_inline_paragraph_view.dart'
    show
        ForumBodyInlineParagraphView,
        ForumBodyInlineImageBinding,
        ForumBodyInlineFontFrameViewPreparation,
        ForumBodyInlineViewFailure,
        ForumBodyInlineViewException;
export 'src/inline/forum_body_inline_paragraph_surface.dart';
export 'src/inline/forum_body_ruby_group_layout.dart'
    show
        ForumBodyRubyGroupLayout,
        ForumBodyRubyHit,
        ForumBodyRubyPart,
        ForumBodyRubyGroupFailure,
        ForumBodyRubyGroupException;
export 'src/inline/forum_body_ruby_group_metrics.dart'
    show
        ForumBodyRubyGroupMetrics,
        ForumBodyRubyAnnotationMetrics,
        ForumBodyRubyLevelMetrics,
        ForumBodyRubyAnnotationLevelMetrics,
        ForumBodyRubySegmentMetrics,
        ForumBodyRubyMeasuredSpan,
        ForumBodyRubyPlacedSpan,
        ForumBodyRubyMeasuredGap,
        ForumBodyRubyPlacedGap,
        ForumBodyRubyMeasuredAnnotationGap,
        ForumBodyRubyPlacedAnnotationGap,
        ForumBodyRubyAtomMetrics,
        ForumBodyRubyColumnMetrics,
        ForumBodyRubyComponentMetrics,
        ForumBodyRubySpaceMetrics,
        ForumBodyTextBaselineAtomMetrics,
        ForumBodyRubySoftSpaceMetrics,
        ForumBodyRubySoftSpaceMeasuredMember,
        ForumBodyRubySoftSpacePlacedMember;
export 'src/inline/forum_body_ruby_soft_space_request.dart';
export 'src/inline/forum_body_ruby_soft_space_layout.dart';
export 'src/inline/forum_body_ruby_segment_layout.dart'
    show
        ForumBodyRubySegmentLayout,
        ForumBodyRubySegmentHit,
        ForumBodyRubySegmentAnnotation;
export 'src/inline/forum_body_ruby_group_preparation.dart';
export 'src/inline/forum_body_ruby_segment_request.dart';
export 'src/inline/forum_body_ruby_column_request.dart';
export 'src/inline/forum_body_ruby_container_background.dart';
export 'src/inline/forum_body_ruby_root_box.dart';
export 'src/inline/forum_body_ruby_tree_input.dart'
    show
        ForumBodyRubyGlyphTreeInput,
        ForumBodyRubyGlyphTreeSource,
        ForumBodyRubyGlyphTreeInputPreparation,
        ForumBodyRubyGlyphTreeMetrics,
        ForumBodyRubyGlyphTreeMetricsPreparation,
        ForumBodyRubyGlyphTreeGeometry,
        ForumBodyRubyGlyphTreeSourcePosition,
        ForumBodyRubyGlyphTreeGeometryPreparation,
        ForumBodyRubyGlyphTreeBand,
        ForumBodyRubyGlyphTreeBandContext,
        ForumBodyRubyGlyphTreeBands,
        ForumBodyRubyGlyphTreeBandsPreparation,
        ForumBodyRubyGlyphTreeBoundSource,
        ForumBodyRubyGlyphTreeBinding,
        ForumBodyRubyGlyphTreeBindingPreparation,
        ForumBodyRubyEmptyAnnotationFont,
        ForumBodyRubyEmptyAnnotationFonts,
        ForumBodyRubyEmptyAnnotationFontsPreparation,
        ForumBodyRubyTreeEmphasisSourceMetrics,
        ForumBodyRubyTreeEmphasisMetrics,
        ForumBodyRubyTreeEmphasisMetricsPreparation,
        ForumBodyRubyPhysicalRow,
        ForumBodyRubyTreeDecorationBand,
        ForumBodyRubyTreeDecorationNode,
        ForumBodyRubyTreeDecorationContext,
        ForumBodyRubyTreeDecorationBands,
        ForumBodyRubyTreeDecorationBandsPreparation,
        ForumBodyRubyTreePlacedEmphasisMark,
        ForumBodyRubyTreeEmphasisRow,
        ForumBodyRubyTreeEmphasisPlacement,
        ForumBodyRubyRootEmphasisShift,
        ForumBodyRubyTreeEmphasisPlacementPreparation;
export 'src/inline/forum_body_ruby_tree_child_geometry.dart'
    show
        ForumBodyRubyTreeBranch,
        ForumBodyRubyTreeChildGeometry,
        ForumBodyRubyTreeNodePosition;
export 'src/inline/forum_body_ruby_tree_layout.dart' show ForumBodyRubyTreeHit;
export 'src/inline/forum_body_ruby_tree_emphasis_format_preparation.dart';
export 'src/inline/forum_body_ruby_atom_plan.dart';
export 'src/inline/forum_body_ruby_segment_metrics_preparation.dart';
export 'src/inline/forum_body_ruby_segment_preparation.dart';
export 'src/inline/forum_body_text_band_content.dart'
    show ForumBodyTextBandContent;
export 'src/inline/forum_body_text_band_layout.dart';
export 'src/inline/forum_body_ruby_content.dart';
export 'src/inline/forum_body_ruby_content_cursor.dart';
export 'src/pagination/forum_body_text_page_composer.dart';
export 'src/pagination/forum_body_text_page_binding.dart'
    show
        validateForumBodyTextPageBinding,
        validateForumBodyPreparedTextPageBinding;
export 'src/pagination/forum_body_text_page_session.dart';
export 'src/pagination/forum_body_text_page_preparation.dart'
    show
        ForumBodyTextPagePreparation,
        ForumBodyTextPagePreparationState,
        ForumBodyTextPagePreparationStep,
        ForumBodyTextPagePreparationFailure,
        ForumBodyTextPagePreparationException;
export 'src/pagination/forum_body_text_page_surface.dart';
export 'src/pagination/forum_body_text_selection_snapshot.dart';
export 'src/pagination/forum_body_prepared_text_fragment.dart';
export 'src/pagination/forum_body_text_page_content.dart';
export 'src/paragraph/forum_body_paragraph_content.dart';
export 'src/paragraph/forum_body_paragraph_layout.dart';
export 'src/paragraph/forum_body_paragraph_line_frames.dart';
export 'src/paragraph/forum_body_paragraph_row.dart';
export 'src/paragraph/forum_body_paragraph_row_reference.dart';
export 'src/paragraph/forum_body_paragraph_cache.dart';
export 'src/paragraph/forum_body_text_layout.dart';
export 'src/inline/forum_body_text_baseline_layout.dart';
export 'src/inline/forum_body_text_baseline_preparation.dart';
export 'src/paragraph/forum_body_text_request.dart';
export 'src/paragraph/forum_body_native_request.dart';
export 'src/inline/forum_body_inline_paragraph_request.dart';
export 'src/inline/forum_body_emphasis_mark.dart'
    show ForumBodyEmphasisMarkInput, ForumBodyDecorationTextInput;
export 'src/decoration/forum_body_decoration_text_request.dart';
export 'src/inline/forum_body_emphasis_mark_request.dart';
export 'src/inline/forum_body_emphasis_text_input.dart';
export 'src/inline/forum_body_inline_font_frame_plan.dart';
export 'src/inline/forum_body_emphasis_row_input.dart';
export 'src/inline/forum_body_emphasis_text_geometry.dart';
export 'src/inline/forum_body_emphasis_line_layout.dart';
export 'src/inline/forum_body_ruby_base_emphasis_geometry.dart';
export 'src/inline/forum_body_emphasis_row_allocation.dart';
export 'src/inline/forum_body_emphasis_paragraph_metrics.dart';
export 'src/inline/forum_body_fitted_emphasis_plan.dart';
export 'src/inline/forum_body_emphasis_fragment_surface.dart';
export 'src/paragraph/forum_body_paragraph_surface.dart';
export 'src/style/forum_body_length.dart';
export 'src/style/forum_body_box_style.dart';
export 'src/style/forum_body_style_options.dart';
export 'src/style/forum_body_style_resolver.dart';
export 'src/style/forum_body_style_cursor.dart';

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
export 'src/models/forum_html_safe_display_plan.dart';
export 'src/contracts/forum_html_collapse_labels.dart';
export 'src/contracts/forum_html_display_image.dart';
export 'src/contracts/forum_html_image_host.dart';
export 'src/contracts/forum_html_image_predecode_host.dart';
export 'src/contracts/forum_html_preparation_image_policy.dart';
export 'src/contracts/forum_html_prepared_image_resource.dart';
export 'src/contracts/forum_html_render_palette.dart';
export 'src/html_rendering/forum_html_fragment_codec.dart';
export 'src/html_rendering/forum_html_image_deduplicator.dart'
    show ForumHtmlImageDeduplicator;
export 'src/html_rendering/forum_html_prepared_render_document.dart';
export 'src/html_rendering/forum_html_render_callbacks.dart';
export 'src/html_rendering/forum_html_render_theme_factory.dart';
export 'src/html_rendering/forum_html_render_style_policy.dart';
export 'src/html_rendering/forum_html_render_text_style_resolver.dart';
export 'src/html_rendering/forum_html_preparation_pipeline.dart';
export 'src/html_rendering/forum_html_renderer.dart';
export 'src/html_rendering/forum_html_safe_display_planner.dart';
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
export 'src/services/forum_http_text_link_detector.dart';
export 'src/services/forum_html_image_viewport_coordinator.dart';
export 'src/html_rendering/widgets/forum_html_image_view.dart';
export 'src/services/forum_html_image_predecode_policy.dart';
export 'src/services/forum_html_image_anchor_controller.dart'
    show ForumHtmlImageAnchorController;
