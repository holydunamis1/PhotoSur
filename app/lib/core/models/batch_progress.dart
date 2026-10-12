import 'package:freezed_annotation/freezed_annotation.dart';

part 'batch_progress.freezed.dart';

/// Where one photo of a batch run is.
enum BatchItemStatus { waiting, working, done, failed }

/// Progress of a batch run, one status per photo. Held in memory only.
@freezed
abstract class BatchProgress with _$BatchProgress {
  const BatchProgress._();

  const factory BatchProgress({
    required List<BatchItemStatus> items,
    @Default(false) bool running,
    @Default(false) bool finished,
  }) = _BatchProgress;

  factory BatchProgress.initial(int count) => BatchProgress(
        items: List<BatchItemStatus>.filled(count, BatchItemStatus.waiting),
      );

  int get total => items.length;
  int get doneCount =>
      items.where((s) => s == BatchItemStatus.done).length;
  int get failedCount =>
      items.where((s) => s == BatchItemStatus.failed).length;

  /// Photos that are finished one way or the other.
  int get processedCount => doneCount + failedCount;

  BatchProgress withItem(int index, BatchItemStatus status) {
    final next = [...items];
    next[index] = status;
    return copyWith(items: next);
  }
}
