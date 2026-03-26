import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reverie/theme/app_theme.dart';

final StateProvider<List<String>> libraryBooksProvider =
    StateProvider<List<String>>((Ref ref) => <String>[]);

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  Future<void> _scanAndPickBooks(BuildContext context, WidgetRef ref) async {
    final Set<String> combinedBooks =
        ref.read(libraryBooksProvider).toSet();

    final List<Directory> scanRoots = <Directory>[];
    final Directory appDocs = await getApplicationDocumentsDirectory();
    scanRoots.add(appDocs);

    if (Platform.isAndroid) {
      final Directory? external = await getExternalStorageDirectory();
      if (external != null) {
        scanRoots.add(external);
      }
      scanRoots.add(Directory('/storage/emulated/0'));
    }

    for (final Directory root in scanRoots) {
      if (!await root.exists()) {
        continue;
      }
      try {
        await for (final FileSystemEntity entity
            in root.list(recursive: true, followLinks: false)) {
          if (entity is File &&
              entity.path.toLowerCase().endsWith('.epub')) {
            combinedBooks.add(entity.path);
          }
        }
      } catch (_) {
        // Ignore directories that cannot be traversed.
      }
    }

    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['epub', 'pdf'],
      allowMultiple: true,
    );

    if (!context.mounted) {
      return;
    }

    if (result != null) {
      for (final PlatformFile file in result.files) {
        final String? path = file.path;
        if (path != null) {
          combinedBooks.add(path);
        }
      }
    }

    final List<String> updated = combinedBooks.toList()..sort();
    ref.read(libraryBooksProvider.notifier).state = updated;
  }

  String _bookTitleFromPath(String path) {
    final String filename = path.split(Platform.pathSeparator).last;
    final String lower = filename.toLowerCase();
    if (lower.endsWith('.epub') || lower.endsWith('.pdf')) {
      final int dotIndex = filename.lastIndexOf('.');
      return dotIndex > 0 ? filename.substring(0, dotIndex) : filename;
    }
    return filename;
  }

  String _typeFromPath(String path) {
    final String lower = path.toLowerCase();
    if (lower.endsWith('.epub')) {
      return 'epub';
    }
    return 'pdf';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final List<String> books = ref.watch(libraryBooksProvider);
    final ThemeMode mode = ref.watch(themeModeProvider);
    final bool isDark = mode == ThemeMode.dark;
    final Color muted = theme.textTheme.bodySmall?.color ??
        (isDark ? const Color(0xFF8888AA) : const Color(0xFF666655));

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Reverie',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      ref.read(themeModeProvider.notifier).state =
                          isDark ? ThemeMode.light : ThemeMode.dark;
                    },
                    icon: Icon(
                      isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                      color: theme.textTheme.bodyLarge?.color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: books.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              Icons.menu_book_rounded,
                              size: 54,
                              color: muted,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Your library is empty',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        itemCount: books.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.72,
                        ),
                        itemBuilder: (BuildContext context, int index) {
                          final String path = books[index];
                          final String type = _typeFromPath(path);
                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              final String encodedPath =
                                  Uri.encodeComponent(path);
                              context.go('/reader?path=$encodedPath&type=$type');
                            },
                            child: Card(
                              color: scheme.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Expanded(
                                      child: Container(
                                        width: double.infinity,
                                        decoration: BoxDecoration(
                                          color: scheme.primary.withValues(
                                            alpha: 0.35,
                                          ),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Icon(
                                          Icons.menu_book_rounded,
                                          color: scheme.onSurface,
                                          size: 38,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      _bookTitleFromPath(path),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleMedium,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _scanAndPickBooks(context, ref),
        backgroundColor: scheme.surface,
        child: Icon(Icons.add, color: AppTheme.accent),
      ),
    );
  }
}
