import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/comic/data/providers/comic_providers.dart';
import 'package:y300/features/comic/presentation/controllers/comic_comment_session_controller.dart';
import 'package:y300/features/comic/presentation/widgets/comic_comment_tail_surface.dart';

final comicCommentSessionControllerProvider = Provider.autoDispose
    .family<ComicCommentSessionController, ComicCommentSessionKey>((ref, key) {
      final controller = ComicCommentSessionController(
        key: key,
        loader: ref.watch(comicCommentLoaderProvider),
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

final comicCommentTailSurfaceProvider = Provider.autoDispose
    .family<ComicCommentTailSurface, ComicCommentSessionKey>((ref, key) {
      final session = ref.watch(comicCommentSessionControllerProvider(key));
      final surface = ComicCommentTailSurface(
        session: session,
        imageHeaderBuilder: ref.watch(imageRequestHeaderBuilderProvider),
      );
      ref.onDispose(surface.dispose);
      return surface;
    });
