import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/profile/presentation/current_account_avatar_controller.dart';
import 'package:y300/shared/widgets/forum_default_avatar.dart';
import 'package:y300/shared/widgets/forum_media_loading_style.dart';

/// Keeps the rendered frame while its replacement is decoded off screen.
class MoreAccountAvatar extends ConsumerStatefulWidget {
  const MoreAccountAvatar({super.key, required this.uid, required this.size});
  final String uid;
  final double size;

  @override
  ConsumerState<MoreAccountAvatar> createState() => _MoreAccountAvatarState();
}

class _MoreAccountAvatarState extends ConsumerState<MoreAccountAvatar> {
  ImageProvider? _shown;
  String? _shownKey;
  String? _requestedKey;
  int _generation = 0;
  bool _animate = false;

  void _prepare(CurrentAccountAvatarState value) {
    final path = value.localPath;
    final key = path ?? (value.useDefault ? forumDefaultAvatarAsset : null);
    if (key == null || key == _requestedKey) return;
    _requestedKey = key;
    final generation = ++_generation;
    final ImageProvider provider = path == null
        ? const AssetImage(forumDefaultAvatarAsset)
        : FileImage(File(path));
    unawaited(
      Future<void>.microtask(() async {
        if (!mounted) return;
        if (_shown == null && path == null) {
          setState(() {
            _shown = provider;
            _shownKey = key;
          });
          return;
        }
        var failed = false;
        await precacheImage(
          provider,
          context,
          onError: (_, _) => failed = true,
        );
        if (!mounted || generation != _generation) return;
        if (failed) {
          if (_shown == null) {
            setState(() {
              _shown = const AssetImage(forumDefaultAvatarAsset);
              _shownKey = forumDefaultAvatarAsset;
            });
          }
          return;
        }
        setState(() {
          _animate = value.animate;
          _shown = provider;
          _shownKey = key;
        });
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final avatar = ref.watch(currentAccountAvatarControllerProvider);
    if (avatar.uid == widget.uid) {
      _prepare(avatar);
    } else {
      // Identity invalidation must clear even an already decoded retained frame.
      _generation++;
      _shown = null;
      _shownKey = null;
      _requestedKey = null;
      _animate = false;
    }
    return SizedBox(
      key: const Key('more-account-avatar-image'),
      width: widget.size,
      height: widget.size,
      child: ClipOval(
        child: AnimatedSwitcher(
          key: ValueKey(avatar.uid),
          duration: !_animate || MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : ForumMediaLoadingStyle.fadeInDuration,
          child: _shown == null
              ? ColoredBox(
                  key: const Key('forum-avatar-placeholder'),
                  color: ForumMediaLoadingStyle.placeholderColorFor(
                    Theme.of(context).scaffoldBackgroundColor,
                  ),
                  child: const SizedBox.expand(),
                )
              : Image(
                  key: ValueKey(_shownKey),
                  image: _shown!,
                  width: widget.size,
                  height: widget.size,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
        ),
      ),
    );
  }
}
