import 'dart:async';

import 'package:photosur/core/services/consent_flow.dart';
import 'package:photosur/platform/ad_service.dart';

/// Runs before every test file. The real Google consent calls need the ads
/// plugin, which does not exist in a unit test (the calls would never
/// answer), so tests use a gateway whose update fails at once. Ad loading
/// then fails the same way it did before consent was added.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AdService.instance.consentGatewayOverride = ConsentGateway(
    requestInfoUpdate: () async => throw 'no ads plugin in tests',
    showFormIfRequired: () async {},
    canRequestAds: () async => true,
    privacyOptionsRequired: () async => false,
    showPrivacyOptions: () async {},
  );
  await testMain();
}
