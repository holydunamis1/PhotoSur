import 'package:flutter/services.dart';

/// Free bytes on the app's storage volume (Android only). Returns null on
/// any failure or on platforms without the channel, so callers skip the
/// check instead of blocking.
Future<int?> readFreeBytes() async {
  try {
    final v = await const MethodChannel('photosur/storage')
        .invokeMethod<num>('freeBytes');
    return v?.toInt();
  } catch (_) {
    return null;
  }
}
