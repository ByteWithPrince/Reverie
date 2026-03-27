import 'dart:convert';
import 'dart:io';


import 'package:archive/archive.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:reverie/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 1. EPUB METADATA
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class EpubMetadata {
  final String title;
  final String author;
  final Uint8List? coverBytes;

  const EpubMetadata({
    required this.title,
    required this.author,
    this.coverBytes,
  });
}

String _cleanFileName(String name) {
  return name
      .replaceAll('_', ' ')
      .replaceAll('-', ' ')
      .replaceAll('.', ' ')
      .split(' ')
      .map((String w) =>
          w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ')
      .trim();
}

/// Extracts metadata from an EPUB file (ZIP-based format).
/// Runs synchronously — designed to be called outside isolates
/// or from within compute() wrappers.
Future<EpubMetadata> extractEpubMetadata(String filePath) async {
  try {
    final File file = File(filePath);
    final Uint8List bytes = await file.readAsBytes();
    final Archive archive = ZipDecoder().decodeBytes(bytes);

    String title = _cleanFileName(
        filePath.split('/').last.replaceAll('.epub', ''));
    String author = 'Unknown Author';
    Uint8List? coverBytes;

    // Find and parse the OPF file for metadata
    for (final ArchiveFile archiveFile in archive) {
      if (archiveFile.name.endsWith('.opf')) {
        final String content = utf8.decode(archiveFile.content as List<int>);

        // Extract title
        final RegExpMatch? titleMatch =
            RegExp(r'<dc:title[^>]*>([^<]+)<\/dc:title>')
                .firstMatch(content);
        if (titleMatch != null) {
          title = titleMatch.group(1)?.trim() ?? title;
        }

        // Extract author
        final RegExpMatch? authorMatch =
            RegExp(r'<dc:creator[^>]*>([^<]+)<\/dc:creator>')
                .firstMatch(content);
        if (authorMatch != null) {
          author = authorMatch.group(1)?.trim() ?? author;
        }

        // Find cover image reference
        final RegExpMatch? coverMatch =
            RegExp(r'<item[^>]*id="cover[^"]*"[^>]*href="([^"]+)"')
                .firstMatch(content);
        if (coverMatch != null) {
          final String coverPath = coverMatch.group(1) ?? '';
          final String coverFileName = coverPath.split('/').last;
          for (final ArchiveFile cf in archive) {
            if (cf.name.endsWith(coverFileName) &&
                cf.content != null &&
                (cf.content as List<int>).isNotEmpty) {
              coverBytes = Uint8List.fromList(cf.content as List<int>);
              break;
            }
          }
        }
        break;
      }
    }

    // Fallback: try common cover image names
    if (coverBytes == null) {
      for (final ArchiveFile archiveFile in archive) {
        final String name = archiveFile.name.toLowerCase();
        if ((name.contains('cover') || name.contains('title')) &&
            (name.endsWith('.jpg') ||
                name.endsWith('.jpeg') ||
                name.endsWith('.png'))) {
          if (archiveFile.content != null &&
              (archiveFile.content as List<int>).isNotEmpty) {
            coverBytes =
                Uint8List.fromList(archiveFile.content as List<int>);
            break;
          }
        }
      }
    }

    return EpubMetadata(
      title: title,
      author: author,
      coverBytes: coverBytes,
    );
  } catch (_) {
    return EpubMetadata(
      title: _cleanFileName(
          filePath.split('/').last.replaceAll('.epub', '')),
      author: 'Unknown Author',
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 2. DATA MODEL
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class BookModel {
  final String filePath;
  final String title;
  final String author;
  final String fileType;
  final DateTime dateAdded;
  final int fileSizeBytes;
  final double readingProgress;
  final bool isNew;
  final String? coverBase64;

  const BookModel({
    required this.filePath,
    required this.title,
    required this.author,
    required this.fileType,
    required this.dateAdded,
    required this.fileSizeBytes,
    this.readingProgress = 0.0,
    this.isNew = true,
    this.coverBase64,
  });

  Uint8List? get coverBytes {
    if (coverBase64 == null || coverBase64!.isEmpty) return null;
    try {
      return base64Decode(coverBase64!);
    } catch (_) {
      return null;
    }
  }

  BookModel copyWith({
    String? filePath,
    String? title,
    String? author,
    String? fileType,
    DateTime? dateAdded,
    int? fileSizeBytes,
    double? readingProgress,
    bool? isNew,
    String? coverBase64,
  }) {
    return BookModel(
      filePath: filePath ?? this.filePath,
      title: title ?? this.title,
      author: author ?? this.author,
      fileType: fileType ?? this.fileType,
      dateAdded: dateAdded ?? this.dateAdded,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      readingProgress: readingProgress ?? this.readingProgress,
      isNew: isNew ?? this.isNew,
      coverBase64: coverBase64 ?? this.coverBase64,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'filePath': filePath,
        'title': title,
        'author': author,
        'fileType': fileType,
        'dateAdded': dateAdded.toIso8601String(),
        'fileSizeBytes': fileSizeBytes,
        'readingProgress': readingProgress,
        'isNew': isNew,
        'coverBase64': coverBase64,
      };

  factory BookModel.fromJson(Map<String, dynamic> json) => BookModel(
        filePath: json['filePath'] as String,
        title: json['title'] as String,
        author: (json['author'] as String?) ?? 'Unknown Author',
        fileType: json['fileType'] as String,
        dateAdded: DateTime.parse(json['dateAdded'] as String),
        fileSizeBytes: json['fileSizeBytes'] as int,
        readingProgress: (json['readingProgress'] as num).toDouble(),
        isNew: json['isNew'] as bool,
        coverBase64: json['coverBase64'] as String?,
      );
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 3. RIVERPOD PROVIDERS
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

const String _prefsKey = 'reverie_library_books';

class LibraryBooksNotifier extends StateNotifier<List<BookModel>> {
  LibraryBooksNotifier() : super(<BookModel>[]);

  void setBooks(List<BookModel> books) {
    state = books;
  }

  void addBook(BookModel book) {
    if (state.any((BookModel b) => b.filePath == book.filePath)) return;
    state = [...state, book]..sort(
        (BookModel a, BookModel b) =>
            a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
  }

  void removeBook(String filePath) {
    state = state.where((BookModel b) => b.filePath != filePath).toList();
  }

  void updateBook(String filePath, BookModel Function(BookModel) updater) {
    state = state
        .map((BookModel b) => b.filePath == filePath ? updater(b) : b)
        .toList();
  }

  void mergeScannedBooks(List<BookModel> scanned) {
    final Map<String, BookModel> existing = <String, BookModel>{
      for (final BookModel b in state) b.filePath: b,
    };
    for (final BookModel book in scanned) {
      existing.putIfAbsent(book.filePath, () => book);
    }
    final List<BookModel> merged = existing.values.toList()
      ..sort(
        (BookModel a, BookModel b) =>
            a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
    state = merged;
  }

  Future<void> saveToPrefs() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String json = jsonEncode(
        state.map((BookModel b) => b.toJson()).toList(),
      );
      await prefs.setString(_prefsKey, json);
    } catch (_) {}
  }

  Future<void> loadFromPrefs() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
        final List<BookModel> books = decoded
            .map((dynamic e) =>
                BookModel.fromJson(e as Map<String, dynamic>))
            .toList();
        state = books;
      }
    } catch (_) {}
  }
}

final StateNotifierProvider<LibraryBooksNotifier, List<BookModel>>
    libraryBooksProvider =
    StateNotifierProvider<LibraryBooksNotifier, List<BookModel>>(
  (Ref ref) => LibraryBooksNotifier(),
);

final StateProvider<bool> isScanningProvider =
    StateProvider<bool>((Ref ref) => false);

final StateProvider<String> scanProgressProvider =
    StateProvider<String>((Ref ref) => '');

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 4. FILE SCANNER (top-level for compute)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Synchronous deep EPUB file scanner for use in compute() isolate.
List<String> _scanForEpubFiles(dynamic _) {
  final List<String> found = <String>[];
  final Set<String> seen = <String>{};
  final List<String> searchPaths = <String>[
    '/storage/emulated/0/',
    '/storage/emulated/0/Download/',
    '/storage/emulated/0/Downloads/',
    '/storage/emulated/0/Documents/',
    '/storage/emulated/0/Books/',
    '/storage/emulated/0/EPUB/',
    '/storage/emulated/0/Ebooks/',
    '/storage/emulated/0/Reading/',
  ];

  for (final String path in searchPaths) {
    try {
      final Directory dir = Directory(path);
      if (!dir.existsSync()) continue;

      _scanRecursive(dir, 0, 5, seen, found);
    } catch (_) {
      continue;
    }
  }

  return found;
}

void _scanRecursive(
  Directory dir,
  int currentDepth,
  int maxDepth,
  Set<String> seen,
  List<String> results,
) {
  if (currentDepth >= maxDepth) return;

  try {
    final List<FileSystemEntity> entities = dir.listSync(followLinks: false);
    for (final FileSystemEntity entity in entities) {
      if (entity is File) {
        final String path = entity.path;
        final String lower = path.toLowerCase();
        if (lower.endsWith('.epub') &&
            !seen.contains(path) &&
            !path.contains('/.') &&
            !path.contains('Android/data')) {
          seen.add(path);
          results.add(path);
        }
      } else if (entity is Directory) {
        final String dirName = entity.path.split('/').last;
        // Skip hidden and system directories
        if (!dirName.startsWith('.') && dirName != 'Android') {
          _scanRecursive(entity, currentDepth + 1, maxDepth, seen, results);
        }
      }
    }
  } catch (_) {}
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 5. SORT MODE
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

enum SortMode { alphabetical, recentlyAdded, byProgress }

String _sortModeLabel(SortMode mode) {
  switch (mode) {
    case SortMode.alphabetical:
      return 'A-Z';
    case SortMode.recentlyAdded:
      return 'Recent';
    case SortMode.byProgress:
      return 'Progress';
  }
}

List<BookModel> _sortBooks(List<BookModel> books, SortMode mode) {
  final List<BookModel> sorted = List<BookModel>.from(books);
  switch (mode) {
    case SortMode.alphabetical:
      sorted.sort((BookModel a, BookModel b) =>
          a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    case SortMode.recentlyAdded:
      sorted.sort((BookModel a, BookModel b) =>
          b.dateAdded.compareTo(a.dateAdded));
    case SortMode.byProgress:
      sorted.sort((BookModel a, BookModel b) =>
          b.readingProgress.compareTo(a.readingProgress));
  }
  return sorted;
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 6. HELPERS
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Color _colorForTitle(String title) {
  if (title.isEmpty) return const Color(0xFFE94560);
  final int code = title[0].toUpperCase().codeUnitAt(0);
  if (code >= 65 && code <= 69) return const Color(0xFFE94560);
  if (code >= 70 && code <= 74) return const Color(0xFF7C6AF7);
  if (code >= 75 && code <= 79) return const Color(0xFF2EC4B6);
  if (code >= 80 && code <= 84) return const Color(0xFFF7B731);
  if (code >= 85 && code <= 90) return const Color(0xFF4A9EFF);
  return const Color(0xFFE94560);
}

String _formatReadingTime(int fileSizeBytes) {
  final int totalMinutes = fileSizeBytes ~/ 1024 ~/ 50;
  if (totalMinutes < 1) return '~1m read';
  final int hours = totalMinutes ~/ 60;
  final int minutes = totalMinutes % 60;
  if (hours > 0 && minutes > 0) return '~${hours}h ${minutes}m read';
  if (hours > 0) return '~${hours}h read';
  return '~${minutes}m read';
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 7. LIBRARY SCREEN
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with WidgetsBindingObserver {
  SortMode _sortMode = SortMode.alphabetical;
  bool _awaitingPermissionReturn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAndScan();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingPermissionReturn) {
      _awaitingPermissionReturn = false;
      _checkPermissionAndScan();
    }
  }

  Future<void> _checkPermissionAndScan() async {
    try {
      final bool granted =
          await Permission.manageExternalStorage.isGranted;
      if (granted) {
        await _startBackgroundScan();
      }
    } catch (_) {}
  }

  Future<void> _loadAndScan() async {
    try {
      final LibraryBooksNotifier notifier =
          ref.read(libraryBooksProvider.notifier);
      await notifier.loadFromPrefs();
      await _refreshProgress();
      await _requestAndScan();
    } catch (_) {}
  }

  Future<void> _refreshProgress() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final LibraryBooksNotifier notifier =
          ref.read(libraryBooksProvider.notifier);
      final List<BookModel> books = ref.read(libraryBooksProvider);
      for (final BookModel book in books) {
        final double? progress =
            prefs.getDouble('progress_${book.filePath.hashCode}');
        if (progress != null && progress != book.readingProgress) {
          notifier.updateBook(
            book.filePath,
            (BookModel b) => b.copyWith(readingProgress: progress),
          );
        }
      }
    } catch (_) {}
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // STORAGE PERMISSION
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Future<bool> _requestStoragePermission() async {
    try {
      if (Platform.isAndroid) {
        final AndroidDeviceInfo androidInfo =
            await DeviceInfoPlugin().androidInfo;
        final int sdkInt = androidInfo.version.sdkInt;

        if (sdkInt >= 30) {
          final PermissionStatus status =
              await Permission.manageExternalStorage.status;
          if (status.isGranted) return true;

          _awaitingPermissionReturn = true;
          await openAppSettings();

          // Check will happen in didChangeAppLifecycleState
          return false;
        } else {
          final PermissionStatus status =
              await Permission.storage.request();
          return status.isGranted;
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _requestAndScan() async {
    try {
      if (!Platform.isAndroid) {
        await _startBackgroundScan();
        return;
      }

      // Check if already granted
      final bool alreadyGranted =
          await Permission.manageExternalStorage.isGranted;
      if (alreadyGranted) {
        await _startBackgroundScan();
        return;
      }

      if (!mounted) return;

      // Show explanation dialog
      final bool? userAccepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext ctx) => AlertDialog(
          backgroundColor: Theme.of(ctx).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Storage Access Required',
            style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface),
          ),
          content: Text(
            'Reverie needs access to all files to find your '
            'EPUB books automatically. On the next screen, please find '
            "Reverie in the list and enable 'Allow access to manage "
            "all files'.",
            style: TextStyle(
              color:
                  Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.7),
              height: 1.5,
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                'Skip',
                style: TextStyle(
                  color: Theme.of(ctx)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFE94560),
              ),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );

      if (userAccepted == true) {
        await _requestStoragePermission();
        // If SDK < 30, permission is immediate
        final bool nowGranted =
            await Permission.manageExternalStorage.isGranted;
        if (nowGranted) {
          await _startBackgroundScan();
        }
      }
    } catch (_) {}
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // BACKGROUND SCAN
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Future<void> _startBackgroundScan() async {
    if (ref.read(isScanningProvider)) return;
    ref.read(isScanningProvider.notifier).state = true;

    try {
      ref.read(scanProgressProvider.notifier).state =
          'Scanning for EPUB files...';

      final List<String> paths =
          await compute(_scanForEpubFiles, null);

      ref.read(scanProgressProvider.notifier).state =
          'Found ${paths.length} books, extracting metadata...';

      final List<BookModel> scanned = <BookModel>[];
      for (int i = 0; i < paths.length; i++) {
        try {
          if (mounted) {
            ref.read(scanProgressProvider.notifier).state =
                'Processing ${i + 1} of ${paths.length}...';
          }

          final String path = paths[i];
          final File file = File(path);
          int fileSize = 0;
          try {
            fileSize = await file.length();
          } catch (_) {}

          final EpubMetadata metadata = await extractEpubMetadata(path);

          String? coverB64;
          if (metadata.coverBytes != null) {
            coverB64 = base64Encode(metadata.coverBytes!);
          }

          scanned.add(BookModel(
            filePath: path,
            title: metadata.title,
            author: metadata.author,
            fileType: 'epub',
            dateAdded: DateTime.now(),
            fileSizeBytes: fileSize,
            coverBase64: coverB64,
          ));
        } catch (_) {
          continue;
        }
      }

      final LibraryBooksNotifier notifier =
          ref.read(libraryBooksProvider.notifier);
      notifier.mergeScannedBooks(scanned);
      await notifier.saveToPrefs();

      ref.read(scanProgressProvider.notifier).state = '';
    } catch (_) {
      ref.read(scanProgressProvider.notifier).state = 'Scan failed';
    } finally {
      ref.read(isScanningProvider.notifier).state = false;
    }
  }

  Future<void> _onRefresh() async {
    try {
      await _startBackgroundScan();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Library refreshed'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _pickAndAddBook() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>['epub'],
        allowMultiple: false,
      );

      if (!mounted) return;

      if (result != null && result.files.isNotEmpty) {
        final String? path = result.files.first.path;
        if (path != null) {
          final File file = File(path);
          int fileSize = 0;
          try {
            fileSize = await file.length();
          } catch (_) {}

          final EpubMetadata metadata = await extractEpubMetadata(path);

          String? coverB64;
          if (metadata.coverBytes != null) {
            coverB64 = base64Encode(metadata.coverBytes!);
          }

          final BookModel book = BookModel(
            filePath: path,
            title: metadata.title,
            author: metadata.author,
            fileType: 'epub',
            dateAdded: DateTime.now(),
            fileSizeBytes: fileSize,
            coverBase64: coverB64,
          );

          final LibraryBooksNotifier notifier =
              ref.read(libraryBooksProvider.notifier);
          notifier.addBook(book);
          await notifier.saveToPrefs();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Book added to library'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      }
    } catch (_) {}
  }

  void _onBookTap(BookModel book) {
    try {
      final LibraryBooksNotifier notifier =
          ref.read(libraryBooksProvider.notifier);
      notifier.updateBook(
        book.filePath,
        (BookModel b) => b.copyWith(isNew: false),
      );
      notifier.saveToPrefs();

      final String encodedPath = Uri.encodeComponent(book.filePath);
      context.go('/reader?path=$encodedPath');
    } catch (_) {}
  }

  void _cycleSortMode() {
    setState(() {
      switch (_sortMode) {
        case SortMode.alphabetical:
          _sortMode = SortMode.recentlyAdded;
        case SortMode.recentlyAdded:
          _sortMode = SortMode.byProgress;
        case SortMode.byProgress:
          _sortMode = SortMode.alphabetical;
      }
    });
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // BUILD
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final List<BookModel> allBooks = ref.watch(libraryBooksProvider);
    final bool isScanning = ref.watch(isScanningProvider);
    final String scanProgress = ref.watch(scanProgressProvider);
    final ThemeMode mode = ref.watch(themeModeProvider);
    final bool isDark = mode == ThemeMode.dark;
    final Color muted = scheme.onSurface.withValues(alpha: 0.5);

    final List<BookModel> sortedBooks = _sortBooks(allBooks, _sortMode);
    final List<BookModel> continueReading = allBooks
        .where((BookModel b) => b.readingProgress > 0.05)
        .toList()
      ..sort((BookModel a, BookModel b) =>
          b.readingProgress.compareTo(a.readingProgress));

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (isScanning) ...<Widget>[
              LinearProgressIndicator(
                backgroundColor: Colors.transparent,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Color(0xFFE94560)),
                minHeight: 2,
              ),
              if (scanProgress.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 2),
                  child: Text(
                    scanProgress,
                    style: TextStyle(color: muted, fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Reverie',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 26,
                        fontWeight: FontWeight.w300,
                        fontFamily: 'serif',
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Search coming soon'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    icon: Icon(Icons.search_rounded, color: muted),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      IconButton(
                        onPressed: _cycleSortMode,
                        icon: Icon(Icons.sort_rounded, color: muted),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      Text(
                        _sortModeLabel(_sortMode),
                        style: TextStyle(color: muted, fontSize: 9),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: () {
                      ref.read(themeModeProvider.notifier).state =
                          isDark ? ThemeMode.light : ThemeMode.dark;
                    },
                    icon: Icon(
                      isDark
                          ? Icons.light_mode_rounded
                          : Icons.dark_mode_rounded,
                      color: muted,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: sortedBooks.isEmpty
                  ? _buildEmptyState(scheme, muted)
                  : RefreshIndicator(
                      color: const Color(0xFFE94560),
                      onRefresh: _onRefresh,
                      child: _buildMainContent(
                          sortedBooks, continueReading, scheme, muted),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickAndAddBook,
        backgroundColor: const Color(0xFFE94560),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme scheme, Color muted) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.menu_book_rounded, size: 72, color: muted),
          const SizedBox(height: 16),
          Text(
            'Your library is empty',
            style: TextStyle(color: scheme.onSurface, fontSize: 18),
          ),
          const SizedBox(height: 16),
          Text(
            'Tap + to add books or pull down to scan',
            style: TextStyle(color: muted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(
    List<BookModel> sortedBooks,
    List<BookModel> continueReading,
    ColorScheme scheme,
    Color muted,
  ) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: <Widget>[
        if (continueReading.isNotEmpty) ...<Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 8, bottom: 10),
            child: Text(
              'Continue Reading',
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            height: 120,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: continueReading.length,
              itemBuilder: (BuildContext context, int index) {
                return _buildContinueReadingCard(
                    continueReading[index], scheme, muted);
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
        ...sortedBooks.map((BookModel book) =>
            _buildBookCard(book, scheme, muted)),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildContinueReadingCard(
    BookModel book,
    ColorScheme scheme,
    Color muted,
  ) {
    final int progressPct = (book.readingProgress * 100).round();

    return GestureDetector(
      onTap: () => _onBookTap(book),
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: <Widget>[
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: <Widget>[
                    _buildSmallCover(book, 40, double.infinity),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Text(
                            book.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$progressPct%',
                            style: const TextStyle(
                              color: Color(0xFFE94560),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
              child: LinearProgressIndicator(
                value: book.readingProgress,
                minHeight: 3,
                backgroundColor: Colors.transparent,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFFE94560),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookCard(
    BookModel book,
    ColorScheme scheme,
    Color muted,
  ) {
    final String readTime = _formatReadingTime(book.fileSizeBytes);
    final int progressPct = (book.readingProgress * 100).round();
    final bool showProgress = book.readingProgress > 0.05;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 16, right: 16),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _onBookTap(book),
        child: Container(
          height: 96,
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: <Widget>[
              Expanded(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: <Widget>[
                      _buildSmallCover(book, 60, 76),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Text(
                              book.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: scheme.onSurface,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              book.author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: muted,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: <Widget>[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: const Color(0xFFE94560),
                                      width: 1,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'EPUB',
                                    style: TextStyle(
                                      color: Color(0xFFE94560),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  readTime,
                                  style: TextStyle(
                                    color: muted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (showProgress)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            '$progressPct%',
                            style: const TextStyle(
                              color: Color(0xFFE94560),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (showProgress)
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                  child: LinearProgressIndicator(
                    value: book.readingProgress,
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFFE94560),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSmallCover(BookModel book, double width, double height) {
    final Uint8List? cover = book.coverBytes;
    if (cover != null && cover.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          cover,
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (_, Object e, StackTrace? s) =>
              _buildLetterCover(book.title, width, height),
        ),
      );
    }
    return _buildLetterCover(book.title, width, height);
  }

  Widget _buildLetterCover(String title, double width, double height) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: _colorForTitle(title),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          title.isNotEmpty ? title[0].toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
