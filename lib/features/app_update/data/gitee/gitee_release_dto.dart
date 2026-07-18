final class GiteeReleaseAssetDto {
  const GiteeReleaseAssetDto({
    required this.name,
    required this.browserDownloadUrl,
  });

  final String name;
  final String browserDownloadUrl;
}

final class GiteeReleaseDto {
  const GiteeReleaseDto({
    required this.tagName,
    required this.name,
    required this.body,
    required this.prerelease,
    required this.createdAt,
    required this.assets,
  });

  final String tagName;
  final String name;
  final String body;
  final bool prerelease;
  final String? createdAt;
  final List<GiteeReleaseAssetDto> assets;
}
