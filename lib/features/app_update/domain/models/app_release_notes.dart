import 'package:version/version.dart';

final class AppReleaseNotes {
  const AppReleaseNotes({
    required this.version,
    required this.tag,
    required this.body,
    required this.fetchedAt,
  });

  final Version version;
  final String tag;
  final String body;
  final DateTime fetchedAt;
}
