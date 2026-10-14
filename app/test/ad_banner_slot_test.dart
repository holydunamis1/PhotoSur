import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosur/core/providers/settings_provider.dart';
import 'package:photosur/core/providers/subscription_provider.dart';
import 'package:photosur/widgets/ad_banner_slot.dart';
import 'package:provider/provider.dart';

Widget _host(SubscriptionProvider subscription) {
  Provider.debugCheckInvalidValueType = null;
  return MaterialApp(
    home: Provider<SubscriptionProvider>.value(
      value: subscription,
      child: const Scaffold(
        body: Column(
          children: [
            Expanded(child: SizedBox.expand(key: ValueKey('content'))),
            AdBannerSlot(personalized: false),
          ],
        ),
      ),
    ),
  );
}

double _contentHeight(WidgetTester tester) =>
    tester.getSize(find.byKey(const ValueKey('content'))).height;

void main() {
  testWidgets('slot holds its final height while the ad loads (no jump)',
      (tester) async {
    final subscription = SubscriptionProvider(SettingsProvider());
    await tester.pumpWidget(_host(subscription));
    await tester.pump();
    final screen = tester.view.physicalSize.height / tester.view.devicePixelRatio;

    expect(kAdBannerSlotHeight, kAdBannerHeight + kAdBannerGap);
    expect(_contentHeight(tester), closeTo(screen - kAdBannerSlotHeight, 0.5));

    // Let the load time out so no timer is left pending.
    await tester.pump(const Duration(seconds: 31));
  });

  testWidgets('slot collapses to zero after the ad fails to load',
      (tester) async {
    final subscription = SubscriptionProvider(SettingsProvider());
    await tester.pumpWidget(_host(subscription));
    await tester.pump();
    // The load gives up after its timeout; the fake clock covers it.
    await tester.pump(const Duration(seconds: 31));
    await tester.pump();
    final screen = tester.view.physicalSize.height / tester.view.devicePixelRatio;

    expect(_contentHeight(tester), closeTo(screen, 0.5));
  });

  testWidgets('ad-free users never reserve any space', (tester) async {
    final subscription = SubscriptionProvider(SettingsProvider());
    subscription.value = true;
    await tester.pumpWidget(_host(subscription));
    await tester.pump();
    final screen = tester.view.physicalSize.height / tester.view.devicePixelRatio;

    expect(_contentHeight(tester), closeTo(screen, 0.5));
  });
}
