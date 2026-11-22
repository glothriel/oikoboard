import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'files.dart';
import 'l10n.dart';

/// "1.2 MB" and the like.
String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var v = bytes.toDouble();
  var u = 0;
  while (v >= 1024 && u < units.length - 1) {
    v /= 1024;
    u++;
  }
  final f = NumberFormat(v < 10 && u > 0 ? '0.#' : '0');
  return '${f.format(v)} ${units[u]}';
}

/// Photos are scaled down to this many pixels on the longer side before
/// upload (a phone photo then takes ~0.5–1 MB).
const _photoMaxSide = 2560.0;
const _photoQuality = 85;

/// A file the user picked, not uploaded yet.
class PickedFile {
  const PickedFile(this.name, this.size, this.read);
  final String name;

  /// Null when unknown.
  final int? size;
  final Future<Uint8List> Function() read;
}

enum _Source { camera, photos, files }

/// Lets the user pick photos (taken now or from the gallery) or any files;
/// the sheet also shows how much of the family storage is used.
Future<List<PickedFile>> pickAttachments(BuildContext context) async {
  final source = await showModalBottomSheet<_Source>(
    context: context,
    showDragHandle: true,
    builder: (_) => const _PickSheet(),
  );
  switch (source) {
    case null:
      return const [];
    case _Source.camera:
      final x = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: _photoMaxSide,
        maxHeight: _photoMaxSide,
        imageQuality: _photoQuality,
      );
      return [if (x != null) PickedFile(x.name, null, x.readAsBytes)];
    case _Source.photos:
      final xs = await ImagePicker().pickMultiImage(
        maxWidth: _photoMaxSide,
        maxHeight: _photoMaxSide,
        imageQuality: _photoQuality,
      );
      return [for (final x in xs) PickedFile(x.name, null, x.readAsBytes)];
    case _Source.files:
      final fs = await FilePicker.pickFiles();
      return [
        for (final f in fs) PickedFile(f.name, f.lengthSync(), f.readAsBytes),
      ];
  }
}

/// The family's storage use, fresh each time a picker opens.
final storageUsageProvider = FutureProvider.autoDispose<StorageUsage>(
  (ref) => ref.watch(fileStoreProvider).usage(),
);

class _PickSheet extends ConsumerWidget {
  const _PickSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final usage = ref.watch(storageUsageProvider).value;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!kIsWeb)
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l.attachTakePhoto),
              onTap: () => Navigator.pop(context, _Source.camera),
            ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(l.attachPhotos),
            onTap: () => Navigator.pop(context, _Source.photos),
          ),
          ListTile(
            leading: const Icon(Icons.attach_file),
            title: Text(l.attachFiles),
            onTap: () => Navigator.pop(context, _Source.files),
          ),
          if (usage != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: usage.quota == 0
                        ? 0
                        : (usage.used / usage.quota).clamp(0, 1).toDouble(),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l.attachStorage(
                      formatBytes(usage.used),
                      formatBytes(usage.quota),
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One file being uploaded; [file] is set once it is.
class PendingUpload {
  PendingUpload(this.name);
  final String name;
  StoredFile? file;
}

/// The uploads of one form (a task, a comment): files are uploaded as soon as
/// they're picked and attached when the form is saved. Failures are dropped
/// and reported with a snackbar.
class AttachmentUploads extends ChangeNotifier {
  AttachmentUploads(this.store, this.messenger, this.l10n);
  final FileStore store;
  final ScaffoldMessengerState messenger;
  final AppLocalizations l10n;
  final items = <PendingUpload>[];
  var _disposed = false;

  bool get busy => items.any((u) => u.file == null);
  List<StoredFile> get files => [for (final u in items) ?u.file];

  Future<void> add(List<PickedFile> picked) async {
    for (final p in picked) {
      if ((p.size ?? 0) > maxFileSize) {
        _report(const FileTooLargeException(), p.name);
        continue;
      }
      final u = PendingUpload(p.name);
      items.add(u);
      _notify();
      try {
        u.file = await store.upload(await p.read(), p.name);
      } catch (e) {
        items.remove(u);
        _report(e, p.name);
      }
      _notify();
    }
  }

  void remove(StoredFile file) {
    items.removeWhere((u) => u.file?.id == file.id);
    _notify();
  }

  void clear() {
    items.clear();
    _notify();
  }

  void _report(Object e, String name) => messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(switch (e) {
        FileTooLargeException() => l10n.attachTooLarge(
          name,
          formatBytes(maxFileSize),
        ),
        StorageFullException() => l10n.attachStorageFull(name),
        _ => l10n.attachUploadFailed(name),
      }),
    ),
  );

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// The paperclip button of a form: pick files and start uploading them.
class AttachButton extends StatelessWidget {
  const AttachButton({super.key, required this.uploads});
  final AttachmentUploads uploads;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: context.l10n.attachAction,
    icon: const Icon(Icons.attach_file),
    onPressed: () async => uploads.add(await pickAttachments(context)),
  );
}

/// Attached files: pictures as thumbnails, other files as chips; tapping one
/// opens it. [uploading] shows files still on their way; [onRemove] adds a
/// remove button to each.
class AttachmentStrip extends StatelessWidget {
  const AttachmentStrip({
    super.key,
    required this.files,
    this.uploading = const [],
    this.onRemove,
  });

  final List<StoredFile> files;
  final List<String> uploading;
  final void Function(StoredFile)? onRemove;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty && uploading.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final f in files)
            _FileTile(
              key: ValueKey(f.id),
              file: f,
              onRemove: onRemove == null ? null : () => onRemove!(f),
            ),
          for (final name in uploading) _UploadingTile(name: name),
        ],
      ),
    );
  }
}

const _thumb = 72.0;

class _FileTile extends ConsumerWidget {
  const _FileTile({super.key, required this.file, this.onRemove});
  final StoredFile file;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(8);
    final Widget body = file.isImage
        ? SizedBox.square(
            dimension: _thumb,
            child: FileImageView(
              file: file,
              fit: BoxFit.cover,
              thumbnail: true,
            ),
          )
        : Container(
            constraints: const BoxConstraints(maxWidth: 220),
            height: _thumb,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            color: theme.colorScheme.surfaceContainerHigh,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_iconFor(file.mime), color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                      Text(
                        formatBytes(file.size),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
    return Tooltip(
      message: file.name,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: radius,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => openStoredFile(context, ref, file),
                child: body,
              ),
            ),
          ),
          if (onRemove != null)
            Positioned(
              top: -8,
              right: -8,
              child: IconButton.filledTonal(
                tooltip: context.l10n.attachRemove,
                visualDensity: VisualDensity.compact,
                iconSize: 14,
                constraints: const BoxConstraints.tightFor(
                  width: 24,
                  height: 24,
                ),
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.close),
                onPressed: onRemove,
              ),
            ),
        ],
      ),
    );
  }

  static IconData _iconFor(String mime) => switch (mime) {
    'application/pdf' => Icons.picture_as_pdf_outlined,
    _ when mime.startsWith('image/') => Icons.image_outlined,
    _ when mime.startsWith('video/') => Icons.movie_outlined,
    _ when mime.startsWith('audio/') => Icons.audiotrack_outlined,
    _ when mime.startsWith('text/') => Icons.description_outlined,
    _ => Icons.insert_drive_file_outlined,
  };
}

class _UploadingTile extends StatelessWidget {
  const _UploadingTile({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: name,
    child: Container(
      width: _thumb,
      height: _thumb,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: const SizedBox.square(
        dimension: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}

/// A stored picture, loaded through the [FileStore].
class FileImageView extends ConsumerStatefulWidget {
  const FileImageView({
    super.key,
    required this.file,
    this.fit = BoxFit.contain,
    this.thumbnail = false,
  });
  final StoredFile file;
  final BoxFit fit;

  /// Decoded small, to save memory.
  final bool thumbnail;

  @override
  ConsumerState<FileImageView> createState() => _FileImageViewState();
}

class _FileImageViewState extends ConsumerState<FileImageView> {
  late Future<Uint8List> _bytes = ref
      .read(fileStoreProvider)
      .bytes(widget.file.id);

  @override
  void didUpdateWidget(FileImageView old) {
    super.didUpdateWidget(old);
    if (old.file.id != widget.file.id) {
      _bytes = ref.read(fileStoreProvider).bytes(widget.file.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snap) {
        if (snap.hasError) {
          return ColoredBox(
            color: colors.surfaceContainerHigh,
            child: Icon(Icons.broken_image_outlined, color: colors.outline),
          );
        }
        final data = snap.data;
        if (data == null) {
          return ColoredBox(color: colors.surfaceContainerHigh);
        }
        final px = (_thumb * MediaQuery.devicePixelRatioOf(context)).round();
        return Image.memory(
          data,
          fit: widget.fit,
          gaplessPlayback: true,
          cacheWidth: widget.thumbnail ? px : null,
          errorBuilder: (_, _, _) =>
              Icon(Icons.broken_image_outlined, color: colors.outline),
        );
      },
    );
  }
}

/// Opens a file: pictures full screen in the app, anything else in the
/// browser (which shows or downloads it).
Future<void> openStoredFile(
  BuildContext context,
  WidgetRef ref,
  StoredFile file,
) async {
  if (file.isImage) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _ImageViewer(file: file),
      ),
    );
    return;
  }
  await downloadStoredFile(context, ref, file);
}

/// Opens the file's download link in the browser.
Future<void> downloadStoredFile(
  BuildContext context,
  WidgetRef ref,
  StoredFile file,
) async {
  final l = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  void fail(String msg) => messenger.showSnackBar(
    SnackBar(behavior: SnackBarBehavior.floating, content: Text(msg)),
  );
  try {
    final url = await ref.read(fileStoreProvider).link(file.id);
    if (url == null) return fail(l.attachUnavailableInDemo);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      fail(l.attachOpenFailed);
    }
  } catch (_) {
    fail(l.attachOpenFailed);
  }
}

class _ImageViewer extends ConsumerWidget {
  const _ImageViewer({required this.file});
  final StoredFile file;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text(file.name, overflow: TextOverflow.ellipsis),
      actions: [
        IconButton(
          tooltip: context.l10n.attachDownload,
          icon: const Icon(Icons.download),
          onPressed: () => downloadStoredFile(context, ref, file),
        ),
      ],
    ),
    body: InteractiveViewer(
      maxScale: 6,
      child: Center(child: FileImageView(file: file)),
    ),
  );
}
