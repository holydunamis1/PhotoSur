import 'package:flutter_test/flutter_test.dart';
import 'package:katharerase/core/models/batch_progress.dart';

void main() {
  test('starts with every photo waiting', () {
    final p = BatchProgress.initial(3);
    expect(p.total, 3);
    expect(p.items.every((s) => s == BatchItemStatus.waiting), isTrue);
    expect(p.processedCount, 0);
    expect(p.running, isFalse);
    expect(p.finished, isFalse);
  });

  test('withItem updates one photo and leaves the original untouched', () {
    final p = BatchProgress.initial(3);
    final q = p
        .withItem(0, BatchItemStatus.done)
        .withItem(1, BatchItemStatus.failed)
        .withItem(2, BatchItemStatus.working);
    expect(q.doneCount, 1);
    expect(q.failedCount, 1);
    expect(q.processedCount, 2);
    expect(p.doneCount, 0);
  });
}
