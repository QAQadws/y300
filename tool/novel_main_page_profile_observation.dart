import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_overlay_scaffold.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_controller.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_native_paged_controller.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_owner.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_delayed_loading_boundary.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_html_paged_surface.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_native_paged_surface.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_native_paged_viewport.dart';
import 'package:y300/l10n/app_localizations.dart';

/// Observation only: never calls content-ready, commits positions or changes a
/// renderer callback. Stop at viewports to avoid scanning the rendered corpus.
final class ProfileReaderObservation {
  ProfileReaderObservation();
  int? page;
  int count = 0;
  String? paginationKey;
  bool complete = false;
  bool ready = false;
  bool businessConfirmed = false;
  bool failed = false;
  NovelReaderNativeOwner? nativeOwner;
  NovelReaderController? businessController;
  ReaderOverlayScaffold? overlay;
  bool Function()? legacyCachesReleased;
}

bool profileVisiblePageAccepted({
  required int? mountedPage,
  required int pageCount,
  required int businessPage,
  required String? mountedKey,
  required String? businessKey,
  required bool covered,
  required bool pending,
  required bool routeSettled,
}) =>
    mountedPage != null &&
    mountedPage >= 0 &&
    mountedPage < pageCount &&
    mountedPage == businessPage &&
    mountedKey != null &&
    mountedKey == businessKey &&
    !covered &&
    !pending &&
    routeSettled;

ProfileReaderObservation observeProfileReader(
  BuildContext context,
  NovelReaderArgs args,
) {
  final observation = ProfileReaderObservation();
  NovelReaderNativePagedController? native;
  NovelReaderHtmlPagedSurface? legacy;
  String? legacySemanticsValue;
  bool covered = false;
  bool scrolling = false;
  void visit(Element element) {
    final widget = element.widget;
    if (widget is NovelReaderDelayedLoadingBoundary) {
      covered |= widget.isLoading;
    } else if (widget is ReaderOverlayScaffold) {
      observation.overlay = widget;
      covered |= widget.controller?.contentObscured.value ?? false;
    } else if (widget is NovelReaderNativePagedSurface) {
      observation.nativeOwner = widget.owner;
    } else if (widget is NovelReaderNativePagedViewport) {
      native = widget.controller;
      return;
    } else if (widget is NovelReaderHtmlPagedSurface) {
      legacy = widget;
    } else if (widget is Semantics &&
        widget.key == const Key('novel-reader-paged-semantics')) {
      legacySemanticsValue = widget.properties.value;
      // The mounted page session's public ValueKey holds the layout identity.
      // The surface's progressSnapshot can intentionally retain the OLD key
      // during a read-only typography preview; it is not a display identity.
      element.visitAncestorElements((ancestor) {
        if (ancestor.widget is NovelReaderHtmlPagedSurface) return false;
        if (ancestor.widget.key case ValueKey<String>(value: final candidate)) {
          try {
            final identity = jsonDecode(candidate);
            if (identity is List &&
                identity.isNotEmpty &&
                identity.first == args.episodeId) {
              // NovelReaderPaginationKey.layoutFingerprint is SHA-256 of this
              // exact cache identity, as used by the viewport's position port.
              observation.paginationKey = sha256
                  .convert(utf8.encode(candidate))
                  .toString();
              return false;
            }
          } on FormatException {
            // Other ancestor keys are not pagination identities.
          }
        }
        return true;
      });
    } else if (widget is PageView &&
        widget.key == const Key('novel-reader-paged-page-view')) {
      observation.count = widget.childrenDelegate.estimatedChildCount ?? 0;
      final controller = widget.controller;
      if (controller != null && controller.hasClients) {
        final page = controller.page;
        scrolling = controller.position.isScrollingNotifier.value;
        if (page != null && (page - page.round()).abs() < .0001) {
          observation.page = page.round();
        }
      }
      return;
    } else if (widget.key == const Key('novel-reader-pagination-failure') ||
        widget.key == const Key('novel-reader-pagination-paused') ||
        widget is Icon && widget.icon == Icons.warning_amber_outlined) {
      observation.failed = true;
    }
    element.visitChildElements(visit);
  }

  context.visitChildElements(visit);
  final container = ProviderScope.containerOf(context, listen: false);
  final provider = novelReaderControllerProvider(args);
  final asyncState = container.read(provider);
  observation.failed |= asyncState.hasError;
  final state = asyncState.asData?.value;
  if (state == null) return observation;
  observation.businessController = container.read(provider.notifier);
  final snapshot = state.progressSnapshot;
  final nativeController = native;
  bool pending = scrolling || state.transition != null;
  if (nativeController != null) {
    observation.page = nativeController.visiblePageIndex;
    observation.count = nativeController.snapshot?.length ?? 0;
    observation.complete = nativeController.snapshot?.isComplete ?? false;
    observation.paginationKey = nativeController.paginationKey;
    observation.failed |= nativeController.error != null;
    pending |=
        nativeController.isSuspended || nativeController.hasPendingNavigation;
  } else if (legacy case final surface?) {
    // Read the public accessibility value in its actual locale. A cached plan
    // alone cannot prove that its page is mounted or the loading cover is gone.
    final l10n = AppLocalizations.of(context);
    if (observation.page case final page?) {
      observation.complete =
          legacySemanticsValue ==
          l10n.novelPageValue(page + 1, l10n.novelPages(observation.count));
      pending |=
          !observation.complete &&
          legacySemanticsValue !=
              l10n.novelPageValue(page + 1, l10n.novelPageCountPending);
    }
    final plans = surface.paginationCache;
    final measures = surface.paginationMeasureCache;
    final boundaries = surface.paginationBoundaryCache;
    final prepared = surface.preparedChapterCache;
    observation.legacyCachesReleased = () =>
        plans?.isClosed == true &&
        plans?.estimatedRetainedBytes == 0 &&
        measures?.isClosed == true &&
        measures?.estimatedRetainedBytes == 0 &&
        boundaries?.isClosed == true &&
        boundaries?.estimatedRetainedBytes == 0 &&
        prepared?.isClosed == true &&
        prepared?.estimatedRetainedBytes == 0;
  }
  final routeSettled =
      ModalRoute.of(context)?.animation?.status == AnimationStatus.completed;
  observation.businessConfirmed = profileVisiblePageAccepted(
    mountedPage: observation.page,
    pageCount: observation.count,
    businessPage: snapshot.pageIndex,
    mountedKey: observation.paginationKey,
    businessKey: snapshot.paginationKey,
    covered: covered,
    pending: pending,
    routeSettled: routeSettled,
  );
  final page = observation.page;
  observation.ready =
      !observation.failed &&
      page != null &&
      page >= 0 &&
      page < observation.count &&
      observation.paginationKey != null &&
      !covered &&
      !pending &&
      routeSettled;
  return observation;
}
