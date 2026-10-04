/// Layout, viewport and scroll compensation geometry without a UI runtime.
library;

export 'src/continuous_image_geometry_models.dart'
    show
        ContinuousImageDimensionSource,
        ContinuousImageDimensions,
        ContinuousImageExtent,
        ContinuousImageLayoutHint,
        ContinuousImageLayoutItem,
        ContinuousImageScrollDirection,
        ContinuousImageViewportState;
export 'src/continuous_image_extent_registry.dart'
    show ContinuousImageExtentRegistry, InMemoryContinuousImageExtentRegistry;
export 'src/continuous_image_layout_index.dart' show ContinuousImageLayoutIndex;
export 'src/continuous_image_layout_resolver.dart'
    show ContinuousImageDimensionCandidate, ContinuousImageLayoutResolver;
export 'src/continuous_image_scroll_anchor_coordinator.dart'
    show
        ContinuousImageScrollAnchorCoordinator,
        ContinuousImageScrollAnchorMetrics,
        ContinuousImageScrollCompensationPlan,
        ContinuousImageScrollCompensationTiming;
