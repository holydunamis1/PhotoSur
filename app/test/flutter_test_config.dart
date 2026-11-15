import 'dart:async';

import 'package:photosur/platform/ad_service.dart';

/// Runs before every test file. Unit tests have no ads plugin, so the real
/// Google consent calls would never answer: skip that step here. Ad loading
/// then behaves as it did before consent was added.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AdService.instance.skipConsentForTests = true;
  await testMain();
}
