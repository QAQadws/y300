import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:version/version.dart';
import 'package:y300/features/app_update/domain/services/app_version_codec.dart';
import 'package:y300/features/app_update/presentation/app_release_notes_page.dart';
import 'package:y300/features/app_update/presentation/widgets/app_update_check_tile.dart';
import 'package:y300/features/more/data/about_providers.dart';
import 'package:y300/features/more/domain/models/about_app_info.dart';
import 'package:y300/features/more/presentation/more_debug_tools.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class AboutPage extends ConsumerStatefulWidget {
  const AboutPage({super.key});

  static final Uri githubRepositoryUri = Uri.parse(
    'https://github.com/QAQadws/y300',
  );

  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage> {
  static const AppVersionCodec _versionCodec = AppVersionCodec();

  final MoreDebugTools _debugTools = MoreDebugTools();

  @override
  Widget build(BuildContext context) {
    final appInfo = ref.watch(aboutAppInfoProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              key: const Key('about-page-list'),
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                _AboutHeader(
                  appInfo: appInfo.value,
                  onIconTap: () => _debugTools.handleAboutTap(context, ref),
                ),
                const _AboutSectionLabel('版本'),
                const AppUpdateCheckTile(showVersionSubtitle: false),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  key: const Key('about-release-notes-entry'),
                  leading: const Icon(Icons.history_outlined),
                  title: const Text('更新日志'),
                  trailing: const Icon(Icons.chevron_right),
                  enabled: _installedVersion(appInfo.value) != null,
                  onTap: () => _openReleaseNotes(appInfo.value),
                ),
                const SizedBox(height: 12),
                const _AboutSectionLabel('项目'),
                ListTile(
                  key: const Key('about-github-entry'),
                  leading: const FaIcon(FontAwesomeIcons.github),
                  title: const Text('GitHub 仓库'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: _openGitHubRepository,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Version? _installedVersion(AboutAppInfo? appInfo) {
    if (appInfo == null) {
      return null;
    }
    return _versionCodec.parseVersionName(appInfo.version.trim());
  }

  void _openReleaseNotes(AboutAppInfo? appInfo) {
    final installedVersion = _installedVersion(appInfo);
    if (installedVersion == null) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AppReleaseNotesPage(installedVersion: installedVersion),
      ),
    );
  }

  Future<void> _openGitHubRepository() async {
    var opened = false;
    try {
      opened = await ref
          .read(aboutExternalLinkLauncherProvider)
          .open(AboutPage.githubRepositoryUri);
    } on Object {
      opened = false;
    }
    if (!mounted || opened) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('无法打开 GitHub 仓库')));
  }
}

class _AboutHeader extends StatelessWidget {
  const _AboutHeader({required this.appInfo, required this.onIconTap});

  final AboutAppInfo? appInfo;
  final VoidCallback onIconTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      child: Column(
        children: [
          GestureDetector(
            key: const Key('about-app-icon-tap-target'),
            behavior: HitTestBehavior.opaque,
            onTap: onIconTap,
            child: Image.asset(
              'assets/app_icon_transparent.png',
              width: 88,
              height: 88,
              filterQuality: FilterQuality.medium,
            ),
          ),
          const SizedBox(height: 14),
          Text('Y300', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            appInfo?.displayVersion ?? '版本读取中',
            key: const Key('about-version-label'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutSectionLabel extends StatelessWidget {
  const _AboutSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
