import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/profile/domain/models/forum_user_profile_models.dart';

enum ForumUserProfileCapability {
  stableUserIdentity,
  userName,
  avatarReference,
  coverReference,
  signatureMarkup,
  orderedMetrics,
  orderedDetails,
}

final class ForumUserProfileSourceCapabilities {
  const ForumUserProfileSourceCapabilities({required this.values});

  final DataCapabilitySet<ForumUserProfileCapability> values;

  bool supports(ForumUserProfileCapability capability) {
    return values.supports(capability);
  }

  ForumUserProfileReadCapabilities toReadCapabilities() {
    return ForumUserProfileReadCapabilities(values: values);
  }
}

final class ForumUserProfileReadCapabilities {
  const ForumUserProfileReadCapabilities({required this.values});

  final DataCapabilitySet<ForumUserProfileCapability> values;

  bool supports(ForumUserProfileCapability capability) {
    return values.supports(capability);
  }

  ForumUserProfileReadCapabilities intersect(
    ForumUserProfileReadCapabilities other,
  ) {
    return ForumUserProfileReadCapabilities(
      values: values.intersect(other.values),
    );
  }
}

abstract interface class ForumUserProfileRepository {
  ForumUserProfileSourceCapabilities get capabilities;

  Future<DataReadResult<ForumUserProfileData, ForumUserProfileReadCapabilities>>
  load(
    ForumUserProfileQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });
}
