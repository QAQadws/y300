import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/profile/domain/models/current_user_profile_models.dart';

enum CurrentUserProfileCapability {
  stableUserIdentity,
  userName,
  avatarReference,
  groupIdentity,
  creditTotal,
  postCount,
  threadCount,
}

final class CurrentUserProfileSourceCapabilities {
  const CurrentUserProfileSourceCapabilities({required this.values});

  final DataCapabilitySet<CurrentUserProfileCapability> values;

  bool supports(CurrentUserProfileCapability capability) {
    return values.supports(capability);
  }

  CurrentUserProfileReadCapabilities toReadCapabilities() {
    return CurrentUserProfileReadCapabilities(values: values);
  }
}

final class CurrentUserProfileReadCapabilities {
  const CurrentUserProfileReadCapabilities({required this.values});

  final DataCapabilitySet<CurrentUserProfileCapability> values;

  bool supports(CurrentUserProfileCapability capability) {
    return values.supports(capability);
  }

  CurrentUserProfileReadCapabilities intersect(
    CurrentUserProfileReadCapabilities other,
  ) {
    return CurrentUserProfileReadCapabilities(
      values: values.intersect(other.values),
    );
  }
}

abstract interface class CurrentUserProfileRepository {
  CurrentUserProfileSourceCapabilities get capabilities;

  Future<
    DataReadResult<CurrentUserProfileData, CurrentUserProfileReadCapabilities>
  >
  load(
    CurrentUserProfileQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });
}
