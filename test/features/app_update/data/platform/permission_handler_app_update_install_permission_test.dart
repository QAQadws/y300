import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/app_update/data/platform/permission_handler_app_update_install_permission.dart';
import 'package:y300/features/app_update/domain/models/app_update_install_permission.dart';

void main() {
  test(
    'does not request Android install permission on unsupported platforms',
    () async {
      const gateway = PermissionHandlerAppUpdateInstallPermission();

      expect(
        await gateway.ensureGranted(),
        AppUpdateInstallPermissionStatus.unsupported,
      );
      expect(await gateway.openSettings(), isFalse);
    },
  );
}
