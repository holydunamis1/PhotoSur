import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:katharerase/core/models/batch_background.dart';
import 'package:katharerase/core/models/editable_image_state.dart';
import 'package:katharerase/core/models/export_job.dart';
import 'package:katharerase/core/utils/marketplace_presets.dart';

MarketplacePreset _p(Marketplace m) =>
    kMarketplacePresets.firstWhere((e) => e.marketplace == m);

void main() {
  test('no preset: transparent stays a PNG, anything else is a JPG', () {
    var r = resolveBatchOutput(const BatchBackground(), null);
    expect(r.format, ExportFormat.png);
    expect(r.background.isTransparent, isTrue);

    r = resolveBatchOutput(
      const BatchBackground(type: BackgroundType.solidColor, color: Color(0xFF3B82F6)),
      null,
    );
    expect(r.format, ExportFormat.jpg);
    expect(r.background.type, BackgroundType.solidColor);
    expect(r.background.color, const Color(0xFF3B82F6));
  });

  test('Amazon forces pure white whatever was chosen', () {
    final r = resolveBatchOutput(
      const BatchBackground(type: BackgroundType.gradient, gradientIndex: 2),
      _p(Marketplace.amazon),
    );
    expect(r.background.type, BackgroundType.white);
    expect(r.format, ExportFormat.jpg);
  });

  test('a JPG preset turns transparent into white; Shopify keeps transparency', () {
    var r = resolveBatchOutput(const BatchBackground(), _p(Marketplace.ebay));
    expect(r.background.type, BackgroundType.white);
    expect(r.format, ExportFormat.jpg);

    r = resolveBatchOutput(const BatchBackground(), _p(Marketplace.shopify));
    expect(r.background.isTransparent, isTrue);
    expect(r.format, ExportFormat.png);
  });

  test('a chosen colour survives a non-white JPG preset', () {
    final r = resolveBatchOutput(
      const BatchBackground(type: BackgroundType.black),
      _p(Marketplace.etsy),
    );
    expect(r.background.type, BackgroundType.black);
    expect(r.format, ExportFormat.jpg);
  });
}
