import 'package:y300/features/app_update/domain/models/app_update_checksum.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';

sealed class AppUpdateChecksumParseResult {
  const AppUpdateChecksumParseResult();
}

final class AppUpdateChecksumParseSuccess extends AppUpdateChecksumParseResult {
  const AppUpdateChecksumParseSuccess(this.checksum);

  final AppUpdateChecksum checksum;
}

final class AppUpdateChecksumParseFailure extends AppUpdateChecksumParseResult {
  const AppUpdateChecksumParseFailure(this.failure);

  final AppUpdateFailure failure;
}

final class AppUpdateChecksumParser {
  const AppUpdateChecksumParser();

  static const int maxChecksumCharacters = 1024;
  static final RegExp _canonicalLine = RegExp(r'^([0-9a-fA-F]{64})  (.+)$');

  AppUpdateChecksumParseResult parse(
    String raw, {
    required String expectedFileName,
  }) {
    if (raw.length > maxChecksumCharacters) {
      return const AppUpdateChecksumParseFailure(
        AppUpdateFailure(
          code: AppUpdateFailureCode.checksumContentTooLarge,
          message: 'The checksum response is too large.',
        ),
      );
    }

    var line = raw;
    if (line.endsWith('\r\n')) {
      line = line.substring(0, line.length - 2);
    } else if (line.endsWith('\n')) {
      line = line.substring(0, line.length - 1);
    }
    if (line.contains('\r') || line.contains('\n')) {
      return const AppUpdateChecksumParseFailure(
        AppUpdateFailure(
          code: AppUpdateFailureCode.checksumMalformed,
          message: 'The checksum response must contain exactly one line.',
        ),
      );
    }

    final match = _canonicalLine.firstMatch(line);
    if (match == null) {
      return const AppUpdateChecksumParseFailure(
        AppUpdateFailure(
          code: AppUpdateFailureCode.checksumMalformed,
          message: 'The checksum response is not a canonical sha256sum line.',
        ),
      );
    }

    final fileName = match.group(2)!;
    if (fileName != expectedFileName) {
      return AppUpdateChecksumParseFailure(
        const AppUpdateFailure(
          code: AppUpdateFailureCode.checksumFileNameMismatch,
          message: 'The checksum filename does not match the APK filename.',
          field: 'filename',
        ),
      );
    }
    return AppUpdateChecksumParseSuccess(
      AppUpdateChecksum(
        sha256: match.group(1)!.toLowerCase(),
        fileName: fileName,
      ),
    );
  }
}
