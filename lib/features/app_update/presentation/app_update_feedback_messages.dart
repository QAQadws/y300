import 'package:y300/features/app_update/domain/models/app_update_failure.dart';

String appUpdateDownloadRequestFailureMessage(AppUpdateFailureCode code) {
  return switch (code) {
    AppUpdateFailureCode.networkUnavailable => '网络不可用，无法开始下载更新',
    AppUpdateFailureCode.requestTimeout => '更新检查超时，请稍后重试',
    AppUpdateFailureCode.invalidPayload => '当前更新信息无效，请稍后重试',
    AppUpdateFailureCode.apkDownloadStartFailed => '更新下载正在进行中，请稍候',
    _ => '无法开始更新下载，请稍后重试',
  };
}

String appUpdateCheckFailureMessage(AppUpdateFailureCode code) {
  return switch (code) {
    AppUpdateFailureCode.networkUnavailable => '网络不可用，检查更新失败',
    AppUpdateFailureCode.requestTimeout => '检查更新超时，请稍后重试',
    AppUpdateFailureCode.rateLimited => '检查更新过于频繁，请稍后重试',
    AppUpdateFailureCode.installedVersionUnavailable => '无法读取当前应用版本',
    _ => '检查更新失败，请稍后重试',
  };
}

String appUpdateLaunchFailureMessage(AppUpdateFailureCode code) {
  return switch (code) {
    AppUpdateFailureCode.invalidAssetUrl => '更新下载地址无效，请稍后重试',
    AppUpdateFailureCode.externalLaunchUnavailable => '无法打开下载链接，请确认设备已安装浏览器',
    AppUpdateFailureCode.externalLaunchFailed => '打开下载链接失败，请稍后重试',
    _ => '打开更新下载链接失败，请稍后重试',
  };
}
