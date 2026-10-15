import '../models/export_job.dart';

enum ExportAge { today, yesterday, thisWeek, earlier }

class ExportGroup {
  const ExportGroup(this.age, this.jobs);
  final ExportAge age;
  final List<ExportJob> jobs;
}

ExportAge exportAgeOf(DateTime createdAt, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(createdAt.year, createdAt.month, createdAt.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return ExportAge.today;
  if (diff == 1) return ExportAge.yesterday;
  if (diff < 7) return ExportAge.thisWeek;
  return ExportAge.earlier;
}

/// Splits [jobs] (already newest first) into Today / Yesterday / This week /
/// Earlier sections, dropping empty ones and keeping the order.
List<ExportGroup> groupExports(List<ExportJob> jobs, DateTime now) {
  final buckets = {for (final a in ExportAge.values) a: <ExportJob>[]};
  for (final job in jobs) {
    buckets[exportAgeOf(job.createdAt, now)]!.add(job);
  }
  return [
    for (final a in ExportAge.values)
      if (buckets[a]!.isNotEmpty) ExportGroup(a, buckets[a]!),
  ];
}
