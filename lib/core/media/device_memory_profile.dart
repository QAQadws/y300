import 'dart:io' show Platform;

import 'package:flutter/services.dart';

class DeviceMemoryProfile {
  const DeviceMemoryProfile({required this.isLowRamDevice, this.memoryClassMb});

  final bool isLowRamDevice;
  final int? memoryClassMb;
}

abstract final class DeviceMemoryProfileStore {
  static DeviceMemoryProfile? current;
}

class DeviceMemoryProfileResolver {
  const DeviceMemoryProfileResolver({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  static const MethodChannel _defaultChannel = MethodChannel(
    'com.adws.y300/device_memory',
  );

  final MethodChannel _channel;

  Future<DeviceMemoryProfile?> resolve() async {
    if (!Platform.isAndroid) {
      return null;
    }
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'getProfile',
      );
      if (result == null) {
        return null;
      }
      return DeviceMemoryProfile(
        isLowRamDevice: result['isLowRamDevice'] as bool? ?? false,
        memoryClassMb: (result['memoryClassMb'] as num?)?.toInt(),
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
