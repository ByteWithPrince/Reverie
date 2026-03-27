import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:reverie/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 1. DATA MODEL
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class BookModel {
  final String filePath;
  final String title;
  final String fileType;
  final DateTime dateAdded;
  final int fileSizeBytes;
  final double readingProgress;
  final bool isNew;

  const BookModel({
    required this.filePath,
    required this.title,
    required this.fileType,
    required this.dateAdded,
    required this.fileSizeBytes,
    this.readingProgress = 0.0,
    this.isNew = true,
  });

  BookModel copyWith({
    String? filePath,
    String? title,
    String? fileType,
    DateTime? dateAdded,
    int? fileSizeBytes,
    double? readingProgress,
    bool? isNew,
  }) {
    return BookModel(
      filePath: filePath ?? this.filePath,
      title: title ?? this.title,
      fileType: fileType ?? this.fileType,
      dateAdded: dateAdded ?? this.dateAdded,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      readingProgress: readingProgress ?? this.readingProgress,
      isNew: isNew ?? this.isNew,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'filePath': filePath,
        'title': title,
        'fileType': fileType,
        'dateAdded': dateAdded.toIso8601String(),
        'fileSizeBytes': fileSizeBytes,
        'readingProgress': readingProgress,
        'isNew': isNew,
      };

  factory BookModel.fromJson(Map<String, dynamic> json) => BookModel(
        filePath: json['filePath'] as String,
        title: json['title'] as String,
        fileType: json['fileType'] as String,
        dateAdded: DateTime.parse(json['dateAdded'] as String),
        fileSizeBytes: json['fileSizeBytes'] as int,
        readingProgress: (json['readingProgress'] as num).toDouble(),
        isNew: json['isNew'] as bool,
      );

  factory BookModel.fromFile(File file) {
    final String path = file.path;
    final String filename = path.split(Platform.pathSeparator).last;
    final int dotIndex = filename.lastIndexOf('.');
    final String rawName =
        dotIndex > 0 ? filename.substring(0, dotIndex) : filename;
    final String ext =
        dotIndex > 0 ? filename.substring(dotIndex + 1).toLowerCase() : '';

    return BookModel(
      filePath: path,
      title: _cleanTitle(rawName),
      fileType: ext == 'epub' ? 'epub' : 'pdf',
      dateAdded: DateTime.now(),
      fileSizeBytes: file.existsSync() ? file.lengthSync() : 0,
    );
  }

  static String _cleanTitle(String raw) {
    final String cleaned = raw.replaceAll('_', ' ').replaceAll('-', ' ');
    return cleaned
        .split(RegExp(r'\s+'))
        .where((String w) => w.isNotEmpty)
        .map((String w) =>
            w[0].toUpperCase() + (w.length > 1 ? w.substring(1) : ''))
        .join(' ');
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 2. RIVERPOD PROVIDERS
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
// 3. BACKGROUND SCAN ISOLATE FUNCTION
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

List<Map<String, dynamic>> _scanDirectories(List<String> paths) {
  final Set<String> seen = <String>{};
  final List<Map<String, dynamic>> results = <Map<String, dynamic>>[];

  for (final String dirPath in paths) {
    final Directory dir = Directory(dirPath);
    if (!dir.existsSync()) continue;

    try {
      _scanRecursive(dir, 0, 4, seen, results);
    } catch (_) {}
  }

  return results;
}

void _scanRecursive(
  Directory dir,
  int currentDepth,
  int maxDepth,
  Set<String> seen,
  List<Map<String, dynamic>> results,
) {
  if (currentDepth >= maxDepth) return;

  try {
    final List<FileSystemEntity> entities = dir.listSync(followLinks: false);
    for (final FileSystemEntity entity in entities) {
      if (entity is File) {
        final String lower = entity.path.toLowerCase();
        if ((lower.endsWith('.epub') || lower.endsWith('.pdf')) &&
            !seen.contains(entity.path)) {
          seen.add(entity.path);
          int size = 0;
          try {
            size = entity.lengthSync();
          } catch (_) {}
          results.add(<String, dynamic>{
            'path': entity.path,
            'size': size,
          });
        }
      } else if (entity is Directory) {
        _scanRecursive(entity, currentDepth + 1, maxDepth, seen, results);
      }
    }
  } catch (_) {}
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 4. SORT MODE
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
// 5. HELPERS
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Color _colorForTitle(String title) {
  if (title.isEmpty) return const Color(0xFFE94560);
  final String upper = title[0].toUpperCase();
  final int code = upper.codeUnitAt(0);
  if (code >= 65 && code <= 69) return const Color(0xFFE94560); // A-E red
  if (code >= 70 && code <= 74) return const Color(0xFF7C6AF7); // F-J purple
  if (code >= 75 && code <= 79) return const Color(0xFF2EC4B6); // K-O teal
  if (code >= 80 && code <= 84) return const Color(0xFFF7B731); // P-T amber
  if (code >= 85 && code <= 90) return const Color(0xFF4A9EFF); // U-Z blue
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
// 6. LIBRARY SCREEN
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  SortMode _sortMode = SortMode.alphabetical;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAndScan();
    });
  }

  Future<void> _loadAndScan() async {
    final LibraryBooksNotifier notifier =
        ref.read(libraryBooksProvider.notifier);
    await notifier.loadFromPrefs();
    await _startBackgroundScan();
  }

  Future<bool> _requestPermission() async {
    if (!Platform.isAndroid) return true;

    final bool alreadyGranted =
        await Permission.manageExternalStorage.isGranted;
    if (alreadyGranted) return true;

    if (!mounted) return false;

    final bool? userAccepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        title: Text(
          'Storage Access Required',
          style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface),
        ),
        content: Text(
          'Reverie needs storage access to find your books '
          'automatically. Please allow access on the next screen.',
          style: TextStyle(
            color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
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

    if (userAccepted != true) return false;

    await openAppSettings();

    // Wait a moment for user to return from settings
    await Future<void>.delayed(const Duration(seconds: 1));

    final bool grantedAfter =
        await Permission.manageExternalStorage.isGranted;
    if (grantedAfter) return true;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Storage permission was not granted. '
            'Some books may not be found automatically.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
    }
    return false;
  }

  Future<void> _startBackgroundScan() async {
    final bool hasPermission = await _requestPermission();
    if (!hasPermission) return;

    ref.read(isScanningProvider.notifier).state = true;

    try {
      ref.read(scanProgressProvider.notifier).state =
          'Preparing scan directories...';

      final List<String> scanPaths = <String>[
        '/storage/emulated/0/',
        '/storage/emulated/0/Download/',
        '/storage/emulated/0/Downloads/',
        '/storage/emulated/0/Documents/',
        '/storage/emulated/0/Books/',
        '/storage/emulated/0/EPUB/',
      ];

      ref.read(scanProgressProvider.notifier).state = 'Scanning Downloads...';

      final List<Map<String, dynamic>> rawResults =
          await compute(_scanDirectories, scanPaths);

      ref.read(scanProgressProvider.notifier).state =
          'Found ${rawResults.length} books, processing...';

      final List<BookModel> scanned = rawResults.map((Map<String, dynamic> r) {
        final String path = r['path'] as String;
        final int size = r['size'] as int;
        final String filename = path.split(Platform.pathSeparator).last;
        final int dotIndex = filename.lastIndexOf('.');
        final String rawName =
            dotIndex > 0 ? filename.substring(0, dotIndex) : filename;
        final String ext =
            dotIndex > 0 ? filename.substring(dotIndex + 1).toLowerCase() : '';

        return BookModel(
          filePath: path,
          title: BookModel._cleanTitle(rawName),
          fileType: ext == 'epub' ? 'epub' : 'pdf',
          dateAdded: DateTime.now(),
          fileSizeBytes: size,
        );
      }).toList();

      final LibraryBooksNotifier notifier =
          ref.read(libraryBooksProvider.notifier);
      notifier.mergeScannedBooks(scanned);
      await notifier.saveToPrefs();

      ref.read(scanProgressProvider.notifier).state = '';
    } catch (e) {
      ref.read(scanProgressProvider.notifier).state = 'Scan failed';
    } finally {
      ref.read(isScanningProvider.notifier).state = false;
    }
  }

  Future<void> _pickAndAddBook() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>['epub', 'pdf'],
        allowMultiple: false,
      );

      if (!mounted) return;

      if (result != null && result.files.isNotEmpty) {
        final String? path = result.files.first.path;
        if (path != null) {
          final BookModel book = BookModel.fromFile(File(path));
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
    final LibraryBooksNotifier notifier =
        ref.read(libraryBooksProvider.notifier);
    notifier.updateBook(
      book.filePath,
      (BookModel b) => b.copyWith(isNew: false),
    );
    notifier.saveToPrefs();

    final String encodedPath = Uri.encodeComponent(book.filePath);
    context.go('/reader?path=$encodedPath&type=${book.fileType}');
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
        .where((BookModel b) => b.readingProgress > 0)
        .toList()
      ..sort((BookModel a, BookModel b) =>
          b.readingProgress.compareTo(a.readingProgress));

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // Scan indicator
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

            // Top bar
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
                          content: Text('TODO: Search coming soon'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    icon: Icon(Icons.search_rounded, color: muted),
                  ),
                  // Sort button
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

            // Main content
            Expanded(
              child: sortedBooks.isEmpty
                  ? _buildEmptyState(scheme, muted)
                  : _buildMainContent(
                      sortedBooks, continueReading, theme, scheme, muted),
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
            'Tap + to add books or wait for scan to complete',
            style: TextStyle(color: muted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(
    List<BookModel> sortedBooks,
    List<BookModel> continueReading,
    ThemeData theme,
    ColorScheme scheme,
    Color muted,
  ) {
    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        // Continue Reading section
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

        // All books
        ...sortedBooks.map((BookModel book) =>
            _buildBookCard(book, theme, scheme, muted)),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildContinueReadingCard(
    BookModel book,
    ColorScheme scheme,
    Color muted,
  ) {
    final Color coverColor = _colorForTitle(book.title);
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
                    Container(
                      width: 40,
                      decoration: BoxDecoration(
                        color: coverColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text(
                          book.title.isNotEmpty
                              ? book.title[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
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
    ThemeData theme,
    ColorScheme scheme,
    Color muted,
  ) {
    final Color coverColor = _colorForTitle(book.title);
    final String readTime = _formatReadingTime(book.fileSizeBytes);
    final int progressPct = (book.readingProgress * 100).round();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 16, right: 16),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _onBookTap(book),
        child: Container(
          height: 100,
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
                      // Book cover placeholder
                      Container(
                        width: 64,
                        height: 80,
                        decoration: BoxDecoration(
                          color: coverColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            book.title.isNotEmpty
                                ? book.title[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Title, badge, reading time
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
                                      color: scheme.secondary,
                                      width: 1,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    book.fileType.toUpperCase(),
                                    style: TextStyle(
                                      color: scheme.secondary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
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

                      // Right side: progress % or NEW badge + menu
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          if (book.isNew)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.secondary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'NEW',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          if (book.readingProgress > 0) ...<Widget>[
                            const SizedBox(height: 4),
                            Text(
                              '$progressPct%',
                              style: const TextStyle(
                                color: Color(0xFFE94560),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Icon(
                            Icons.more_vert_rounded,
                            color: muted,
                            size: 20,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Reading progress bar
              if (book.readingProgress > 0)
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
}
