import 'package:y300/features/app_update/data/gitee/gitee_release_dto.dart';
import 'package:y300/features/app_update/domain/models/app_release.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';
import 'package:y300/features/app_update/domain/services/app_version_codec.dart';

sealed class GiteeReleaseParseResult {
  const GiteeReleaseParseResult();
}

final class GiteeReleaseParseSuccess extends GiteeReleaseParseResult {
  const GiteeReleaseParseSuccess(this.release);

  final AppRelease release;
}

final class GiteeReleaseParseFailure extends GiteeReleaseParseResult {
  const GiteeReleaseParseFailure(this.failure);

  final AppUpdateFailure failure;
}

final class GiteeReleaseParser {
  GiteeReleaseParser({
    AppVersionCodec versionCodec = const AppVersionCodec(),
    Uri? releasePageUrl,
  }) : _versionCodec = versionCodec,
       _releasePageUrl = releasePageUrl ?? productionReleasePageUrl;

  static final Uri productionReleasePageUrl = Uri.https(
    'gitee.com',
    '/QAQadws/y300-releases/releases',
  );

  static const String _assetPrefix = 'y300-v';
  static const String _assetSuffix = '-android-arm64-v8a-release.apk';

  final AppVersionCodec _versionCodec;
  final Uri _releasePageUrl;

  GiteeReleaseParseResult parse(Object? payload) {
    final dtoResult = _parseDto(payload);
    if (dtoResult case _GiteeDtoFailure(:final failure)) {
      return GiteeReleaseParseFailure(failure);
    }
    final dto = (dtoResult as _GiteeDtoSuccess).dto;
    final semanticVersion = _versionCodec.parseReleaseTag(dto.tagName);
    if (semanticVersion == null) {
      return _failure(
        AppUpdateFailureCode.invalidTag,
        'Release tag must use v{major}.{minor}.{patch}.',
        field: 'tag_name',
      );
    }
    if (dto.prerelease) {
      return _failure(
        AppUpdateFailureCode.prerelease,
        'Prerelease entries are not eligible for stable updates.',
        field: 'prerelease',
      );
    }

    final versionName = semanticVersion.toString();
    final expectedAssetName = '$_assetPrefix$versionName$_assetSuffix';
    final expectedChecksumAssetName = '$expectedAssetName.sha256';
    final matchingAssets = dto.assets
        .where((asset) => asset.name == expectedAssetName)
        .toList(growable: false);
    if (matchingAssets.isEmpty) {
      return _failure(
        AppUpdateFailureCode.assetMissing,
        'The release does not contain the expected Android arm64 APK.',
        field: 'assets',
      );
    }
    if (matchingAssets.length != 1) {
      return _failure(
        AppUpdateFailureCode.assetAmbiguous,
        'The release contains more than one matching Android arm64 APK.',
        field: 'assets',
      );
    }

    final matchingChecksumAssets = dto.assets
        .where((asset) => asset.name == expectedChecksumAssetName)
        .toList(growable: false);
    if (matchingChecksumAssets.isEmpty) {
      return _failure(
        AppUpdateFailureCode.checksumAssetMissing,
        'The release does not contain the required APK checksum asset.',
        field: 'assets',
      );
    }
    if (matchingChecksumAssets.length != 1) {
      return _failure(
        AppUpdateFailureCode.checksumAssetAmbiguous,
        'The release contains more than one matching APK checksum asset.',
        field: 'assets',
      );
    }

    final assetDto = matchingAssets.single;
    final downloadUrl = Uri.tryParse(assetDto.browserDownloadUrl);
    if (downloadUrl == null ||
        downloadUrl.scheme != 'https' ||
        downloadUrl.host.isEmpty) {
      return _failure(
        AppUpdateFailureCode.invalidAssetUrl,
        'The matching APK must have an absolute HTTPS download URL.',
        field: 'assets.browser_download_url',
      );
    }
    final checksumAssetDto = matchingChecksumAssets.single;
    final checksumDownloadUrl = Uri.tryParse(
      checksumAssetDto.browserDownloadUrl,
    );
    if (checksumDownloadUrl == null ||
        checksumDownloadUrl.scheme != 'https' ||
        checksumDownloadUrl.host.isEmpty) {
      return _failure(
        AppUpdateFailureCode.invalidChecksumAssetUrl,
        'The matching checksum must have an absolute HTTPS download URL.',
        field: 'assets.browser_download_url',
      );
    }

    final releasedAt = dto.createdAt == null
        ? null
        : DateTime.tryParse(dto.createdAt!)?.toUtc();
    return GiteeReleaseParseSuccess(
      AppRelease(
        tag: dto.tagName,
        versionName: versionName,
        semanticVersion: semanticVersion,
        title: dto.name.isEmpty ? dto.tagName : dto.name,
        releaseNotes: dto.body,
        releasedAt: releasedAt,
        releasePageUrl: _releasePageUrl,
        apk: AppReleaseAsset(
          name: assetDto.name,
          downloadUrl: downloadUrl,
          abi: AppReleaseAbi.androidArm64V8a,
          checksum: AppReleaseChecksumAsset(
            name: checksumAssetDto.name,
            downloadUrl: checksumDownloadUrl,
          ),
        ),
      ),
    );
  }

  _GiteeDtoParseResult _parseDto(Object? payload) {
    if (payload is! Map) {
      return _dtoFailure(
        AppUpdateFailureCode.invalidPayload,
        'Gitee release payload must be a JSON object.',
      );
    }
    final map = payload.map((key, value) => MapEntry(key.toString(), value));

    final tagName = _requiredString(map, 'tag_name');
    if (tagName case _FieldFailure(:final failure)) {
      return _GiteeDtoFailure(failure);
    }
    final prerelease = _requiredBool(map, 'prerelease');
    if (prerelease case _FieldFailure(:final failure)) {
      return _GiteeDtoFailure(failure);
    }
    final rawAssets = map['assets'];
    if (rawAssets == null) {
      return _dtoFailure(
        AppUpdateFailureCode.missingRequiredField,
        'Required field is missing.',
        field: 'assets',
      );
    }
    if (rawAssets is! List) {
      return _dtoFailure(
        AppUpdateFailureCode.invalidFieldType,
        'Field must be a JSON array.',
        field: 'assets',
      );
    }

    final assets = <GiteeReleaseAssetDto>[];
    for (final rawAsset in rawAssets) {
      if (rawAsset is! Map) {
        continue;
      }
      final assetMap = rawAsset.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final name = assetMap['name'];
      final browserDownloadUrl = assetMap['browser_download_url'];
      if (name is String && browserDownloadUrl is String) {
        assets.add(
          GiteeReleaseAssetDto(
            name: name,
            browserDownloadUrl: browserDownloadUrl,
          ),
        );
      }
    }

    return _GiteeDtoSuccess(
      GiteeReleaseDto(
        tagName: (tagName as _FieldSuccess<String>).value,
        name: _optionalString(map['name']),
        body: _optionalString(map['body']),
        prerelease: (prerelease as _FieldSuccess<bool>).value,
        createdAt: map['created_at'] is String
            ? map['created_at'] as String
            : null,
        assets: List<GiteeReleaseAssetDto>.unmodifiable(assets),
      ),
    );
  }

  _FieldResult<String> _requiredString(Map<String, Object?> map, String field) {
    final value = map[field];
    if (value == null) {
      return _FieldFailure(
        AppUpdateFailure(
          code: AppUpdateFailureCode.missingRequiredField,
          message: 'Required field is missing.',
          field: field,
        ),
      );
    }
    if (value is! String || value.isEmpty) {
      return _FieldFailure(
        AppUpdateFailure(
          code: AppUpdateFailureCode.invalidFieldType,
          message: 'Field must be a non-empty string.',
          field: field,
        ),
      );
    }
    return _FieldSuccess<String>(value);
  }

  _FieldResult<bool> _requiredBool(Map<String, Object?> map, String field) {
    final value = map[field];
    if (value == null) {
      return _FieldFailure(
        AppUpdateFailure(
          code: AppUpdateFailureCode.missingRequiredField,
          message: 'Required field is missing.',
          field: field,
        ),
      );
    }
    if (value is! bool) {
      return _FieldFailure(
        AppUpdateFailure(
          code: AppUpdateFailureCode.invalidFieldType,
          message: 'Field must be a boolean.',
          field: field,
        ),
      );
    }
    return _FieldSuccess<bool>(value);
  }

  String _optionalString(Object? value) => value is String ? value : '';

  GiteeReleaseParseFailure _failure(
    AppUpdateFailureCode code,
    String message, {
    String? field,
  }) {
    return GiteeReleaseParseFailure(
      AppUpdateFailure(code: code, message: message, field: field),
    );
  }

  _GiteeDtoFailure _dtoFailure(
    AppUpdateFailureCode code,
    String message, {
    String? field,
  }) {
    return _GiteeDtoFailure(
      AppUpdateFailure(code: code, message: message, field: field),
    );
  }
}

sealed class _GiteeDtoParseResult {
  const _GiteeDtoParseResult();
}

final class _GiteeDtoSuccess extends _GiteeDtoParseResult {
  const _GiteeDtoSuccess(this.dto);

  final GiteeReleaseDto dto;
}

final class _GiteeDtoFailure extends _GiteeDtoParseResult {
  const _GiteeDtoFailure(this.failure);

  final AppUpdateFailure failure;
}

sealed class _FieldResult<T> {
  const _FieldResult();
}

final class _FieldSuccess<T> extends _FieldResult<T> {
  const _FieldSuccess(this.value);

  final T value;
}

final class _FieldFailure<T> extends _FieldResult<T> {
  const _FieldFailure(this.failure);

  final AppUpdateFailure failure;
}
