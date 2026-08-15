const String forumDefaultAvatarAsset = 'assets/noavatar.png';

bool isForumDefaultAvatarUrl(String? rawUrl) {
  return _normalizedAvatarPath(rawUrl)?.endsWith('/noavatar.svg') == true;
}

bool isForumDefaultOrUnsupportedAvatarUrl(String? rawUrl) {
  final path = _normalizedAvatarPath(rawUrl);
  if (path == null) {
    return true;
  }
  return path.endsWith('/noavatar.svg') || path.endsWith('.svg');
}

String? _normalizedAvatarPath(String? rawUrl) {
  final normalized = rawUrl?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return Uri.tryParse(normalized)?.path.toLowerCase() ?? normalized;
}
