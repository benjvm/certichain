import 'dart:io';

/// Removes only the selected copy in the pinned mobile picker's own cache.
/// Never clear all picker files: another selection may still be reading them.
Future<void> removePickerTemporaryFile(
  String? path, {
  Directory? temporaryDirectory,
  String? operatingSystem,
}) async {
  if (path == null) return;
  final system = operatingSystem ?? Platform.operatingSystem;
  if (system != 'android' && system != 'ios') return;
  final temporary = temporaryDirectory ?? Directory.systemTemp;
  // Flutter Android's TMPDIR is code_cache; the pinned picker writes to the
  // sibling app cache. Derive that root from the trusted app temporary root.
  final pickerRoot =
      system == 'android' &&
          temporary.uri.pathSegments.where((s) => s.isNotEmpty).last ==
              'code_cache'
      ? Directory('${temporary.parent.path}${Platform.pathSeparator}cache')
      : temporary;
  final root = Directory.fromUri(pickerRoot.absolute.uri.normalizePath());
  try {
    final file = File.fromUri(File(path).absolute.uri.normalizePath());
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return;
    }
    // Android/iOS can expose different aliases for the same app cache. Compare
    // their real paths, then delete only the canonical, selected plugin copy.
    final canonicalRoot = (await root.resolveSymbolicLinks()).replaceFirst(
      RegExp(r'[\\/]+$'),
      '',
    );
    final canonicalFile = await file.resolveSymbolicLinks();
    final prefix = '$canonicalRoot${Platform.pathSeparator}';
    if (!canonicalFile.startsWith(prefix)) return;
    final parts = canonicalFile
        .substring(prefix.length)
        .split(Platform.pathSeparator);
    final ownCopy = system == 'android'
        ? parts.length == 3 &&
              parts[0] == 'file_picker' &&
              RegExp(r'^\d+$').hasMatch(parts[1])
        : parts.length == 2 &&
              RegExp(
                r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
              ).hasMatch(parts[0]);
    if (!ownCopy || parts.any((p) => p.isEmpty || p == '.' || p == '..')) {
      return;
    }
    final selectedCopy = File(canonicalFile);
    await selectedCopy.delete();
    // Non-recursive deletion succeeds only for an empty, selected-item folder.
    await selectedCopy.parent.delete();
  } on FileSystemException {
    // Best effort: provider/OS may retain or remove a copy independently.
  }
}
