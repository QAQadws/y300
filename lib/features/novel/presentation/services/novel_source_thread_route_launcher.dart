import 'package:flutter/material.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/novel/domain/models/novel_source_reading_context.dart';
import 'package:y300/features/novel/presentation/adapters/novel_source_reading_adapter.dart';
import 'package:y300/features/thread/domain/models/thread_post_target.dart';
import 'package:y300/features/thread/domain/repositories/thread_post_locator.dart';
import 'package:y300/features/thread/domain/services/thread_post_navigation_session.dart';
import 'package:y300/features/thread/domain/services/thread_post_route_resolver.dart';
import 'package:y300/features/thread/presentation/services/thread_post_route_launcher.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';

typedef NovelSourceReadingAdapterFactory =
    NovelSourceReadingAdapter Function(NovelSourceReadingContext context);

/// Binds reading only to an explicitly selected novel source route.
/// The locator still owns ordinary forum page resolution and failure handling.
Future<void> launchNovelSourceThreadRoute({
  required BuildContext context,
  required ThreadPostNavigationSession session,
  required ThreadPostRouteResolver resolver,
  required ThreadPostTarget target,
  required bool Function() isCurrent,
  required NovelSourceReadingContext readingContext,
  required NovelSourceReadingAdapterFactory? createAdapter,
  String subject = '',
  Future<ApiResult<ThreadPostLocation>> Function()? resolve,
  Key failureDialogKey = const Key('novel-source-route-failure-dialog'),
}) async {
  final observer = createAdapter?.call(readingContext);
  try {
    await launchThreadPostRoute(
      context: context,
      session: session,
      resolver: resolver,
      target: target,
      isCurrent: isCurrent,
      subject: subject,
      bodyReadingObserver: observer,
      failureDialogKey: failureDialogKey,
      resolve: () async {
        // Prepare within the navigation single-flight. A cancelled or failed
        // location never mounts a reading producer or establishes a history.
        await observer?.prepare();
        return resolve?.call() ?? resolver.resolve(target);
      },
    );
  } finally {
    try {
      await observer?.flush();
    } finally {
      observer?.dispose();
    }
  }
}

/// The work's source-thread action has no chapter restoration target.
/// Only catalog-matched bodies become eligible after actual visible reading.
Future<void> launchNovelSourceThreadHome({
  required BuildContext context,
  required String tid,
  required bool Function() isCurrent,
  required NovelSourceReadingContext readingContext,
  required NovelSourceReadingAdapterFactory? createAdapter,
  String subject = '',
  int? initialPage,
  String? targetPid,
}) async {
  final ownerRoute = ModalRoute.of(context);
  final observer = createAdapter?.call(readingContext);
  try {
    await observer?.prepare();
    if (!context.mounted || !isCurrent() || !(ownerRoute?.isCurrent ?? true)) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ThreadDetailPage(
          tid: tid,
          subject: subject,
          initialPage: initialPage,
          targetPid: targetPid,
          bodyReadingObserver: observer,
        ),
      ),
    );
  } finally {
    try {
      await observer?.flush();
    } finally {
      observer?.dispose();
    }
  }
}
