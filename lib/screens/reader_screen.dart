import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:epub_view/epub_view.dart' as epub;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// READER SCREEN
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class ReaderScreen extends StatefulWidget {
  final String filePath;
  const ReaderScreen({super.key, required this.filePath});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  epub.EpubController? _controller;
  bool _showControls = false;
  Timer? _hideTimer;
  Timer? _saveDebouncer;

  // Settings
  double _fontSize = 18.0;
  double _lineHeight = 1.8;
  String _fontFamily = 'Georgia';
  Color _bgColor = const Color(0xFF0f0f1a);
  Color _textColor = const Color(0xFFf0f0f0);
  double _brightness = 1.0;
  int _selectedTheme = 0;

  // Progress
  String _currentChapter = '';
  double _progress = 0.0;
  int _totalChapters = 0;
  int _currentChapterIndex = 0;

  // Session tracking
  late final DateTime _sessionStart;

  static const List<Map<String, dynamic>> _themes = [
    {'name': 'Dark', 'bg': Color(0xFF0f0f1a), 'text': Color(0xFFf0f0f0)},
    {'name': 'Black', 'bg': Color(0xFF000000), 'text': Color(0xFFffffff)},
    {'name': 'Paper', 'bg': Color(0xFFf5f0e8), 'text': Color(0xFF1a1a1a)},
    {'name': 'Sepia', 'bg': Color(0xFFfbf0d9), 'text': Color(0xFF5b4636)},
    {'name': 'Forest', 'bg': Color(0xFF1a2e1a), 'text': Color(0xFFc8e6c8)},
  ];

  String get _progressText {
    if (_progress <= 0.01) return 'Start reading';
    if (_progress >= 0.99) return 'Completed';
    return '${(_progress * 100).toInt()}% complete';
  }

  @override
  void initState() {
    super.initState();
    _sessionStart = DateTime.now();
    _loadSettings();
    _initReader();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _saveDebouncer?.cancel();
    _saveSessionTime();
    _controller?.currentValueListenable.removeListener(
        _onScrollPositionChanged);
    _controller?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // PERSISTENCE
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _fontSize = prefs.getDouble('reader_fontSize') ?? 18.0;
        _lineHeight = prefs.getDouble('reader_lineHeight') ?? 1.8;
        _fontFamily = prefs.getString('reader_fontFamily') ?? 'Georgia';
        _selectedTheme = prefs.getInt('reader_theme') ?? 0;
        _brightness = prefs.getDouble('reader_brightness') ?? 1.0;
        // ignore: deprecated_member_use
        _bgColor = Color(prefs.getInt('reader_bgColor') ?? 0xFF0f0f1a);
        // ignore: deprecated_member_use
        _textColor = Color(prefs.getInt('reader_textColor') ?? 0xFFf0f0f0);
        _progress =
            prefs.getDouble('progress_${widget.filePath.hashCode}') ?? 0.0;
      });
    } catch (e) {
      debugPrint('Load settings error: $e');
    }
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('reader_fontSize', _fontSize);
      await prefs.setDouble('reader_lineHeight', _lineHeight);
      await prefs.setString('reader_fontFamily', _fontFamily);
      await prefs.setInt('reader_theme', _selectedTheme);
      await prefs.setDouble('reader_brightness', _brightness);
      // ignore: deprecated_member_use
      await prefs.setInt('reader_bgColor', _bgColor.value);
      // ignore: deprecated_member_use
      await prefs.setInt('reader_textColor', _textColor.value);
    } catch (e) {
      debugPrint('Save settings error: $e');
    }
  }

  Future<void> _saveProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(
          'progress_${widget.filePath.hashCode}', _progress);
    } catch (e) {
      debugPrint('Save progress error: $e');
    }
  }

  void _debouncedSaveProgress() {
    _saveDebouncer?.cancel();
    _saveDebouncer = Timer(const Duration(seconds: 2), _saveProgress);
  }

  Future<void> _loadSavedProgress() async {
    try {
      if (_totalChapters <= 0) return;
      final prefs = await SharedPreferences.getInstance();
      final saved =
          prefs.getDouble('progress_${widget.filePath.hashCode}') ?? 0.0;
      if (saved > 0.01 && mounted) {
        setState(() => _progress = saved);
        final targetIndex =
            (saved * _totalChapters).floor().clamp(0, _totalChapters - 1);
        if (_controller != null && targetIndex > 0) {
          await Future.delayed(const Duration(milliseconds: 800));
          try {
            if (mounted) _controller!.jumpTo(index: targetIndex);
          } catch (e) {
            debugPrint('Jump error: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Load saved progress error: $e');
    }
  }

  void _saveSessionTime() {
    try {
      final duration = DateTime.now().difference(_sessionStart);
      SharedPreferences.getInstance().then((prefs) {
        final existing =
            prefs.getInt('readtime_${widget.filePath.hashCode}') ?? 0;
        prefs.setInt('readtime_${widget.filePath.hashCode}',
            existing + duration.inMinutes);
      });
    } catch (_) {}
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // READER INIT + SCROLL LISTENER
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  void _initReader() {
    try {
      _controller = epub.EpubController(
        document: epub.EpubDocument.openFile(File(widget.filePath)),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_controller == null || !mounted) return;
        _controller!.currentValueListenable
            .addListener(_onScrollPositionChanged);
      });
    } catch (e) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open book: $e')),
        );
        context.pop();
      });
    }
  }

  void _onScrollPositionChanged() {
    try {
      final value = _controller?.currentValueListenable.value;
      if (value == null || _totalChapters <= 0 || !mounted) return;

      final chapterIndex = value.position.index;
      final leadingEdge = value.position.itemLeadingEdge;

      final rawProgress =
          (chapterIndex + (1 - leadingEdge)) / _totalChapters;
      final newProgress = rawProgress.clamp(0.0, 1.0);

      // Never go backwards
      if (newProgress > _progress && mounted) {
        setState(() => _progress = newProgress);
        _debouncedSaveProgress();
      }

      final title = value.chapter?.Title;
      if (title != null && title != _currentChapter) {
        setState(() {
          _currentChapter = title;
          _currentChapterIndex = chapterIndex;
        });
      }
    } catch (_) {}
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // CONTROLS
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

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

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _hideTimer?.cancel();
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _showControls = false);
      });
    } else {
      _hideTimer?.cancel();
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

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // BUILD
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  @override
  Widget build(BuildContext context) {
    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: _bgColor,
        body: GestureDetector(
          onTap: _toggleControls,
          child: ColorFiltered(
            colorFilter: ColorFilter.matrix(<double>[
              _brightness, 0, 0, 0, 0,
              0, _brightness, 0, 0, 0,
              0, 0, _brightness, 0, 0,
              0, 0, 0, 1, 0,
            ]),
            child: Stack(
              children: [
                _buildEpubReader(),
                if (_showControls) _buildTopBar(),
                _buildBottomProgress(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEpubReader() {
    if (_controller == null) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFe94560)),
      );
    }
    return epub.EpubView(
      controller: _controller!,
      onDocumentLoaded: (epub.EpubBook document) {
        if (!mounted) return;
        final total = document.Chapters?.length ?? 0;
        if (total > 0) {
          setState(() => _totalChapters = total);
          Future.delayed(const Duration(milliseconds: 300), () {
            _loadSavedProgress();
          });
        }
      },
      builders: epub.EpubViewBuilders<epub.DefaultBuilderOptions>(
        options: epub.DefaultBuilderOptions(
          chapterPadding: const EdgeInsets.symmetric(
              horizontal: 24, vertical: 16),
          paragraphPadding: const EdgeInsets.symmetric(vertical: 8),
          textStyle: TextStyle(
            fontFamily: _fontFamily,
            fontSize: _fontSize,
            height: _lineHeight,
            color: _textColor,
          ),
        ),
        chapterDividerBuilder: (_) => const SizedBox(height: 32),
      ),
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // TOP BAR — frosted glass blur
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

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
                      icon: Icon(Icons.arrow_back_ios_new_rounded,
                          color: _textColor, size: 20),
                      onPressed: _onWillPop,
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
                      icon: Text('Aa',
                          style: TextStyle(
                              color: _textColor,
                              fontSize: 15,
                              fontWeight: FontWeight.w500)),
                      onPressed: _showSettingsSheet,
                    ),
                    IconButton(
                      icon: Icon(Icons.bookmark_border_rounded,
                          color: _textColor, size: 20),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Bookmarks coming soon'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
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

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // BOTTOM PROGRESS — smooth animated bar
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Widget _buildBottomProgress() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: _progress, end: _progress),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            builder: (ctx, val, _) => LinearProgressIndicator(
              value: val,
              minHeight: 2,
              backgroundColor: Colors.transparent,
              valueColor:
                  const AlwaysStoppedAnimation(Color(0xFFe94560)),
            ),
          ),
          Container(
            color: _bgColor.withValues(alpha: 0.75),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: SafeArea(
              top: false,
              child: Text(
                _progressText,
                style: TextStyle(
                  color: _textColor.withValues(alpha: 0.5),
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // SETTINGS SHEET — dynamic bg color
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Widget _buildSettingsSheet() {
    return StatefulBuilder(
      builder: (BuildContext context, StateSetter setSheetState) {
        final sheetMuted = _textColor.withValues(alpha: 0.5);
        return Container(
          decoration: BoxDecoration(
            color: _bgColor,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: _textColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text('Reading settings',
                    style: TextStyle(
                        color: _textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 24),
                // Brightness
                _settingRow(
                  label: 'Brightness',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.brightness_3_rounded,
                          size: 16, color: sheetMuted),
                      SizedBox(
                        width: 120,
                        child: Slider(
                          value: _brightness,
                          min: 0.3,
                          max: 1.0,
                          activeColor: const Color(0xFFe94560),
                          inactiveColor:
                              Colors.grey.withValues(alpha: 0.3),
                          onChanged: (val) {
                            setSheetState(() {
                              setState(() => _brightness = val);
                            });
                          },
                        ),
                      ),
                      Icon(Icons.wb_sunny_rounded,
                          size: 16, color: sheetMuted),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Font size
                _settingRow(
                  label: 'Text size',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _circleButton('-', () {
                        setSheetState(() {
                          setState(() =>
                              _fontSize = (_fontSize - 1).clamp(14, 28));
                        });
                      }),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('${_fontSize.toInt()}',
                            style: TextStyle(
                                color: _textColor, fontSize: 16)),
                      ),
                      _circleButton('+', () {
                        setSheetState(() {
                          setState(() =>
                              _fontSize = (_fontSize + 1).clamp(14, 28));
                        });
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Spacing
                _settingRow(
                  label: 'Spacing',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _spacingPill('Compact', 1.4, setSheetState),
                      const SizedBox(width: 8),
                      _spacingPill('Normal', 1.8, setSheetState),
                      const SizedBox(width: 8),
                      _spacingPill('Relaxed', 2.2, setSheetState),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Font
                _settingRow(
                  label: 'Font',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _fontPill('Serif', 'Georgia', setSheetState),
                      const SizedBox(width: 8),
                      _fontPill('Sans', 'Sans', setSheetState),
                      const SizedBox(width: 8),
                      _fontPill('Mono', 'Mono', setSheetState),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Themes
                Text('Theme',
                    style: TextStyle(
                        color: _textColor.withValues(alpha: 0.6),
                        fontSize: 13)),
                const SizedBox(height: 12),
                Row(
                  children: List.generate(_themes.length, (i) {
                    final theme = _themes[i];
                    final isSelected = _selectedTheme == i;
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedTheme = i;
                            _bgColor = theme['bg'] as Color;
                            _textColor = theme['text'] as Color;
                          });
                          setSheetState(() {});
                        },
                        child: Column(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: theme['bg'] as Color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFFe94560)
                                      : Colors.grey
                                          .withValues(alpha: 0.3),
                                  width: isSelected ? 2.5 : 1,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(theme['name'] as String,
                                style: TextStyle(
                                    color: _textColor
                                        .withValues(alpha: 0.6),
                                    fontSize: 10)),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _settingRow({required String label, required Widget child}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                color: _textColor.withValues(alpha: 0.6), fontSize: 14)),
        child,
      ],
    );
  }

  Widget _circleButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border:
              Border.all(color: _textColor.withValues(alpha: 0.2)),
        ),
        child: Center(
            child: Text(label,
                style: TextStyle(color: _textColor, fontSize: 18))),
      ),
    );
  }

  Widget _spacingPill(String label, double value,
      StateSetter setSheetState) {
    final sel = _lineHeight == value;
    return GestureDetector(
      onTap: () {
        setSheetState(() {
          setState(() => _lineHeight = value);
        });
      },
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFFe94560) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: sel
                  ? const Color(0xFFe94560)
                  : _textColor.withValues(alpha: 0.2)),
        ),
        child: Text(label,
            style: TextStyle(
                color: sel
                    ? Colors.white
                    : _textColor.withValues(alpha: 0.6),
                fontSize: 12)),
      ),
    );
  }

  Widget _fontPill(String label, String fontValue,
      StateSetter setSheetState) {
    final sel = _fontFamily == fontValue;
    return GestureDetector(
      onTap: () {
        setSheetState(() {
          setState(() => _fontFamily = fontValue);
        });
      },
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFFe94560) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: sel
                  ? const Color(0xFFe94560)
                  : _textColor.withValues(alpha: 0.2)),
        ),
        child: Text(label,
            style: TextStyle(
                color: sel
                    ? Colors.white
                    : _textColor.withValues(alpha: 0.6),
                fontSize: 12)),
      ),
    );
  }
}