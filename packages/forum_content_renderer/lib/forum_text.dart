/// Source coordinates and text projections; no Widget or engine imports.
library;

export 'src/text/ports.dart'
    show
        HtmlFragmentParser,
        DefaultHtmlFragmentParser,
        HtmlProtectedInlinePredicate,
        HtmlPaginationCancellation;
export 'src/text/text_coordinates.dart' show HtmlTextCoordinates;
export 'src/text/display_text_projection.dart'
    show
        HtmlDisplayWhiteSpace,
        HtmlProjectionAffinity,
        HtmlDisplayTextRun,
        HtmlDisplayTextPart,
        HtmlDisplayTextSegment,
        HtmlProjectedSourcePosition,
        HtmlDisplayTextLimitException,
        HtmlDisplayTextProjection;
export 'src/text/inline_text_projection.dart'
    show
        HtmlInlineTextAtom,
        HtmlInlineTextPosition,
        HtmlInlineTextLimitException,
        HtmlInlineTextProjection;
export 'src/text/source_text_map.dart'
    show HtmlSourceTextMap, HtmlSourceTextRange;
export 'src/text/text_band_projection.dart'
    show HtmlTextBandProjection, HtmlTextBandChild, HtmlTextBandLimitException;
export 'src/text/work_slice.dart' show HtmlPaginationWorkSlice;
export 'src/text/source_dom_index.dart'
    show
        HtmlSourceDomIndex,
        HtmlDomProtectedNodeKind,
        HtmlDomGrapheme,
        HtmlDomIndexedNode,
        HtmlDomIndexedTextNode,
        HtmlDomIndexedElementNode,
        HtmlDomIndexedOpaqueNode;
