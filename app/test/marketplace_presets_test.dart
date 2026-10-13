import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:katharerase/core/models/export_job.dart';
import 'package:katharerase/core/models/editable_image_state.dart'
    show BackgroundType;
import 'package:katharerase/core/services/export_service.dart';
import 'package:katharerase/core/utils/marketplace_presets.dart';

Uint8List _noisyPng(int size) {
  final image = img.Image(width: size, height: size);
  var seed = 12345;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      image.setPixelRgb(x, y, seed & 255, (seed >> 8) & 255, (seed >> 16) & 255);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  test('preset table matches the rules it was verified against', () {
    MarketplacePreset p(Marketplace m) =>
        kMarketplacePresets.firstWhere((e) => e.marketplace == m);

    final amazon = p(Marketplace.amazon);
    expect((amazon.width, amazon.height), (2000, 2000));
    expect(amazon.pureWhite, isTrue);
    expect(amazon.subjectFill, greaterThanOrEqualTo(0.85));
    expect(amazon.format, ExportFormat.jpg);

    final ebay = p(Marketplace.ebay);
    expect((ebay.width, ebay.height), (1600, 1600));
    expect(ebay.maxBytes, 12000000);

    final etsy = p(Marketplace.etsy);
    expect(etsy.width / etsy.height, closeTo(4 / 3, 0.001));
    expect(etsy.height, greaterThanOrEqualTo(2000)); // shortest side
    expect(etsy.format, ExportFormat.jpg); // Etsy shows transparency as black
    expect(etsy.maxBytes, 1000000);

    final shopify = p(Marketplace.shopify);
    expect((shopify.width, shopify.height), (2048, 2048));
    expect(shopify.width, lessThanOrEqualTo(5000));
    expect(shopify.format, ExportFormat.png);
  });

  test('subject fill: amazon preset makes the product fill about 86%', () {
    const w = 400, h = 300;
    final mask = Uint8List(w * h);
    for (var y = 100; y < 200; y++) {
      for (var x = 150; x < 250; x++) {
        mask[y * w + x] = 255; // 100x100 product
      }
    }
    final amazon =
        kMarketplacePresets.firstWhere((e) => e.marketplace == Marketplace.amazon);
    final fit = marketplaceSubjectLayout(amazon, mask, w, h)!;
    // Photo fits 2000x2000 at 2000/400 = 5x; product 500 px; scale to ~1720.
    final productPx = 100 * (2000 / w) * fit.scale;
    expect(productPx / 2000, closeTo(0.86, 0.01));

    final ebay =
        kMarketplacePresets.firstWhere((e) => e.marketplace == Marketplace.ebay);
    expect(marketplaceSubjectLayout(ebay, mask, w, h), isNull);
  });

  test('JPG is re-encoded to fit the size cap, never below the quality floor',
      () async {
    final png = _noisyPng(400);
    final mask = Uint8List(400 * 400)..fillRange(0, 400 * 400, 255);
    Future<Uint8List> run({int? maxBytes, int minQuality = 60}) =>
        ExportService.instance.compositeAndExport(
          originalBytes: png,
          maskBytes: mask,
          backgroundType: BackgroundType.white,
          format: ExportFormat.jpg,
          quality: 95,
          resizeMode: ResizeMode.original,
          maxBytes: maxBytes,
          minQuality: minQuality,
        );

    final uncapped = await run();
    final cap = (uncapped.length * 0.6).round();
    final capped = await run(maxBytes: cap);
    expect(capped.length, lessThanOrEqualTo(cap));
    expect(capped.length, lessThan(uncapped.length));

    // An impossible cap stops at the floor quality instead of destroying it.
    final floor = await run(maxBytes: 10, minQuality: 80);
    expect(floor.length, greaterThan(10));
    expect(floor.length, lessThan(uncapped.length));
  });
}
