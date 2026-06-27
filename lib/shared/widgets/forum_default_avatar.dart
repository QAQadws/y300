import 'package:flutter/widgets.dart';

const String forumDefaultAvatarAsset = 'assets/noavatar.png';

bool isForumDefaultOrUnsupportedAvatarUrl(String? rawUrl) {
  final normalized = rawUrl?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) {
    return true;
  }
  final path = Uri.tryParse(normalized)?.path.toLowerCase() ?? normalized;
  return path.endsWith('/noavatar.svg') || path.endsWith('.svg');
}

Widget forumDefaultAvatarImage({
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
}) {
  return Image.asset(
    forumDefaultAvatarAsset,
    width: width,
    height: height,
    fit: fit,
  );
}
