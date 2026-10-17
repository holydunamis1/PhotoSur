import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photosur/core/services/segmentation_service.dart';
import 'package:photosur/core/utils/constants.dart';

const int _inLen = kModelInputSize * kModelInputSize * 3;
const int _outLen = kModelInputSize * kModelInputSize;

void main() {
  group('SegmentationService.infer', () {
    test('returns the runner output when sizes are correct', () async {
      var calls = 0;
      final service = SegmentationService.forTesting((input) async {
        calls++;
        return Float32List(_outLen)..fillRange(0, _outLen, 0.5);
      });

      final out = await service.infer(Float32List(_inLen));

      expect(out.length, _outLen);
      expect(out.first, 0.5);
      expect(calls, 1);
      expect(service.lastError, isNull);
    });

    test('wrong input length throws SegmentationException without running',
        () async {
      var calls = 0;
      final service = SegmentationService.forTesting((input) async {
        calls++;
        return Float32List(_outLen);
      });

      await expectLater(
        service.infer(Float32List(10)),
        throwsA(isA<SegmentationException>()),
      );
      expect(calls, 0);
      expect(service.lastError, isNotNull);
    });

    test('runner failure is wrapped in SegmentationException', () async {
      final service = SegmentationService.forTesting(
        (input) async => throw Exception('simulated native failure'),
      );

      await expectLater(
        service.infer(Float32List(_inLen)),
        throwsA(isA<SegmentationException>()),
      );
      expect(service.lastError, contains('simulated native failure'));
    });

    test('wrong output length is reported as a failure', () async {
      final service = SegmentationService.forTesting(
        (input) async => Float32List(5),
      );

      await expectLater(
        service.infer(Float32List(_inLen)),
        throwsA(isA<SegmentationException>()),
      );
    });
  });

  group('SegmentationService batch session', () {
    test('beginBatch and endBatch are safe no-ops without an HD model', () async {
      var calls = 0;
      final service = SegmentationService.forTesting((input) async {
        calls++;
        return Float32List(_outLen);
      });

      await service.beginBatch();
      await service.infer(Float32List(_inLen));
      await service.infer(Float32List(_inLen));
      await service.endBatch();
      await service.endBatch(); // closing twice is fine

      expect(calls, 2);
      expect(service.lastError, isNull);
    });
  });
}
