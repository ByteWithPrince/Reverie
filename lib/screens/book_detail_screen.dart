import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:reverie/screens/library_screen.dart';
import 'package:reverie/services/ai_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const Color _accent = Color(0xFFE94560);

class BookDetailScreen extends ConsumerStatefulWidget {
  final BookModel book;
  const BookDetailScreen({super.key, required this.book});

  @override
  ConsumerState<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends ConsumerState<BookDetailScreen> {
  String? _summary;
  bool _loadingSummary = true;

  BookModel get book => widget.book;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    try {
      final summary = await _getSummary();
      if (mounted) setState(() { _summary = summary; _loadingSummary = false; });
    } catch (_) {
      if (mounted) setState(() { _summary = null; _loadingSummary = false; });
    }
  }

  Future<String> _getSummary() async {
    // Try Gemini first
    if (AiService.isConfigured) {
      return await AiService.getBookSummary(
        bookTitle: book.title,
        author: book.author,
      );
    }
    // Fallback: contextual placeholder
    final authorPart = book.author != 'Unknown Author'
        ? 'A ${book.author} classic. '
        : '';
    return '${authorPart}Tap "Read" to begin your journey through '
        '"${book.title}". '
        'Add your Gemini API key in Settings '
        'to unlock AI-powered book summaries.';
  }

  String _estimateReadTime(int bytes) {
    if (bytes <= 0) return '~1h read';
    final words = bytes ~/ 6;
    final minutes = words ~/ 250;
    if (minutes < 60) return '~${minutes}m read';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m > 0 ? '~${h}h ${m}m read' : '~${h}h read';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.5);
    final progressPct = (book.readingProgress * 100).round();
    final coverColor = _coverColorForBook(book.title);

    return Scaffold(
      backgroundColor: scheme.surface,
      body: CustomScrollView(slivers: [
        // Top cover area
        SliverToBoxAdapter(child: _buildCoverSection(coverColor, scheme)),
        // Content
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Title + author
            Text(book.title, style: TextStyle(color: scheme.onSurface,
              fontSize: 24, fontWeight: FontWeight.w500), maxLines: 3),
            const SizedBox(height: 6),
            Text(book.author, style: TextStyle(color: muted, fontSize: 16)),
            const SizedBox(height: 12),
            // Info row
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6)),
                child: const Text('EPUB', style: TextStyle(
                  color: _accent, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 10),
              Text(_estimateReadTime(book.fileSizeBytes),
                style: TextStyle(color: muted, fontSize: 13)),
            ]),
            const SizedBox(height: 16),
            // Progress
            if (book.readingProgress > 0.01) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: book.readingProgress, minHeight: 4,
                  backgroundColor: muted.withValues(alpha: 0.15),
                  valueColor: const AlwaysStoppedAnimation(_accent)),
              ),
              const SizedBox(height: 6),
              Text('$progressPct% complete',
                style: TextStyle(color: muted, fontSize: 12)),
              const SizedBox(height: 16),
            ],
            // Action buttons
            _buildActionButtons(scheme, muted),
            const SizedBox(height: 28),
            // About
            Text('About this book', style: TextStyle(color: scheme.onSurface,
              fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 12),
            _buildSummarySection(muted),
            const SizedBox(height: 40),
          ]),
        )),
      ]),
    );
  }

  Widget _buildCoverSection(Color coverColor, ColorScheme scheme) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.4,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [coverColor, scheme.surface],
          stops: const [0.6, 1.0],
        ),
      ),
      child: Stack(children: [
        // Back button
        Positioned(top: 0, left: 0, child: SafeArea(child: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
            color: Colors.white.withValues(alpha: 0.9), size: 20),
          onPressed: () { if (context.canPop()) context.pop(); else context.go('/library'); },
        ))),
        // Cover
        Center(child: Padding(
          padding: const EdgeInsets.only(top: 24),
          child: book.coverBase64 != null && book.coverBase64!.isNotEmpty
              ? _buildImageCover()
              : _buildLetterCover(coverColor),
        )),
      ]),
    );
  }

  Widget _buildImageCover() {
    try {
      return Container(
        width: 120, height: 170,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 20)],
          image: DecorationImage(
            image: MemoryImage(base64Decode(book.coverBase64!)),
            fit: BoxFit.cover),
        ),
      );
    } catch (_) {
      return _buildLetterCover(Colors.grey);
    }
  }

  Widget _buildLetterCover(Color color) {
    return Container(
      width: 120, height: 170,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 20)],
      ),
      child: Center(child: Text(
        book.title.isNotEmpty ? book.title[0].toUpperCase() : '?',
        style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w300),
      )),
    );
  }

  Widget _buildActionButtons(ColorScheme scheme, Color muted) {
    return Row(children: [
      Expanded(child: ElevatedButton.icon(
        onPressed: () {
          final encoded = Uri.encodeComponent(book.filePath);
          // Mark as read
          try {
            final notifier = ref.read(libraryBooksProvider.notifier);
            notifier.updateBook(book.filePath, (b) => b.copyWith(isNew: false));
            notifier.saveToPrefs();
          } catch (_) {}
          context.go('/reader?path=$encoded');
        },
        icon: const Icon(Icons.auto_stories_rounded, size: 18),
        label: Text(book.readingProgress > 0.01 ? 'Continue' : 'Read'),
        style: ElevatedButton.styleFrom(
          backgroundColor: _accent, foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 14)),
      )),
      const SizedBox(width: 10),
      _actionIconBtn(Icons.share_rounded, scheme, muted, () {
        try { Share.share('I\'m reading "${book.title}" by ${book.author} on Reverie'); } catch (_) {}
      }),
      const SizedBox(width: 8),
      _actionIconBtn(Icons.delete_outline_rounded, scheme, muted, _confirmRemove,
        iconColor: Colors.redAccent.withValues(alpha: 0.7)),
    ]);
  }

  Widget _actionIconBtn(IconData icon, ColorScheme scheme, Color muted,
      VoidCallback onTap, {Color? iconColor}) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: muted.withValues(alpha: 0.3)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.all(12), minimumSize: const Size(48, 48)),
      child: Icon(icon, size: 20, color: iconColor ?? scheme.onSurface),
    );
  }

  void _confirmRemove() async {
    try {
      final remove = await showDialog<bool>(context: context,
        builder: (d) => AlertDialog(
          title: const Text('Remove book?'),
          content: const Text('This will remove it from your library. The file won\'t be deleted.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(d, true),
              child: const Text('Remove', style: TextStyle(color: Colors.redAccent))),
          ],
        ));
      if (remove == true && mounted) {
        ref.read(libraryBooksProvider.notifier).removeBook(book.filePath);
        ref.read(libraryBooksProvider.notifier).saveToPrefs();
        if (context.canPop()) context.pop(); else context.go('/library');
      }
    } catch (_) {}
  }

  Widget _buildSummarySection(Color muted) {
    if (_loadingSummary) {
      return Column(
        children: List.generate(3, (_) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            height: 14,
            decoration: BoxDecoration(
              color: muted.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        )),
      );
    }
    return Text(
      _summary ?? 'Open this book to start your adventure.',
      style: TextStyle(color: muted, fontSize: 14, height: 1.6),
    );
  }

  Color _coverColorForBook(String title) {
    const colors = [
      Color(0xFF7c6af7), Color(0xFF2ec4b6), Color(0xFFe94560),
      Color(0xFF4a9eff), Color(0xFFf7b731), Color(0xFF993C1D),
      Color(0xFF43aa8b), Color(0xFF888780),
    ];
    return colors[title.length % colors.length];
  }
}
