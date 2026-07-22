import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:y300/features/more/domain/models/about_app_info.dart';
import 'package:y300/features/more/domain/services/about_external_link_launcher.dart';

final aboutAppInfoProvider = FutureProvider<AboutAppInfo>((ref) async {
  final packageInfo = await PackageInfo.fromPlatform();
  return AboutAppInfo(
    version: packageInfo.version,
    buildNumber: packageInfo.buildNumber,
  );
});

final aboutExternalLinkLauncherProvider = Provider<AboutExternalLinkLauncher>((
  ref,
) {
  return const _UrlLauncherAboutExternalLinkLauncher();
});

final class _UrlLauncherAboutExternalLinkLauncher
    implements AboutExternalLinkLauncher {
  const _UrlLauncherAboutExternalLinkLauncher();

  @override
  Future<bool> open(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
