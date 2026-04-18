import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:reverie/services/streak_service.dart';
import 'package:reverie/services/supabase_service.dart';
import 'package:reverie/theme/app_theme.dart';
import 'package:share_plus/share_plus.dart';
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
      .map(
        (String w) =>
            w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1).toLowerCase(),
      )
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
      filePath.split('/').last.replaceAll('.epub', ''),
    );
    String author = 'Unknown Author';
    Uint8List? coverBytes;

    // Find and parse the OPF file for metadata
    for (final ArchiveFile archiveFile in archive) {
      if (archiveFile.name.endsWith('.opf')) {
        final String content = utf8.decode(archiveFile.content as List<int>);

        // Extract title
        final RegExpMatch? titleMatch = RegExp(
          r'<dc:title[^>]*>([^<]+)<\/dc:title>',
        ).firstMatch(content);
        if (titleMatch != null) {
          title = titleMatch.group(1)?.trim() ?? title;
        }

        // Extract author
        final RegExpMatch? authorMatch = RegExp(
          r'<dc:creator[^>]*>([^<]+)<\/dc:creator>',
        ).firstMatch(content);
        if (authorMatch != null) {
          author = authorMatch.group(1)?.trim() ?? author;
        }

        // Find cover image reference
        final RegExpMatch? coverMatch = RegExp(
          r'<item[^>]*id="cover[^"]*"[^>]*href="([^"]+)"',
        ).firstMatch(content);
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
            coverBytes = Uint8List.fromList(archiveFile.content as List<int>);
            break;
          }
        }
      }
    }

    return EpubMetadata(title: title, author: author, coverBytes: coverBytes);
  } catch (_) {
    return EpubMetadata(
      title: _cleanFileName(filePath.split('/').last.replaceAll('.epub', '')),
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

/// FIX 1 — Normalize book key by filename for deduplication.
/// Extracts just the filename without extension, lowercased,
/// with separators normalized so the same book from different
/// paths (Download vs Downloads) is treated as one.
String _normalizeBookKey(String filePath) {
  final String fileName = filePath
      .split('/')
      .last
      .toLowerCase()
      .replaceAll('.epub', '')
      .replaceAll(RegExp(r'[_\-\s]+'), ' ')
      .trim();
  return fileName;
}

/// Pick the "better" book entry — the one with more progress/metadata.
BookModel _pickBetterBook(BookModel a, BookModel b) {
  // Prefer the one with higher reading progress
  if (a.readingProgress > b.readingProgress) return a;
  if (b.readingProgress > a.readingProgress) return b;
  // Prefer the one whose file actually exists on disk
  try {
    final bool aExists = File(a.filePath).existsSync();
    final bool bExists = File(b.filePath).existsSync();
    if (aExists && !bExists) return a;
    if (bExists && !aExists) return b;
  } catch (_) {}
  // Prefer the one with a cover
  final bool aHasCover = a.coverBase64 != null && a.coverBase64!.isNotEmpty;
  final bool bHasCover = b.coverBase64 != null && b.coverBase64!.isNotEmpty;
  if (aHasCover && !bHasCover) return a;
  if (bHasCover && !aHasCover) return b;
  // Prefer the one with a real author
  if (a.author != 'Unknown Author' && b.author == 'Unknown Author') return a;
  if (b.author != 'Unknown Author' && a.author == 'Unknown Author') return b;
  return a; // default: keep existing
}

class LibraryBooksNotifier extends StateNotifier<List<BookModel>> {
  LibraryBooksNotifier() : super(<BookModel>[]);

  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = state.map((b) => b.toJson()).toList();
      await prefs.setString('reverie_library_v2', jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Save prefs error: $e');
    }
  }

  void setBooks(List<BookModel> books) {
    state = _deduplicateList(books);
  }

  void addBook(BookModel book) {
    final String newKey = _normalizeBookKey(book.filePath);
    final BookModel existing = state.firstWhere(
      (BookModel b) => _normalizeBookKey(b.filePath) == newKey,
      orElse: () => book,
    );
    if (existing.filePath == book.filePath) {
      // Exact same path — skip entirely if already in list
      if (state.any((BookModel b) => b.filePath == book.filePath)) return;
    }
    // Different path but same book name — replace with better one
    state =
        <BookModel>[
          ...state.where(
            (BookModel b) => _normalizeBookKey(b.filePath) != newKey,
          ),
          _pickBetterBook(existing, book),
        ]..sort(
          (BookModel a, BookModel b) =>
              a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
    _saveToPrefs();
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
    // Build a map keyed by normalized book key (filename)
    final Map<String, BookModel> byKey = <String, BookModel>{};

    // Add existing books first
    for (final BookModel b in state) {
      final String key = _normalizeBookKey(b.filePath);
      if (byKey.containsKey(key)) {
        byKey[key] = _pickBetterBook(byKey[key]!, b);
      } else {
        byKey[key] = b;
      }
    }

    // Add scanned books — merge with existing by key
    for (final BookModel book in scanned) {
      final String key = _normalizeBookKey(book.filePath);
      if (byKey.containsKey(key)) {
        byKey[key] = _pickBetterBook(byKey[key]!, book);
      } else {
        byKey[key] = book;
      }
    }

    final List<BookModel> merged = byKey.values.toList()
      ..sort(
        (BookModel a, BookModel b) =>
            a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
    state = merged;
  }

  /// Deduplicate by normalized path before saving.
  Future<void> saveToPrefs() async {
    try {
      final List<BookModel> deduped = _deduplicateList(state);
      state = deduped;
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String json = jsonEncode(
        deduped.map((BookModel b) => b.toJson()).toList(),
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
            .map((dynamic e) => BookModel.fromJson(e as Map<String, dynamic>))
            .toList();
        // Deduplicate immediately on load
        state = _deduplicateList(books);
      }
      // Run extra cleanup on app start
      await _deduplicateExisting();
    } catch (_) {}
  }

  /// FIX 1 — Run deduplication cleanup on app start.
  Future<void> _deduplicateExisting() async {
    try {
      final Set<String> seen = <String>{};
      final List<BookModel> unique = <BookModel>[];

      // Sort by readingProgress descending so we keep the best copy
      final List<BookModel> sorted = <BookModel>[...state]
        ..sort(
          (BookModel a, BookModel b) =>
              b.readingProgress.compareTo(a.readingProgress),
        );

      for (final BookModel book in sorted) {
        final String key = _normalizeBookKey(book.filePath);
        if (!seen.contains(key)) {
          seen.add(key);
          unique.add(book);
        }
      }
      state = unique;
      await _saveToPrefs();
    } catch (_) {}
  }

  /// Internal deduplication by normalized book key (filename).
  static List<BookModel> _deduplicateList(List<BookModel> books) {
    final Map<String, BookModel> byKey = <String, BookModel>{};
    for (final BookModel b in books) {
      final String key = _normalizeBookKey(b.filePath);
      if (byKey.containsKey(key)) {
        byKey[key] = _pickBetterBook(byKey[key]!, b);
      } else {
        byKey[key] = b;
      }
    }
    final List<BookModel> result = byKey.values.toList()
      ..sort(
        (BookModel a, BookModel b) =>
            a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
    return result;
  }
}

final StateNotifierProvider<LibraryBooksNotifier, List<BookModel>>
libraryBooksProvider =
    StateNotifierProvider<LibraryBooksNotifier, List<BookModel>>(
      (Ref ref) => LibraryBooksNotifier(),
    );

final StateProvider<bool> isScanningProvider = StateProvider<bool>(
  (Ref ref) => false,
);

final StateProvider<String> scanProgressProvider = StateProvider<String>(
  (Ref ref) => '',
);

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
      sorted.sort(
        (BookModel a, BookModel b) =>
            a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
    case SortMode.recentlyAdded:
      sorted.sort(
        (BookModel a, BookModel b) => b.dateAdded.compareTo(a.dateAdded),
      );
    case SortMode.byProgress:
      sorted.sort(
        (BookModel a, BookModel b) =>
            b.readingProgress.compareTo(a.readingProgress),
      );
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

String _formatReadingTime(int fileSizeBytes, {double wpm = 200}) {
  if (fileSizeBytes <= 0) return '~1m read';
  final int words = fileSizeBytes ~/ 6;
  final int totalMinutes = (words / wpm).round();
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
    with WidgetsBindingObserver, TickerProviderStateMixin {
  SortMode _sortMode = SortMode.alphabetical;
  bool _awaitingPermissionReturn = false;
  Timer? _scanTimeout;
  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  int _totalReadingMinutes = 0;
  final ScrollController _scrollController = ScrollController();
  bool _hasScrolled = false;
  int _currentStreak = 0;
  double _readingSpeedWpm = 200;

  // FAB scale animation
  late final AnimationController _fabAnimController;
  late final Animation<double> _fabScale;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);

    _fabAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fabScale = CurvedAnimation(
      parent: _fabAnimController,
      curve: Curves.elasticOut,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAndScan();
      _loadStreak();
      // Delay FAB animation for a nice entrance
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _fabAnimController.forward();
      });
    });
  }

  void _onScroll() {
    final scrolled =
        _scrollController.hasClients && _scrollController.offset > 8;
    if (scrolled != _hasScrolled) {
      setState(() => _hasScrolled = scrolled);
    }
  }

  Future<void> _loadStreak() async {
    try {
      final streak = await StreakService.getCurrentStreak();
      if (mounted) setState(() => _currentStreak = streak);
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _scanTimeout?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _fabAnimController.dispose();
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
    // If permission was previously granted, skip check entirely
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final bool remembered = prefs.getBool('permission_granted') ?? false;
      if (remembered) {
        await _startBackgroundScan();
        return;
      }
    } catch (_) {}

    if (!Platform.isAndroid) {
      await _startBackgroundScan();
      return;
    }
    try {
      final AndroidDeviceInfo androidInfo =
          await DeviceInfoPlugin().androidInfo;
      final int sdk = androidInfo.version.sdkInt;

      bool hasPermission = false;
      if (sdk >= 30) {
        hasPermission = await Permission.manageExternalStorage.isGranted;
      } else {
        hasPermission = await Permission.storage.isGranted;
      }

      if (hasPermission) {
        // Remember so we never ask again
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setBool('permission_granted', true);
        await _startBackgroundScan();
      }
    } catch (e) {
      debugPrint('Permission check error: $e');
    }
  }

  /// Verify each book file still exists on disk.
  Future<List<BookModel>> _verifyAndCleanLibrary(List<BookModel> books) async {
    final List<BookModel> valid = <BookModel>[];
    for (final BookModel book in books) {
      try {
        final bool exists = await File(book.filePath).exists();
        if (exists) {
          valid.add(book);
        }
      } catch (_) {
        continue;
      }
    }
    return valid;
  }

  Future<void> _loadAndScan() async {
    try {
      final LibraryBooksNotifier notifier = ref.read(
        libraryBooksProvider.notifier,
      );
      // Load from prefs
      await notifier.loadFromPrefs();
      // Verify files exist and clean stale entries
      final List<BookModel> current = ref.read(libraryBooksProvider);
      final List<BookModel> valid = await _verifyAndCleanLibrary(current);
      notifier.setBooks(valid);
      // Save cleaned list back to prefs
      await notifier.saveToPrefs();
      // Refresh progress from reader
      await _refreshProgress();
      // Scan for new files
      await _requestAndScan();
    } catch (_) {}
  }

  Future<void> _refreshProgress() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final LibraryBooksNotifier notifier = ref.read(
        libraryBooksProvider.notifier,
      );
      final List<BookModel> books = ref.read(libraryBooksProvider);
      for (final BookModel book in books) {
        final double? progress = prefs.getDouble(
          'progress_${book.filePath.hashCode}',
        );
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
          // Check if already granted
          if (await Permission.manageExternalStorage.isGranted) return true;

          // Try the system permission request first
          await Permission.manageExternalStorage.request();

          // If still not granted, open All Files Access settings page
          if (!await Permission.manageExternalStorage.isGranted) {
            _awaitingPermissionReturn = true;
            await openAppSettings();
            // Check will happen in didChangeAppLifecycleState
            return false;
          }
          return true;
        } else {
          final PermissionStatus status = await Permission.storage.request();
          return status.isGranted;
        }
      }
      return true;
    } catch (_) {
      try {
        await openAppSettings();
      } catch (_) {}
      return false;
    }
  }

  Future<void> _requestAndScan() async {
    try {
      // Check if permission was previously remembered
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final bool remembered = prefs.getBool('permission_granted') ?? false;
      if (remembered) {
        await _startBackgroundScan();
        return;
      }

      if (!Platform.isAndroid) {
        await prefs.setBool('permission_granted', true);
        await _startBackgroundScan();
        return;
      }

      // Check if already granted
      final bool alreadyGranted =
          await Permission.manageExternalStorage.isGranted;
      if (alreadyGranted) {
        await prefs.setBool('permission_granted', true);
        await _startBackgroundScan();
        return;
      }

      if (!mounted) return;

      // Show explanation dialog with clear instructions
      final bool? userAccepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext ctx) => AlertDialog(
          backgroundColor: Theme.of(ctx).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Find Your Books',
            style: TextStyle(
              color: Theme.of(ctx).colorScheme.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'To automatically find all your EPUB books, '
                'Reverie needs access to your files.',
                style: TextStyle(
                  color: Theme.of(
                    ctx,
                  ).colorScheme.onSurface.withValues(alpha: 0.7),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE94560).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'On the next screen:\n'
                  '1. Look for "All files access" OR\n'
                  '2. Find Reverie in the list\n'
                  '3. Toggle it ON',
                  style: TextStyle(
                    color: Color(0xFFE94560),
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                'Skip',
                style: TextStyle(
                  color: Theme.of(
                    ctx,
                  ).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE94560),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
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
          await prefs.setBool('permission_granted', true);
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

    _scanTimeout?.cancel();
    _scanTimeout = Timer(const Duration(seconds: 15), () {
      if (mounted) {
        ref.read(isScanningProvider.notifier).state = false;
        ref.read(scanProgressProvider.notifier).state = '';
      }
    });

    try {
      ref.read(isScanningProvider.notifier).state = true;
      ref.read(scanProgressProvider.notifier).state =
          'Scanning for EPUB files...';

      final List<String> paths = await compute(_scanForEpubFiles, null);

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

          scanned.add(
            BookModel(
              filePath: path,
              title: metadata.title,
              author: metadata.author,
              fileType: 'epub',
              dateAdded: DateTime.now(),
              fileSizeBytes: fileSize,
              coverBase64: coverB64,
            ),
          );
        } catch (_) {
          continue;
        }
      }

      final LibraryBooksNotifier notifier = ref.read(
        libraryBooksProvider.notifier,
      );
      notifier.mergeScannedBooks(scanned);
      await notifier.saveToPrefs();

      ref.read(scanProgressProvider.notifier).state = '';
    } catch (e) {
      debugPrint('Scan error: $e');
      if (mounted) {
        ref.read(scanProgressProvider.notifier).state = 'Scan failed';
      }
    } finally {
      _scanTimeout?.cancel();
      if (mounted) {
        ref.read(isScanningProvider.notifier).state = false;
        ref.read(scanProgressProvider.notifier).state = '';
      }
    }
    _loadReadingStats();
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

          final LibraryBooksNotifier notifier = ref.read(
            libraryBooksProvider.notifier,
          );
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

  Future<void> _onBookTap(BookModel book) async {
    try {
      final exists = await File(book.filePath).exists();
      if (!exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${book.title} could not be found. '
                'It may have been moved or deleted.',
              ),
              backgroundColor: Colors.red.shade800,
              action: SnackBarAction(
                label: 'Remove',
                textColor: Colors.white,
                onPressed: () {
                  ref
                      .read(libraryBooksProvider.notifier)
                      .removeBook(book.filePath);
                  ref.read(libraryBooksProvider.notifier).saveToPrefs();
                },
              ),
            ),
          );
        }
        return;
      }

      final LibraryBooksNotifier notifier = ref.read(
        libraryBooksProvider.notifier,
      );
      notifier.updateBook(
        book.filePath,
        (BookModel b) => b.copyWith(isNew: false),
      );
      notifier.saveToPrefs();

      if (mounted) {
        context.push('/book/${Uri.encodeComponent(book.title)}', extra: book);
      }
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

  Future<void> _loadReadingStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      int total = 0;
      final books = ref.read(libraryBooksProvider);
      for (final book in books) {
        total += prefs.getInt('readtime_${book.filePath.hashCode}') ?? 0;
      }
      final savedWpm = prefs.getDouble('reading_speed_wpm') ?? 0;
      if (mounted) {
        setState(() {
          _totalReadingMinutes = total;
          if (savedWpm > 50) _readingSpeedWpm = savedWpm;
        });
      }
    } catch (_) {}
  }

  String _formatTotalTime(int minutes) {
    if (minutes < 1) return '0m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  void _showBookDetail(BookModel book, ColorScheme scheme, Color muted) {
    try {
      final int progressPct = (book.readingProgress * 100).round();
      final String readTime = _formatReadingTime(book.fileSizeBytes, wpm: _readingSpeedWpm);
      showModalBottomSheet(
        context: context,
        backgroundColor: scheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: muted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              _buildSmallCover(book, 100, 140),
              const SizedBox(height: 16),
              Text(
                book.title,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(book.author, style: TextStyle(color: muted, fontSize: 14)),
              const SizedBox(height: 12),
              if (book.readingProgress > 0.01) ...[
                LinearProgressIndicator(
                  value: book.readingProgress,
                  minHeight: 3,
                  backgroundColor: muted.withValues(alpha: 0.15),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFFE94560)),
                ),
                const SizedBox(height: 4),
                Text(
                  '$progressPct% complete',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(readTime, style: TextStyle(color: muted, fontSize: 12)),
                  Text('  ·  ', style: TextStyle(color: muted)),
                  Text(
                    'Added ${book.dateAdded.day}/${book.dateAdded.month}/${book.dateAdded.year}',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _onBookTap(book);
                      },
                      icon: const Icon(Icons.auto_stories_rounded, size: 18),
                      label: const Text('Read'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE94560),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        try {
                          Share.share(
                            "I'm reading \"${book.title}\" by ${book.author} on Reverie",
                          );
                        } catch (_) {}
                      },
                      icon: const Icon(Icons.share_rounded, size: 18),
                      label: const Text('Share'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: scheme.onSurface,
                        side: BorderSide(color: muted.withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final remove = await showDialog<bool>(
                          context: ctx,
                          builder: (d) => AlertDialog(
                            title: const Text('Remove book?'),
                            content: const Text(
                              'This will remove it from your library. '
                              'The file will not be deleted.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(d, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(d, true),
                                child: const Text(
                                  'Remove',
                                  style: TextStyle(color: Colors.redAccent),
                                ),
                              ),
                            ],
                          ),
                        );
                        if (remove == true && mounted) {
                          final n = ref.read(libraryBooksProvider.notifier);
                          n.removeBook(book.filePath);
                          await n.saveToPrefs();
                          if (ctx.mounted) Navigator.pop(ctx);
                        }
                      },
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('Remove'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    } catch (_) {}
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

    // Filter books by search query
    final List<BookModel> filtered = _searchQuery.isEmpty
        ? allBooks
        : allBooks
              .where(
                (BookModel b) =>
                    b.title.toLowerCase().contains(_searchQuery) ||
                    b.author.toLowerCase().contains(_searchQuery),
              )
              .toList();

    final List<BookModel> sortedBooks = _sortBooks(filtered, _sortMode);
    final List<BookModel> continueReading =
        filtered.where((BookModel b) => b.readingProgress > 0.05).toList()
          ..sort(
            (BookModel a, BookModel b) =>
                b.readingProgress.compareTo(a.readingProgress),
          );

    final int inProgress = allBooks
        .where((b) => b.readingProgress > 0.01)
        .length;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // FIX 3 — Minimal top bar: Reverie + search + avatar
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: _hasScrolled
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.transparent,
                    width: 0.5,
                  ),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _isSearching
                          ? TextField(
                              key: const ValueKey('search_field'),
                              controller: _searchController,
                              autofocus: true,
                              style: TextStyle(
                                color: scheme.onSurface,
                                fontSize: 18,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Search books...',
                                hintStyle: TextStyle(
                                  color: scheme.onSurface.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                                border: InputBorder.none,
                                prefixIcon: Icon(
                                  Icons.search,
                                  color: scheme.onSurface.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                              ),
                              onChanged: (String val) {
                                setState(
                                  () => _searchQuery = val.toLowerCase(),
                                );
                              },
                            )
                          : Text(
                              'Reverie',
                              key: const ValueKey('reverie_title'),
                              style: GoogleFonts.cormorantGaramond(
                                fontSize: 28,
                                fontWeight: FontWeight.w300,
                                color: scheme.onSurface,
                                letterSpacing: 2,
                              ),
                            ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        if (_isSearching) {
                          _isSearching = false;
                          _searchQuery = '';
                          _searchController.clear();
                        } else {
                          _isSearching = true;
                        }
                      });
                    },
                    icon: Icon(
                      _isSearching ? Icons.close_rounded : Icons.search_rounded,
                      color: muted,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => context.push('/profile'),
                    child: SupabaseService.isLoggedIn
                        ? CircleAvatar(
                            radius: 16,
                            backgroundColor: const Color(0xFFE94560),
                            child: Text(
                              SupabaseService.displayName.isNotEmpty
                                  ? SupabaseService.displayName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          )
                        : CircleAvatar(
                            radius: 16,
                            backgroundColor: const Color(0xFFE94560),
                            child: Icon(
                              Icons.person_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                  ),
                ],
              ),
            ),
            // FIX 1 — Scanning indicator BELOW the top bar
            if (isScanning)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 6),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor: AlwaysStoppedAnimation(
                          Color(0xFFe94560)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      scanProgress.isEmpty
                        ? 'Scanning for books...'
                        : scanProgress,
                      style: TextStyle(
                        color: muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            if (_isSearching && _searchQuery.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 20, bottom: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${filtered.length} books found',
                    style: const TextStyle(
                      color: Color(0xFFE94560),
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: sortedBooks.isEmpty
                  ? _buildEmptyState(scheme, muted)
                  : RefreshIndicator(
                      color: const Color(0xFFE94560),
                      onRefresh: _onRefresh,
                      child: _buildMainContent(
                        sortedBooks,
                        continueReading,
                        scheme,
                        muted,
                        totalBooks: allBooks.length,
                        inProgress: inProgress,
                      ),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: ScaleTransition(
        scale: _fabScale,
        child: FloatingActionButton(
          onPressed: _pickAndAddBook,
          backgroundColor: const Color(0xFFE94560),
          child: const Icon(Icons.add, color: Colors.white),
        ),
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
          if (!SupabaseService.isLoggedIn) ...[
            const SizedBox(height: 24),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: muted.withValues(alpha: 0.15)),
              ),
              child: Column(
                children: [
                  Icon(Icons.cloud_outlined, color: muted, size: 28),
                  const SizedBox(height: 8),
                  Text(
                    'Sign in to access your cloud library',
                    style: TextStyle(color: muted, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => context.go('/auth'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE94560),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 8,
                      ),
                    ),
                    child: const Text('Sign In'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMainContent(
    List<BookModel> sortedBooks,
    List<BookModel> continueReading,
    ColorScheme scheme,
    Color muted, {
    int totalBooks = 0,
    int inProgress = 0,
  }) {
    return ListView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: <Widget>[
        // Stats bar
        if (totalBooks > 0 && !_isSearching)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        '$totalBooks',
                        style: const TextStyle(
                          color: Color(0xFFE94560),
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'books',
                        style: TextStyle(color: muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height: 30,
                  color: muted.withValues(alpha: 0.2),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        '$inProgress',
                        style: const TextStyle(
                          color: Color(0xFFE94560),
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'in progress',
                        style: TextStyle(color: muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height: 30,
                  color: muted.withValues(alpha: 0.2),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        _formatTotalTime(_totalReadingMinutes),
                        style: const TextStyle(
                          color: Color(0xFFE94560),
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'read',
                        style: TextStyle(color: muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height: 30,
                  color: muted.withValues(alpha: 0.2),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_currentStreak > 2)
                            const Icon(
                              Icons.local_fire_department_rounded,
                              color: Color(0xFFE94560),
                              size: 18,
                            ),
                          Text(
                            '$_currentStreak',
                            style: const TextStyle(
                              color: Color(0xFFE94560),
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'day streak',
                        style: TextStyle(color: muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
                  continueReading[index],
                  scheme,
                  muted,
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
        ...sortedBooks.map(
          (BookModel book) => _buildBookCard(book, scheme, muted),
        ),
        const SizedBox(height: 100),
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

  Widget _buildBookCard(BookModel book, ColorScheme scheme, Color muted) {
    final String readTime = _formatReadingTime(book.fileSizeBytes, wpm: _readingSpeedWpm);
    final int progressPct = (book.readingProgress * 100).round();
    final bool showProgress = book.readingProgress > 0.05;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 16, right: 16),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _onBookTap(book),
        onLongPress: () => _showBookDetail(book, scheme, muted),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
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
                              style: TextStyle(color: muted, fontSize: 12),
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
                                  style: TextStyle(color: muted, fontSize: 11),
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
