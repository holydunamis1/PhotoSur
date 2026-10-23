
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../core/models/export_job.dart';
import '../core/services/storage_service.dart';
import '../core/utils/constants.dart';
import '../core/theme/app_tokens.dart';
import '../generated/l10n/app_localizations.dart';
import '../widgets/ad_banner_slot.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/brand_wordmark.dart';
import '../widgets/empty_state.dart';
import '../widgets/export_actions.dart';
import '../widgets/home_backdrop_strip.dart';
import '../widgets/preference_sheets.dart';
import '../widgets/recent_export_tile.dart';
import '../widgets/toast_notification.dart';
import 'export_viewer_screen.dart';

/// Wordmark left; language, theme and settings icons right. Two big buttons
/// (Camera, Gallery), recent exports grid (last 6), banner ad at the bottom.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<ExportJob> _recentExports = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    StorageService.instance.historyRevision.addListener(_loadRecent);
    _loadRecent();
  }

  @override
  void dispose() {
    StorageService.instance.historyRevision.removeListener(_loadRecent);
    super.dispose();
  }

  Future<void> _loadRecent() async {
    try {
      final jobs = await StorageService.instance.getRecentExportJobs(limit: 6);
      if (mounted) setState(() => _recentExports = jobs);
    } catch (e) {
      // Storage failure shouldn't block the home screen — just show the
      // empty state as if there were no exports yet.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickFromGallery(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null || !context.mounted) return;
      context.push('/crop', extra: picked.path);
    } catch (e) {
      if (context.mounted) {
        ToastNotification.show(
          context,
          message: l10n.homeGalleryOpenFailed,
          type: ToastType.error,
        );
      }
    }
  }

  /// Several photos at once, cut out one after another on the batch screen.
  Future<void> _pickBatch(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    try {
      final picked =
          await ImagePicker().pickMultiImage(limit: kMaxBatchPhotos);
      if (picked.isEmpty || !context.mounted) return;
      final paths = [for (final f in picked.take(kMaxBatchPhotos)) f.path];
      if (picked.length > kMaxBatchPhotos) {
        ToastNotification.show(
          context,
          message: l10n.batchTooMany(kMaxBatchPhotos),
          type: ToastType.info,
        );
      }
      context.push('/batch', extra: paths);
    } catch (e) {
      if (context.mounted) {
        ToastNotification.show(
          context,
          message: l10n.homeGalleryOpenFailed,
          type: ToastType.error,
        );
      }
    }
  }

  Widget _recentSection() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_recentExports.isEmpty) return const EmptyState();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: _recentExports.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, i) {
        final job = _recentExports[i];
        return RecentExportTile(
          job: job,
          onTap: () => context.push(
            '/export-viewer',
            extra: ExportViewerArgs(jobs: _recentExports, index: i),
          ),
          onMore: () => showExportActions(context, job),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AppScaffold(
      appBar: AppBar(
        centerTitle: false,
        title: const BrandWordmark(),
        actions: [
          IconButton(
            tooltip: l10n.helpTitle,
            icon: const Icon(Icons.help_outline_rounded),
            onPressed: () => context.push('/help'),
          ),
          IconButton(
            tooltip: l10n.settingsLanguage,
            icon: const Icon(Icons.translate),
            onPressed: () => showLanguageSheet(context),
          ),
          IconButton(
            tooltip: l10n.settingsTheme,
            icon: const Icon(Icons.palette_outlined),
            onPressed: () => showThemeSheet(context),
          ),
          IconButton(
            tooltip: l10n.settingsTitle,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
        onRefresh: _loadRecent,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _ActionCard(
                            icon: Icons.photo_camera_rounded,
                            label: l10n.homeCameraButton,
                            onTap: () => context.push('/camera'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _ActionCard(
                            icon: Icons.photo_library_rounded,
                            label: l10n.homeGalleryButton,
                            onTap: () => _pickFromGallery(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _BatchTile(
                      label: l10n.homeBatchButton,
                      onTap: () => _pickBatch(context),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.homeRecentExports,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (_recentExports.isNotEmpty)
                          TextButton(
                            onPressed: () => context.push('/exports'),
                            child: Text(l10n.homeSeeAll),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            // The Recent Exports section: fills the space down to the ad
            // banner when short, grows with the grid when tall.
            SliverFillRemaining(
              hasScrollBody: false,
              child: HomeBackdropStrip(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: _recentSection(),
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
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.l),
          side: BorderSide(color: p.separator, width: 0.5),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.l),
          ),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: p.accentTint,
                    borderRadius: BorderRadius.circular(AppRadius.m),
                  ),
                  child: Icon(icon, size: 26, color: p.accentText),
                ),
                const SizedBox(height: AppSpace.xl),
                Text(label, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BatchTile extends StatelessWidget {
  const _BatchTile({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.l),
          side: BorderSide(color: p.separator, width: 0.5),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.l),
          ),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.l,
              vertical: AppSpace.m,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: p.accentTint,
                    borderRadius: BorderRadius.circular(AppRadius.m),
                  ),
                  child: Icon(Icons.collections_rounded,
                      size: 22, color: p.accentText),
                ),
                const SizedBox(width: AppSpace.m),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
