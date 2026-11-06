import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/android_core.dart';
import '../core/core_api.dart';
import '../core/core_controller.dart';
import '../core/models.dart';
import '../l10n/app_localizations.dart';
import 'widgets.dart';

/// A backup file: the core's data folder (accounts and settings) as a
/// zip file in the same layout, so it can also be unzipped into another
/// device's data folder by hand. The core makes it and takes it in
/// (GET /api/backup, POST /api/backup/import); the app only saves and
/// opens the file.
const _zip = XTypeGroup(
  label: 'ZIP',
  extensions: ['zip'],
  mimeTypes: [
    'application/zip',
    'application/x-zip-compressed',
    'application/octet-stream',
  ],
  uniformTypeIdentifiers: ['public.zip-archive'],
);

/// The accounts page's "more" button, beside Add account: save a backup,
/// or add the accounts of one.
class BackupMenuButton extends StatelessWidget {
  const BackupMenuButton({super.key, required this.core});

  final CoreController core;

  Future<void> _export(BuildContext context) async {
    final api = core.api;
    if (api == null) return;
    final l = AppLocalizations.of(context);
    String? saved;
    await runShowingErrors(context, () async {
      final file = await api.exportBackup();
      saved = await _save(file.name, file.bytes);
    });
    if (saved != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.backupSaved(saved!))));
    }
  }

  Future<void> _import(BuildContext context) async {
    final api = core.api;
    if (api == null) return;
    final l = AppLocalizations.of(context);
    Uint8List? zip;
    BackupContents? contents;
    await runShowingErrors(context, () async {
      zip = await _open();
      if (zip != null) contents = await api.inspectBackup(zip!);
    });
    if (zip == null || contents == null || !context.mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => _ImportDialog(contents: contents!),
    );
    if (go != true || !context.mounted) return;
    BackupImported? done;
    await runShowingErrors(context, () async {
      done = await api.importBackup(zip!);
      await core.refresh(accountsToo: true);
    });
    if (done != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.backupImported(done!.added + done!.updated))),
      );
    }
  }

  /// Saves the file where the user picks; its name, or null when the
  /// user backed out.
  static Future<String?> _save(String name, Uint8List bytes) async {
    try {
      if (Platform.isAndroid) return await AndroidCore.saveFile(name, bytes);
      final location = await getSaveLocation(
        suggestedName: name,
        acceptedTypeGroups: const [_zip],
      );
      if (location == null) return null;
      await File(location.path).writeAsBytes(bytes, flush: true);
      return location.path.split(Platform.pathSeparator).last;
    } on FileSystemException catch (e) {
      throw CoreApiException(0, e.message);
    }
  }

  /// The file the user picks, or null when the user backed out.
  static Future<Uint8List?> _open() async {
    // Android's own: file_selector reads as many bytes as the provider says
    // the file has, which is 0 for a file saved through it.
    if (Platform.isAndroid) {
      try {
        return await AndroidCore.openFile();
      } on PlatformException catch (e) {
        throw CoreApiException(0, e.message ?? e.code);
      }
    }
    final file = await openFile(acceptedTypeGroups: const [_zip]);
    try {
      return await file?.readAsBytes();
    } on FileSystemException catch (e) {
      throw CoreApiException(0, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // The tooltip is Flutter's own "Show menu", in the app's language.
    return PopupMenuButton<bool>(
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (export) => export ? _export(context) : _import(context),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: true,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.save_alt_rounded),
            title: Text(l.backupExport),
          ),
        ),
        PopupMenuItem(
          value: false,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.file_open_outlined),
            title: Text(l.backupImport),
          ),
        ),
      ],
    );
  }
}

/// The accounts of a backup file, before they are added.
class _ImportDialog extends StatelessWidget {
  const _ImportDialog({required this.contents});

  final BackupContents contents;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l.backupImportTitle),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final a in contents.accounts)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.account_circle_outlined),
                  // An email reads left to right in every language.
                  title: Text(a.email, textDirection: TextDirection.ltr),
                  subtitle: a.exists
                      ? Text(
                          l.backupAccountExists,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        )
                      : null,
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l.backupImportAction),
        ),
      ],
    );
  }
}
