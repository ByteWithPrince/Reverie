import 'dart:async';
import 'dart:io';

import 'package:epub_view/epub_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfx/pdfx.dart';
import 'package:reverie/theme/app_theme.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({
    super.key,
    required this.filePath,
    required this.fileType,
  });

  final String filePath;
  final String fileType;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  PdfControllerPinch? _pdfController;
  EpubController? _epubController;
  Timer? _hideControlsTimer;

  int _currentPage = 1;
  int _totalPages = 0;
  String _epubProgress = 'Chapter 1';
  bool _showControls = true;
  bool _hasLoadError = false;
  late final String _resolvedType;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _resolvedType = _resolveFileType();

    if (widget.filePath.isEmpty) {
      _hasLoadError = true;
      return;
    }

    if (_resolvedType == 'epub') {
      _epubController = EpubController(
        document: EpubDocument.openFile(File(widget.filePath)),
      );
    } else {
      _pdfController = PdfControllerPinch(
        document: PdfDocument.openFile(widget.filePath),
      );
    }

    _startAutoHideTimer();
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _pdfController?.dispose();
    _epubController?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  String _resolveFileType() {
    if (widget.fileType == 'epub' || widget.fileType == 'pdf') {
      return widget.fileType;
    }
    return widget.filePath.toLowerCase().endsWith('.epub') ? 'epub' : 'pdf';
  }

  void _startAutoHideTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startAutoHideTimer();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  Widget _buildReaderContent() {
    if (_resolvedType == 'epub' && _epubController != null) {
      return EpubView(
        controller: _epubController!,
        onChapterChanged: (dynamic value) {
          if (!mounted || value == null) {
            return;
          }
          final dynamic chapterTitle = value.chapter?.Title;
          final String title = chapterTitle is String ? chapterTitle.trim() : '';
          setState(() {
            _epubProgress =
                title.isEmpty ? 'Chapter ${value.chapterNumber + 1}' : title;
          });
        },
      );
    }

    if (_pdfController != null) {
      return PdfViewPinch(
        controller: _pdfController!,
        scrollDirection: Axis.horizontal,
        onDocumentLoaded: (PdfDocument document) {
          if (mounted) {
            setState(() {
              _totalPages = document.pagesCount;
            });
          }
        },
        onPageChanged: (int page) {
          if (mounted) {
            setState(() {
              _currentPage = page;
            });
          }
        },
      );
    }

    return const Center(child: Text('Unable to open this file.'));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ThemeMode mode = ref.watch(themeModeProvider);
    final bool isDark = mode == ThemeMode.dark;
    final Color textColor = theme.textTheme.bodyLarge?.color ??
        (isDark ? const Color(0xFFF0F0F0) : const Color(0xFF1A1A1A));

    final String progressText = _resolvedType == 'epub'
        ? _epubProgress
        : '$_currentPage / ${_totalPages == 0 ? '--' : _totalPages}';

    if (_hasLoadError) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              IconButton(
                onPressed: () => context.pop(),
                icon: Icon(Icons.arrow_back, color: textColor),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    'Unable to open this file.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        child: Stack(
          children: <Widget>[
            _buildReaderContent(),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              left: 0,
              right: 0,
              bottom: _showControls ? 0 : -88,
              child: SafeArea(
                top: false,
                child: Container(
                  color: Colors.black54,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  child: Row(
                    children: <Widget>[
                      IconButton(
                        onPressed: () => context.pop(),
                        icon: Icon(Icons.arrow_back, color: textColor),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            progressText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: textColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          ref.read(themeModeProvider.notifier).state =
                              isDark ? ThemeMode.light : ThemeMode.dark;
                        },
                        icon: Icon(
                          isDark
                              ? Icons.light_mode_rounded
                              : Icons.dark_mode_rounded,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
