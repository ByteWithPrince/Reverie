import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:epub_view/epub_view.dart' as epub;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:reverie/services/goals_service.dart';
import 'package:reverie/services/streak_service.dart';
import 'package:reverie/services/sync_service.dart';
import 'package:reverie/widgets/ai_companion_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// TOC ENTRY MODEL
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class TocEntry {
  final String title;
  final String href;
  final int index;
  TocEntry({required this.title, required this.href, required this.index});
}

Future<List<TocEntry>> parseEpubToc(String filePath) async {
  final List<TocEntry> entries = [];
  try {
    final bytes = await File(filePath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    ArchiveFile? navFile, ncxFile;
    for (final file in archive) {
      final name = file.name.toLowerCase();
      if (name.endsWith('nav.xhtml') || name.contains('nav.html')) {
        navFile = file;
      }
      if (name.endsWith('.ncx')) ncxFile = file;
    }
    if (navFile != null) _parseNav(navFile, entries);
    if (entries.isEmpty && ncxFile != null) _parseNcx(ncxFile, entries);
  } catch (e) {
    debugPrint('TOC parse error: $e');
  }
  return entries;
}

void _parseNav(ArchiveFile file, List<TocEntry> entries) {
  final content = utf8.decode(file.content as List<int>);
  final regex = RegExp(
    r'<a[^>]*href="([^"]*)"[^>]*>([^<]+)<\/a>',
    caseSensitive: false,
  );
  int i = 0;
  for (final m in regex.allMatches(content)) {
    final title = m.group(2)?.trim() ?? '';
    final href = m.group(1)?.trim() ?? '';
    if (title.isNotEmpty && !href.startsWith('http') && title.length < 100) {
      entries.add(TocEntry(title: title, href: href, index: i++));
    }
  }
}

void _parseNcx(ArchiveFile file, List<TocEntry> entries) {
  final content = utf8.decode(file.content as List<int>);
  final regex = RegExp(
    r'<navPoint[^>]*>.*?<text>([^<]+)<\/text>.*?<content\s+src="([^"]*)"',
    caseSensitive: false,
    dotAll: true,
  );
  int i = 0;
  for (final m in regex.allMatches(content)) {
    final title = m.group(1)?.trim() ?? '';
    final href = m.group(2)?.trim() ?? '';
    if (title.isNotEmpty) {
      entries.add(TocEntry(title: title, href: href, index: i++));
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// READER SCREEN
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

const Color _accent = Color(0xFFe94560);

class ReaderScreen extends ConsumerStatefulWidget {
  final String filePath;
  const ReaderScreen({super.key, required this.filePath});

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen>
    with TickerProviderStateMixin {
  // Core
  epub.EpubController? _controller;
  bool _loadError = false;
  String _errorMessage = '';

  // Controls
  bool _showControls = false;
  Timer? _hideTimer;
  Timer? _saveDebouncer;
  late final AnimationController _controlsAnim;
  late final Animation<double> _controlsOpacity;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Settings
  double _fontSize = 18.0;
  double _lineHeight = 1.8;
  String _fontFamily = 'Georgia';
  double _horizontalMargin = 24.0;
  Color _bgColor = const Color(0xFFf5e6c8); // Sepia default
  Color _textColor = const Color(0xFF3a2e1e); // Sepia default
  double _brightness = 1.0;
  int _selectedTheme = 1; // Sepia default
  String _flowMode = 'Scrolled';

  // Progress — FIX 5
  String _currentChapter = '';
  double _scrollProgress = 0.0; // 0.0 to 1.0
  int _totalChapters = 0;
  int _currentChapterIndex = 0;
  int _currentItemIndex = 0;
  double _currentLeadingEdge = 0.0;
  List<TocEntry> _tocEntries = [];
  List<epub.EpubChapter> _epubChapters = [];

  // Paged mode
  PageController? _pageController;
  List<String> _chapterContents = [];
  bool _isLoadingChapters = false;

  // Reading speed
  DateTime? _lastChapterTime;
  double _readingSpeedWpm = 0;

  // Welcome overlay
  bool _showWelcome = false;
  late final AnimationController _welcomeAnim;
  late final Animation<double> _welcomeOpacity;

  // Session
  late final DateTime _sessionStart;

  // FIX 4 — Updated themes with Sepia as default (index 1)
  static const List<Map<String, dynamic>> _themes = [
    {'name': 'Dark', 'bg': Color(0xFF0f0f1a), 'text': Color(0xFFe8e8e8)},
    {'name': 'Sepia', 'bg': Color(0xFFf5e6c8), 'text': Color(0xFF3a2e1e)},
    {'name': 'Paper', 'bg': Color(0xFFfafaf8), 'text': Color(0xFF1a1a1a)},
    {'name': 'Dusk', 'bg': Color(0xFF2d2433), 'text': Color(0xFFe2d9f3)},
    {'name': 'Forest', 'bg': Color(0xFF1a2e1a), 'text': Color(0xFFc8e6c8)},
  ];

  String get _bookName =>
      widget.filePath.split('/').last.replaceAll('.epub', '');

  String _getFontFamily() {
    switch (_fontFamily) {
      case 'Sans':
        return 'sans-serif';
      case 'Mono':
        return 'monospace';
      default:
        return 'Georgia';
    }
  }

  String get _progressText {
    if (_scrollProgress <= 0.01) return 'Start reading';
    if (_scrollProgress >= 0.99) return '✓ Completed';
    final percent = (_scrollProgress * 100).toInt();
    return '$percent% complete';
  }

  // ━━━ LIFECYCLE ━━━

  @override
  void initState() {
    super.initState();
    _sessionStart = DateTime.now();
    _controlsAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _controlsOpacity = CurvedAnimation(
      parent: _controlsAnim,
      curve: Curves.easeInOut,
    );
    _welcomeAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _welcomeOpacity = CurvedAnimation(
      parent: _welcomeAnim,
      curve: Curves.easeInOut,
    );
    _loadSettings().then((_) {
      if (_flowMode == 'Auto') _applySmartTheme();
    });
    _initReader();
    _loadToc();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    try {
      StreakService.recordReadingToday();
    } catch (_) {}
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _saveDebouncer?.cancel();
    _pageController?.dispose();
    _saveSessionTime();
    _syncToCloud();
    _controlsAnim.dispose();
    _welcomeAnim.dispose();
    _controller?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ━━━ LOAD / SAVE ━━━

  Future<void> _loadSettings() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _fontSize = p.getDouble('reader_fontSize') ?? 18.0;
        _lineHeight = p.getDouble('reader_lineHeight') ?? 1.8;
        _fontFamily = p.getString('reader_fontFamily') ?? 'Georgia';
        _horizontalMargin = p.getDouble('reader_margin') ?? 24.0;
        _selectedTheme = p.getInt('reader_theme') ?? 1;
        _brightness = p.getDouble('reader_brightness') ?? 1.0;
        _flowMode = p.getString('reader_flowMode') ?? 'Scrolled';
        // ignore: deprecated_member_use
        _bgColor = Color(p.getInt('reader_bgColor') ?? 0xFFf5e6c8);
        // ignore: deprecated_member_use
        _textColor = Color(p.getInt('reader_textColor') ?? 0xFF3a2e1e);
        _scrollProgress =
            p.getDouble('progress_${widget.filePath.hashCode}') ?? 0.0;
        _readingSpeedWpm = p.getDouble('reading_speed_wpm') ?? 0;
      });
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble('reader_fontSize', _fontSize);
      await p.setDouble('reader_lineHeight', _lineHeight);
      await p.setString('reader_fontFamily', _fontFamily);
      await p.setDouble('reader_margin', _horizontalMargin);
      await p.setInt('reader_theme', _selectedTheme);
      await p.setDouble('reader_brightness', _brightness);
      await p.setString('reader_flowMode', _flowMode);
      // ignore: deprecated_member_use
      await p.setInt('reader_bgColor', _bgColor.value);
      // ignore: deprecated_member_use
      await p.setInt('reader_textColor', _textColor.value);
    } catch (_) {}
  }

  // FIX 5 — Save progress with index and leading edge
  Future<void> _saveProgress() async {
    try {
      final p = await SharedPreferences.getInstance();
      final key = 'progress_${widget.filePath.hashCode}';
      await p.setDouble(key, _scrollProgress);
      await p.setInt('${key}_index', _currentItemIndex);
      await p.setDouble('${key}_leading', _currentLeadingEdge);
    } catch (_) {}
  }

  void _debouncedSaveProgress() {
    _saveDebouncer?.cancel();
    _saveDebouncer = Timer(const Duration(seconds: 3), () {
      _saveProgress();
    });
  }

  // FIX 5 — Load and restore exact position
  Future<void> _loadSavedProgress() async {
    try {
      if (_totalChapters <= 0) return;
      final p = await SharedPreferences.getInstance();
      final key = 'progress_${widget.filePath.hashCode}';
      final savedProgress = p.getDouble(key) ?? 0.0;
      final savedIndex = p.getInt('${key}_index') ?? 0;

      if (savedProgress > 0.01 && mounted) {
        setState(() => _scrollProgress = savedProgress);

        if (savedIndex > 0 && _controller != null) {
          await Future.delayed(const Duration(milliseconds: 500));
          try {
            if (mounted) _controller!.jumpTo(index: savedIndex);
          } catch (e) {
            debugPrint('Resume error: $e');
          }
        }
      }
    } catch (_) {}
  }

  void _saveSessionTime() {
    try {
      final mins = DateTime.now().difference(_sessionStart).inMinutes;
      if (mins > 0) GoalsService.recordMinutes(mins);
      SharedPreferences.getInstance().then((p) {
        final existing = p.getInt('readtime_${widget.filePath.hashCode}') ?? 0;
        p.setInt('readtime_${widget.filePath.hashCode}', existing + mins);
      });
    } catch (_) {}
  }

  void _syncToCloud() {
    try {
      final mins = DateTime.now().difference(_sessionStart).inMinutes;
      SyncService.syncBookProgress(
        fileName: widget.filePath.split('/').last,
        title: _currentChapter.isNotEmpty ? _currentChapter : _bookName,
        author: '',
        progress: _scrollProgress,
        totalMinutes: mins,
      );
      SyncService.syncReadingSession(bookTitle: _bookName, minutesRead: mins);
    } catch (_) {}
  }

  Future<void> _loadToc() async {
    try {
      final entries = await parseEpubToc(widget.filePath);
      if (mounted) setState(() => _tocEntries = entries);
    } catch (_) {}
  }

  // ━━━ READER INIT ━━━

  void _initReader() {
    try {
      _controller = epub.EpubController(
        document: epub.EpubDocument.openFile(File(widget.filePath)),
      );
      if (mounted) setState(() => _loadError = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = true;
          _errorMessage = '$e';
        });
      }
    }
  }

  // FIX 5 — onChapterChanged with accurate progress + reading speed
  void _onChapterChanged(dynamic value) {
    if (value == null || !mounted) return;
    try {
      final index = value.position?.index ?? 0;
      final leading = value.position?.itemLeadingEdge ?? 1.0;
      final title = value.chapter?.Title ?? _currentChapter;

      setState(() {
        _currentChapter = title;
        _currentItemIndex = index;
        _currentLeadingEdge = leading;
        _currentChapterIndex = index;
      });

      // Reading speed calculation
      const avgWordsPerChapter = 3000;
      if (_lastChapterTime != null) {
        final elapsed = DateTime.now()
            .difference(_lastChapterTime!)
            .inSeconds;
        if (elapsed > 10 && elapsed < 600) {
          final wpm = (avgWordsPerChapter / elapsed) * 60;
          if (wpm > 50 && wpm < 1000) {
            _readingSpeedWpm =
                (_readingSpeedWpm * 0.7) + (wpm * 0.3);
            SharedPreferences.getInstance().then((p) =>
                p.setDouble('reading_speed_wpm',
                    _readingSpeedWpm));
          }
        }
      }
      _lastChapterTime = DateTime.now();

      if (_totalChapters > 0) {
        final positionInChapter = (1.0 - leading).clamp(0.0, 1.0);
        final rawProgress = (index + positionInChapter) / _totalChapters;
        final newProgress = rawProgress.clamp(0.0, 1.0);
        if ((newProgress - _scrollProgress).abs() > 0.001) {
          _scrollProgress = newProgress;
          _debouncedSaveProgress();
        }
      }
    } catch (e) {
      debugPrint('Chapter changed error: $e');
    }
  }

  void _onDocLoaded(epub.EpubBook document) {
    if (!mounted) return;
    final chapters = document.Chapters ?? [];
    if (chapters.isEmpty) return;
    setState(() {
      _totalChapters = chapters.length;
      _epubChapters = chapters;
    });
    if (_tocEntries.isEmpty) {
      setState(() {
        _tocEntries = chapters
            .asMap()
            .entries
            .map(
              (e) => TocEntry(
                title: e.value.Title ?? 'Chapter ${e.key + 1}',
                href: '',
                index: e.key,
              ),
            )
            .toList();
      });
    }
    Future.delayed(const Duration(milliseconds: 300), _loadSavedProgress);
    // Show welcome overlay for fresh books
    if (_scrollProgress < 0.01) {
      setState(() => _showWelcome = true);
      _welcomeAnim.forward();
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && _showWelcome) _dismissWelcome();
      });
    }
  }

  // ━━━ SMART AUTO BRIGHTNESS ━━━

  void _applySmartTheme() {
    final hour = DateTime.now().hour;
    if (_flowMode == 'Auto') {
      if (hour >= 6 && hour < 10) {
        // Morning: warm paper
        setState(() {
          _bgColor = const Color(0xFFfafaf8);
          _textColor = const Color(0xFF1a1a1a);
          _selectedTheme = 2;
          _brightness = 0.95;
        });
      } else if (hour >= 10 && hour < 18) {
        // Day: clean paper
        setState(() {
          _bgColor = const Color(0xFFfafaf8);
          _textColor = const Color(0xFF1a1a1a);
          _selectedTheme = 2;
          _brightness = 1.0;
        });
      } else if (hour >= 18 && hour < 21) {
        // Evening: sepia warm
        setState(() {
          _bgColor = const Color(0xFFf5e6c8);
          _textColor = const Color(0xFF3a2e1e);
          _selectedTheme = 1;
          _brightness = 0.9;
        });
      } else {
        // Night: dark mode
        setState(() {
          _bgColor = const Color(0xFF0f0f1a);
          _textColor = const Color(0xFFe8e8e8);
          _selectedTheme = 0;
          _brightness = 0.7;
        });
      }
    }
  }

  // ━━━ PAGED MODE — Chapter loading ━━━

  Future<void> _loadChapterContents() async {
    if (_isLoadingChapters) return;
    _isLoadingChapters = true;

    try {
      final bytes = await File(widget.filePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // Find OPF to get spine order
      String? opfContent;
      String opfBasePath = '';

      // Find container.xml first
      for (final file in archive) {
        if (file.name == 'META-INF/container.xml') {
          final content = utf8.decode(file.content as List<int>);
          final pathMatch = RegExp(
              r'full-path="([^"]+)"').firstMatch(content);
          if (pathMatch != null) {
            final opfPath = pathMatch.group(1)!;
            opfBasePath = opfPath.contains('/')
                ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
                : '';

            // Find and read OPF
            for (final f in archive) {
              if (f.name == opfPath) {
                opfContent = utf8.decode(f.content as List<int>);
                break;
              }
            }
          }
          break;
        }
      }

      if (opfContent == null) {
        _isLoadingChapters = false;
        return;
      }

      // Parse spine order
      final spineMatches = RegExp(
          r'<itemref\s+idref="([^"]+)"').allMatches(opfContent);

      // Build id to href map from manifest
      final manifestMap = <String, String>{};
      final manifestMatches = RegExp(
          r'<item[^>]+id="([^"]+)"[^>]+href="([^"]+)"')
          .allMatches(opfContent);
      for (final m in manifestMatches) {
        manifestMap[m.group(1)!] = m.group(2)!;
      }

      // Get chapter HTMLs in spine order
      final chapters = <String>[];

      for (final spineMatch in spineMatches) {
        final idref = spineMatch.group(1)!;
        final href = manifestMap[idref];
        if (href == null) continue;

        final fullPath = opfBasePath + href.split('#').first;

        for (final file in archive) {
          if (file.name == fullPath ||
              file.name.endsWith(href.split('#').first)) {
            try {
              final html = utf8.decode(file.content as List<int>);
              chapters.add(html);
            } catch (e) {
              chapters.add('<p>Chapter</p>');
            }
            break;
          }
        }
      }

      if (mounted) {
        setState(() {
          _chapterContents = chapters;
          _totalChapters = chapters.length;
          _pageController = PageController(
            initialPage: _currentItemIndex
                .clamp(0, chapters.isEmpty ? 0 : chapters.length - 1),
          );
        });
      }
    } catch (e) {
      debugPrint('Chapter load error: $e');
    } finally {
      _isLoadingChapters = false;
    }
  }

  Widget _buildPagedChapter(String html, int index) {
    // ignore: deprecated_member_use
    final textHex = _textColor.value.toRadixString(16).substring(2);
    // ignore: deprecated_member_use
    final bgHex = _bgColor.value.toRadixString(16).substring(2);
    final styledHtml = '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
<style>
  * { box-sizing: border-box; margin: 0; }
  body {
    font-family: ${_getFontFamily()};
    font-size: ${_fontSize.toInt()}px;
    line-height: $_lineHeight;
    color: #$textHex;
    background: #$bgHex;
    padding: 24px ${_horizontalMargin.toInt()}px 80px ${_horizontalMargin.toInt()}px;
    text-align: justify;
    word-spacing: 0.5px;
    letter-spacing: 0.15px;
  }
  h1, h2, h3, h4 {
    font-size: ${(_fontSize * 1.3).toInt()}px;
    font-weight: 500;
    margin-bottom: 16px;
    margin-top: 24px;
    line-height: 1.4;
    text-align: left;
  }
  p { margin-bottom: ${(_lineHeight * _fontSize * 0.4).toInt()}px; }
  img { max-width: 100%; height: auto; display: block; margin: 16px auto; }
  a { color: #e94560; text-decoration: none; }
</style>
</head>
<body>
$html
</body>
</html>
''';

    return WebViewWidget(
      controller: WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(_bgColor)
        ..loadHtmlString(styledHtml),
    );
  }

  // ━━━ UI ACTIONS ━━━

  Future<bool> _onWillPop() async {
    try {
      await _saveProgress();
      await _saveSettings();
    } catch (_) {}
    if (!mounted) return true;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/library');
    }
    return false;
  }

  // FIX 5 — toggleControls does NOT touch _scrollProgress
  void _toggleControls() {
    if (_showControls) {
      _controlsAnim.reverse().then((_) {
        if (mounted) setState(() => _showControls = false);
      });
      _hideTimer?.cancel();
    } else {
      setState(() => _showControls = true);
      _controlsAnim.forward();
      _hideTimer?.cancel();
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          _controlsAnim.reverse().then((_) {
            if (mounted) setState(() => _showControls = false);
          });
        }
      });
    }
  }

  void _showSettingsSheet() {
    _hideTimer?.cancel();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _buildSettingsSheet(),
    ).then((_) => _saveSettings());
  }

  void _showAiCompanion() {
    try {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => AiCompanionSheet(
          bookTitle: _bookName,
          author: '',
          currentChapter: _currentChapter,
        ),
      );
    } catch (_) {}
  }

  // ━━━ BUILD ━━━

  @override
  Widget build(BuildContext context) {
    if (_loadError) return _buildErrorScreen();
    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: _bgColor,
        drawer: _buildTocDrawer(),
        body: GestureDetector(
          onTap: _toggleControls,
          child: Stack(
            children: [
              _buildReader(),
              if (_showControls)
                FadeTransition(
                  opacity: _controlsOpacity,
                  child: _buildTopBar(),
                ),
              _buildBottomProgress(),
              if (_showWelcome) _buildWelcomeOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  // ━━━ FIX 4 — IMMERSIVE READER WITH PAGED MODE ━━━

  Widget _buildReader() {
    if (_controller == null) {
      return Center(
        child: CircularProgressIndicator(color: _accent, strokeWidth: 1.5),
      );
    }

    // PAGED MODE — chapter by chapter PageView
    if (_flowMode == 'Paged') {
      if (_chapterContents.isEmpty) {
        _loadChapterContents();
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                color: _accent,
                strokeWidth: 1.5,
              ),
              const SizedBox(height: 16),
              Text(
                'Preparing pages...',
                style: TextStyle(
                  color: _textColor.withValues(alpha: 0.5),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        );
      }

      return PageView.builder(
        controller: _pageController,
        itemCount: _chapterContents.length,
        onPageChanged: (index) {
          if (!mounted) return;
          setState(() {
            _currentItemIndex = index;
            _currentChapterIndex = index;
            if (_epubChapters.isNotEmpty &&
                index < _epubChapters.length) {
              _currentChapter =
                  _epubChapters[index].Title ??
                      'Chapter ${index + 1}';
            }
          });
          // Update progress
          if (_totalChapters > 0) {
            _scrollProgress = index / _totalChapters;
            _debouncedSaveProgress();
          }
        },
        itemBuilder: (ctx, index) {
          return ColorFiltered(
            colorFilter: ColorFilter.matrix(<double>[
              _brightness, 0, 0, 0, 0,
              0, _brightness, 0, 0, 0,
              0, 0, _brightness, 0, 0,
              0, 0, 0, 1, 0,
            ]),
            child: _buildPagedChapter(
                _chapterContents[index], index),
          );
        },
      );
    }

    // SCROLLED MODE (default) — existing EpubView
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(<double>[
        _brightness, 0, 0, 0, 0,
        0, _brightness, 0, 0, 0,
        0, 0, _brightness, 0, 0,
        0, 0, 0, 1, 0,
      ]),
      child: epub.EpubView(
        controller: _controller!,
        onChapterChanged: _onChapterChanged,
        onDocumentLoaded: _onDocLoaded,
        builders: epub.EpubViewBuilders<epub.DefaultBuilderOptions>(
          options: epub.DefaultBuilderOptions(
            chapterPadding: EdgeInsets.only(
              left: _horizontalMargin,
              right: _horizontalMargin,
              top: 48,
              bottom: 120,
            ),
            paragraphPadding: EdgeInsets.only(
              bottom: _lineHeight * _fontSize * 0.5,
            ),
            textStyle: TextStyle(
              fontFamily: _getFontFamily(),
              fontSize: _fontSize,
              height: _lineHeight,
              color: _textColor,
              letterSpacing: 0.15,
              wordSpacing: 0.5,
            ),
          ),
          chapterDividerBuilder: (_) => Container(
            margin: EdgeInsets.symmetric(
              horizontal: _horizontalMargin,
              vertical: 48,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 0.5,
                    color: _textColor.withValues(alpha: 0.12),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    '✦',
                    style: TextStyle(
                      color: _textColor.withValues(alpha: 0.25),
                      fontSize: 12,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    height: 0.5,
                    color: _textColor.withValues(alpha: 0.12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            color: _bgColor.withValues(alpha: 0.75),
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 52,
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: _textColor,
                        size: 20,
                      ),
                      onPressed: _onWillPop,
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.format_list_bulleted_rounded,
                        color: _textColor,
                        size: 20,
                      ),
                      onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                    ),
                    Expanded(
                      child: Text(
                        _currentChapter.isEmpty
                            ? 'Loading...'
                            : _currentChapter,
                        style: TextStyle(
                          color: _textColor.withValues(alpha: 0.7),
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Text(
                        'Aa',
                        style: TextStyle(
                          color: _textColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      onPressed: _showSettingsSheet,
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.auto_awesome_rounded,
                        color: _textColor,
                        size: 20,
                      ),
                      onPressed: _showAiCompanion,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // FIX 5 — Bottom progress uses _scrollProgress + reading speed
  Widget _buildBottomProgress() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: _scrollProgress, end: _scrollProgress),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            builder: (_, v, __) => LinearProgressIndicator(
              value: v,
              minHeight: 2,
              backgroundColor: Colors.transparent,
              valueColor: const AlwaysStoppedAnimation(_accent),
            ),
          ),
          Container(
            color: _bgColor.withValues(alpha: 0.75),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _progressText,
                    style: TextStyle(
                      color: _textColor.withValues(alpha: 0.5),
                      fontSize: 11,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_readingSpeedWpm > 0 && _showControls)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '${_readingSpeedWpm.toInt()} words/min',
                        style: TextStyle(
                          color: _textColor.withValues(alpha: 0.3),
                          fontSize: 10,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // FIX 7 — TOC with 350ms delay
  Widget _buildTocDrawer() {
    final w = MediaQuery.of(context).size.width * 0.82;
    return SizedBox(
      width: w,
      child: Drawer(
        backgroundColor: _bgColor,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _bookName,
                      style: TextStyle(
                        color: _textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_tocEntries.length} chapters',
                      style: TextStyle(
                        color: _textColor.withValues(alpha: 0.4),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(color: _textColor.withValues(alpha: 0.08), height: 1),
              Expanded(
                child: _tocEntries.isEmpty
                    ? Center(
                        child: Text(
                          'Loading...',
                          style: TextStyle(
                            color: _textColor.withValues(alpha: 0.5),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _tocEntries.length,
                        itemBuilder: _buildTocItem,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTocItem(BuildContext ctx, int i) {
    final e = _tocEntries[i];
    final cur = i == _currentChapterIndex;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        // FIX 7 — Close drawer, then jump after 350ms
        onTap: () {
          Navigator.pop(ctx);
          Future.delayed(const Duration(milliseconds: 350), () {
            if (!mounted) return;
            try {
              _controller?.jumpTo(index: i);
              setState(() {
                _currentChapterIndex = i;
                _currentChapter =
                    _epubChapters.isNotEmpty && i < _epubChapters.length
                    ? (_epubChapters[i].Title ?? 'Chapter ${i + 1}')
                    : (i < _tocEntries.length
                          ? _tocEntries[i].title
                          : 'Chapter ${i + 1}');
              });
              HapticFeedback.mediumImpact();
            } catch (e) {
              debugPrint('TOC jump error: $e');
            }
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: _textColor.withValues(alpha: 0.06),
                width: 0.5,
              ),
            ),
            color: cur ? _accent.withValues(alpha: 0.1) : Colors.transparent,
          ),
          child: Row(
            children: [
              if (cur)
                Container(
                  width: 3,
                  height: 16,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: _accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              Expanded(
                child: Text(
                  e.title,
                  style: TextStyle(
                    color: cur ? _accent : _textColor.withValues(alpha: 0.85),
                    fontSize: 14,
                    fontWeight: cur ? FontWeight.w500 : FontWeight.normal,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (cur)
                const Icon(Icons.bookmark_rounded, color: _accent, size: 14),
            ],
          ),
        ),
      ),
    );
  }

  void _dismissWelcome() {
    _welcomeAnim.reverse().then((_) {
      if (mounted) setState(() => _showWelcome = false);
    });
  }

  Widget _buildWelcomeOverlay() {
    return FadeTransition(
      opacity: _welcomeOpacity,
      child: GestureDetector(
        onTap: _dismissWelcome,
        child: Container(
          color: Colors.black.withValues(alpha: 0.6),
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 48),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
              decoration: BoxDecoration(
                color: const Color(0xFF1a1a2e),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.auto_stories_rounded,
                    color: _accent,
                    size: 36,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _bookName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Tap to begin reading',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tap screen for settings',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF0f0f1a),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 64,
                  color: Colors.redAccent,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Could not open book',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.filePath.split('/').last,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (_errorMessage.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: 11,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _loadError = false;
                        _errorMessage = '';
                      });
                      _initReader();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Try Again'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/library');
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Go Back'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ━━━ SETTINGS SHEET (FIX 6 — Flow mode added) ━━━

  Widget _buildSettingsSheet() {
    return StatefulBuilder(
      builder: (ctx, setSheet) {
        final m = _textColor.withValues(alpha: 0.5);
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.78,
          ),
          decoration: BoxDecoration(
            color: _bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle + header
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: _textColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Text(
                      'Reading',
                      style: TextStyle(
                        color: _textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: m, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // FIX 6 — FLOW MODE (at top)
                _sectionLabel('FLOW', m),
                const SizedBox(height: 12),
                _flowModeRow(setSheet),
                const SizedBox(height: 20),

                // DISPLAY
                _sectionLabel('DISPLAY', m),
                const SizedBox(height: 12),
                _brightnessRow(m, setSheet),
                const SizedBox(height: 16),
                _fontSizeRow(setSheet),
                const SizedBox(height: 20),

                // TYPOGRAPHY
                _sectionLabel('TYPOGRAPHY', m),
                const SizedBox(height: 12),
                _pillRow(
                  'Font',
                  ['Serif', 'Sans', 'Mono'],
                  _fontFamily == 'Georgia' ? 'Serif' : _fontFamily,
                  (v) {
                    setSheet(() {
                      setState(
                        () => _fontFamily = v == 'Serif' ? 'Georgia' : v,
                      );
                    });
                  },
                ),
                const SizedBox(height: 12),
                _pillRow(
                  'Spacing',
                  ['Tight', 'Normal', 'Loose'],
                  _lineHeight <= 1.5
                      ? 'Tight'
                      : _lineHeight <= 2.0
                      ? 'Normal'
                      : 'Loose',
                  (v) {
                    final h = v == 'Tight'
                        ? 1.4
                        : v == 'Normal'
                        ? 1.8
                        : 2.4;
                    setSheet(() {
                      setState(() => _lineHeight = h);
                    });
                  },
                ),
                const SizedBox(height: 12),
                _pillRow(
                  'Margins',
                  ['Narrow', 'Normal', 'Wide'],
                  _horizontalMargin <= 18
                      ? 'Narrow'
                      : _horizontalMargin <= 30
                      ? 'Normal'
                      : 'Wide',
                  (v) {
                    final mg = v == 'Narrow'
                        ? 16.0
                        : v == 'Normal'
                        ? 24.0
                        : 40.0;
                    setSheet(() {
                      setState(() => _horizontalMargin = mg);
                    });
                  },
                ),
                const SizedBox(height: 20),

                // THEME
                _sectionLabel('THEME', m),
                const SizedBox(height: 12),
                _themeRow(setSheet),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  // FIX 6 — Flow mode row
  Widget _flowModeRow(StateSetter setSheet) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Flow',
          style: TextStyle(
            color: _textColor.withValues(alpha: 0.6),
            fontSize: 14,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _flowModeButton(
              icon: Icons.text_fields_rounded,
              label: 'Auto',
              mode: 'Auto',
              setSheetState: setSheet,
            ),
            const SizedBox(width: 8),
            _flowModeButton(
              icon: Icons.menu_book_rounded,
              label: 'Paged',
              mode: 'Paged',
              setSheetState: setSheet,
            ),
            const SizedBox(width: 8),
            _flowModeButton(
              icon: Icons.format_align_justify_rounded,
              label: 'Scrolled',
              mode: 'Scrolled',
              setSheetState: setSheet,
            ),
          ],
        ),
      ],
    );
  }

  Widget _flowModeButton({
    required IconData icon,
    required String label,
    required String mode,
    required StateSetter setSheetState,
  }) {
    final isSelected = _flowMode == mode;
    return GestureDetector(
      onTap: () {
        setSheetState(() {
          setState(() {
            _flowMode = mode;
            if (mode == 'Paged') {
              _loadChapterContents();
            } else if (mode == 'Scrolled') {
              _pageController?.dispose();
              _pageController = null;
              _chapterContents = [];
            } else if (mode == 'Auto') {
              _pageController?.dispose();
              _pageController = null;
              _chapterContents = [];
              _applySmartTheme();
            }
          });
        });
        _saveSettings();
      },
      child: Container(
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? _accent.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? _accent : _textColor.withValues(alpha: 0.15),
            width: isSelected ? 1.5 : 0.5,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 22,
              color: isSelected ? _accent : _textColor.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isSelected ? _accent : _textColor.withValues(alpha: 0.5),
                fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
            if (mode == 'Auto' && isSelected)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Time-aware',
                  style: TextStyle(
                    color: _textColor.withValues(alpha: 0.4),
                    fontSize: 8,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text, Color m) => Text(
    text,
    style: TextStyle(
      color: m,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 1,
    ),
  );

  Widget _brightnessRow(Color m, StateSetter s) => Row(
    children: [
      Icon(Icons.brightness_3_rounded, size: 16, color: m),
      Expanded(
        child: Slider(
          value: _brightness,
          min: 0.3,
          max: 1.0,
          activeColor: _accent,
          inactiveColor: Colors.grey.withValues(alpha: 0.3),
          onChanged: (v) {
            s(() {
              setState(() => _brightness = v);
            });
          },
        ),
      ),
      Icon(Icons.wb_sunny_rounded, size: 16, color: m),
    ],
  );

  Widget _fontSizeRow(StateSetter s) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      _circleBtn('−', () {
        s(() {
          setState(() => _fontSize = (_fontSize - 1).clamp(14, 28));
        });
      }),
      Text(
        '${_fontSize.toInt()}',
        style: TextStyle(color: _textColor, fontSize: 16),
      ),
      _circleBtn('+', () {
        s(() {
          setState(() => _fontSize = (_fontSize + 1).clamp(14, 28));
        });
      }),
    ],
  );

  Widget _circleBtn(String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _textColor.withValues(alpha: 0.2)),
      ),
      child: Center(
        child: Text(label, style: TextStyle(color: _textColor, fontSize: 18)),
      ),
    ),
  );

  Widget _pillRow(
    String label,
    List<String> items,
    String selected,
    ValueChanged<String> onTap,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: _textColor.withValues(alpha: 0.6),
            fontSize: 14,
          ),
        ),
        Row(
          children: items.map((v) {
            final sel = v == selected;
            return Padding(
              padding: const EdgeInsets.only(left: 8),
              child: GestureDetector(
                onTap: () => onTap(v),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: sel ? _accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: sel ? _accent : _textColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Text(
                    v,
                    style: TextStyle(
                      color: sel
                          ? Colors.white
                          : _textColor.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _themeRow(StateSetter s) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: List.generate(_themes.length, (i) {
      final t = _themes[i];
      final sel = _selectedTheme == i;
      return GestureDetector(
        onTap: () {
          setState(() {
            _selectedTheme = i;
            _bgColor = t['bg'] as Color;
            _textColor = t['text'] as Color;
          });
          s(() {});
        },
        child: Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: t['bg'] as Color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: sel ? _accent : Colors.grey.withValues(alpha: 0.3),
                  width: sel ? 3 : 1,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              t['name'] as String,
              style: TextStyle(
                color: _textColor.withValues(alpha: 0.5),
                fontSize: 9,
              ),
            ),
          ],
        ),
      );
    }),
  );
}
