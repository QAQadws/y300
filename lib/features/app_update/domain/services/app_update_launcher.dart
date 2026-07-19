import 'package:y300/features/app_update/domain/models/app_update_launch_result.dart';

abstract interface class AppUpdateLauncher {
  Future<AppUpdateLaunchResult> openApk(Uri apkUri);
}
