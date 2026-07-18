import 'package:y300/features/app_update/domain/models/app_release.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';

sealed class AppReleaseChecksumParseResult {
  const AppReleaseChecksumParseResult();
}

final class AppReleaseChecksumParseSuccess
    extends AppReleaseChecksumParseResult {
  const AppReleaseChecksumParseSuccess(this.checksum);

  final AppReleaseChecksum checksum;
}

final class AppReleaseChecksumParseFailure
    extends AppReleaseChecksumParseResult {
  const AppReleaseChecksumParseFailure(this.failure);

  final AppUpdateFailure failure;
}

final class AppReleaseChecksumParser {
  const AppReleaseChecksumParser();

  static const int maxContentLength = 1024;
  static final RegExp _linePattern = RegExp(r'^([0-9a-f]{64})  ([^\r\n]+)$');

  AppReleaseChecksumParseResult parse({
    required String content,
    required String expectedFileName,
  }) {
    if (content.length > maxContentLength) {
      return _malformed('Checksum response exceeds the 1 KiB limit.');
    }

    final line = _removeSingleTrailingLineEnding(content);
    final match = _linePattern.firstMatch(line);
    if (match == null) {
      return _malformed(
        'Checksum must use canonical sha256sum single-line format.',
      );
    }

    final fileName = match.group(2)!;
    if (fileName != expectedFileName) {
      return AppReleaseChecksumParseFailure(
        AppUpdateFailure(
          code: AppUpdateFailureCode.checksumFileNameMismatch,
          message: 'Checksum file name does not match the release APK.',
          field: 'checksum.file_name',
        ),
      );
    }

    return AppReleaseChecksumParseSuccess(
      AppReleaseChecksum(sha256Hex: match.group(1)!, fileName: fileName),
    );
  }

  String _removeSingleTrailingLineEnding(String content) {
    if (content.endsWith('\r\n')) {
      return content.substring(0, content.length - 2);
    }
    if (content.endsWith('\n')) {
      return content.substring(0, content.length - 1);
    }
    return content;
  }

  AppReleaseChecksumParseFailure _malformed(String message) {
    return AppReleaseChecksumParseFailure(
      AppUpdateFailure(
        code: AppUpdateFailureCode.checksumMalformed,
        message: message,
        field: 'checksum',
      ),
    );
  }
}
