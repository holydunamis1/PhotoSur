import '../models/export_job.dart';
import 'constants.dart';

/// Rough bytes an export needs: the encoded image written twice (the app's
/// own copy and the gallery copy).
int estimateExportBytes(int width, int height, ExportFormat format) {
  final pixels = width * height;
  final one = format == ExportFormat.png ? pixels * 3 : pixels ~/ 2;
  return one * 2;
}

int estimateBatchBytes(int photoCount) => photoCount * kBatchPerPhotoBytes;

/// True when there is room, or when free space is unknown (null): an
/// unreadable value must never block an export.
bool hasEnoughSpace(int? freeBytes, int neededBytes) {
  if (freeBytes == null) return true;
  return freeBytes >= neededBytes + kLowStorageMarginBytes;
}
