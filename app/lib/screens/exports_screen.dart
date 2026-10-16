import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/models/export_job.dart';
import '../core/services/export_library_service.dart';
import '../core/services/storage_service.dart';
import '../core/theme/app_tokens.dart';
import '../core/utils/export_grouping.dart';
import '../core/utils/extensions.dart';
import '../generated/l10n/app_localizations.dart';
import '../widgets/ad_banner_slot.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/empty_state.dart';
import '../widgets/export_actions.dart';
import '../widgets/recent_export_tile.dart';
import 'export_viewer_screen.dart';

/// Every export, newest first, grouped by age, with a Select mode for
/// deleting several at once and the space exports use on this phone.
class ExportsScreen extends StatefulWidget {
  const ExportsScreen({super.key});

  @override
  State<ExportsScreen> createState() => _ExportsScreenState();
}

class _ExportsScreenState extends State<ExportsScreen> {
  List<ExportJob> _jobs = const [];
  bool _loading = true;
  bool _selecting = false;
  int _bytes = 0;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    StorageService.instance.historyRevision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    StorageService.instance.historyRevision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final jobs = await ExportLibraryService.instance.loadAll();
      final bytes = await ExportLibraryService.instance.totalBytes();
      if (!mounted) return;
      setState(() {
        _jobs = jobs;
        _bytes = bytes;
        _selected.removeWhere((id) => !jobs.any((j) => j.id == id));
        if (jobs.isEmpty) _selecting = false;
      });
    } catch (_) {
      // Show whatever is already on screen; the empty state covers a first
      // failure.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggle(ExportJob job) {
    setState(() {
      if (!_selected.remove(job.id)) _selected.add(job.id);
    });
  }

  void _openViewer(int index) {
    context.push('/export-viewer',
        extra: ExportViewerArgs(jobs: _jobs, index: index));
  }

  Future<void> _deleteSelected() async {
    final chosen = _jobs.where((j) => _selected.contains(j.id)).toList();
    final deleted = await deleteExportsWithConfirm(context, chosen);
    if (deleted && mounted) {
      setState(() {
        _selected.clear();
        _selecting = false;
      });
    }
  }

  Future<void> _shareSelected() {
    final chosen = _jobs.where((j) => _selected.contains(j.id)).toList();
    return shareExports(context, chosen);
  }

  Future<void> _deleteAll() async {
    final deleted = await deleteExportsWithConfirm(context, _jobs, all: true);
    if (deleted && mounted) setState(() => _selecting = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = context.palette;
    final groups = groupExports(_jobs, DateTime.now());

    final actions = <Widget>[
      if (_jobs.isNotEmpty && !_selecting)
        TextButton(
          onPressed: () => setState(() => _selecting = true),
          child: Text(l10n.exportsSelect),
        ),
      if (_selecting)
        TextButton(
          onPressed: () => setState(() {
            _selecting = false;
            _selected.clear();
          }),
          child: Text(l10n.exportsDone),
        ),
      if (_jobs.isNotEmpty && !_selecting)
        PopupMenuButton<int>(
          tooltip: l10n.exportMoreOptions,
          icon: const Icon(Icons.more_horiz_rounded),
          onSelected: (_) => _deleteAll(),
          itemBuilder: (_) => [
            PopupMenuItem<int>(
              value: 0,
              child: Text(
                l10n.exportsDeleteAll,
                style: TextStyle(color: p.danger),
              ),
            ),
          ],
        ),
    ];

    return AppScaffold(
      appBar: AppBar(
        title: Text(
          _selecting
              ? l10n.exportsSelectedCount(_selected.length)
              : l10n.homeRecentExports,
        ),
        actions: actions,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _jobs.isEmpty
              ? const EmptyState()
              : CustomScrollView(
                  slivers: [
                    for (final group in groups) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                              AppSpace.l, AppSpace.l, AppSpace.l, AppSpace.s),
                          child: Text(
                            _groupLabel(l10n, group.age),
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  color: p.text2,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: AppSpace.l),
                        sliver: SliverGrid.builder(
                          itemCount: group.jobs.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: AppSpace.s,
                            crossAxisSpacing: AppSpace.s,
                          ),
                          itemBuilder: (context, i) {
                            final job = group.jobs[i];
                            return RecentExportTile(
                              key: ValueKey(job.id),
                              job: job,
                              selectionMode: _selecting,
                              selected: _selected.contains(job.id),
                              onTap: () => _selecting
                                  ? _toggle(job)
                                  : _openViewer(_jobs.indexOf(job)),
                              onMore: () => _selecting
                                  ? _toggle(job)
                                  : showExportActions(context, job),
                            );
                          },
                        ),
                      ),
                    ],
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: AppSpace.xl, horizontal: AppSpace.l),
                        child: Text(
                          l10n.exportsStorageUsed(_bytes.toHumanFileSize),
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(color: p.text3),
                        ),
                      ),
                    ),
                  ],
                ),
      bottomBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_selecting)
            SafeArea(
              top: false,
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpace.l, AppSpace.s, AppSpace.l, AppSpace.s),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            shape: RoundedSuperellipseBorder(
                              borderRadius: BorderRadius.circular(AppRadius.m),
                            ),
                          ),
                          onPressed: _selected.isEmpty ? null : _shareSelected,
                          icon: const Icon(Icons.ios_share_rounded),
                          label: Text(l10n.exportShare),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpace.s),
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: p.danger,
                            foregroundColor: context.isDarkMode
                                ? const Color(0xFF2A0705)
                                : Colors.white,
                            shape: RoundedSuperellipseBorder(
                              borderRadius: BorderRadius.circular(AppRadius.m),
                            ),
                          ),
                          onPressed: _selected.isEmpty ? null : _deleteSelected,
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: Text(l10n.exportActionDelete),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const AdBannerSlot(personalized: false),
        ],
      ),
    );
  }

  static String _groupLabel(AppLocalizations l10n, ExportAge age) =>
      switch (age) {
        ExportAge.today => l10n.dateToday,
        ExportAge.yesterday => l10n.dateYesterday,
        ExportAge.thisWeek => l10n.exportsGroupThisWeek,
        ExportAge.earlier => l10n.exportsGroupEarlier,
      };
}
