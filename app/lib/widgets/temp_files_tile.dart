import 'package:flutter/material.dart';

import '../core/services/storage_cleanup.dart';
import '../core/utils/extensions.dart';
import '../generated/l10n/app_localizations.dart';
import 'toast_notification.dart';

/// Settings row: size of temporary files with a Clear button.
class TempFilesTile extends StatefulWidget {
  const TempFilesTile({super.key});

  @override
  State<TempFilesTile> createState() => _TempFilesTileState();
}

class _TempFilesTileState extends State<TempFilesTile> {
  int? _bytes;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final b = await StorageCleanup.instance.tempBytes();
    if (mounted) setState(() => _bytes = b);
  }

  Future<void> _clear() async {
    final l10n = AppLocalizations.of(context);
    await StorageCleanup.instance.clearTemp();
    await _refresh();
    if (!mounted) return;
    ToastNotification.show(context,
        message: l10n.settingsTempFilesCleared, type: ToastType.success);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bytes = _bytes;
    return ListTile(
      leading: const Icon(Icons.cleaning_services_outlined),
      title: Text(l10n.settingsTempFilesTitle),
      subtitle: bytes == null ? null : Text(bytes.toHumanFileSize),
      trailing: TextButton(
        onPressed: (bytes ?? 0) > 0 ? _clear : null,
        child: Text(l10n.settingsTempFilesClear),
      ),
    );
  }
}
