import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:reverie/providers/pro_provider.dart';
import 'package:reverie/screens/library_screen.dart';
import 'package:url_launcher/url_launcher.dart';

const Color _accent = Color(0xFFE94560);

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// BOOK RECOMMENDATION MODEL
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class BookRecommendation {
  final String title;
  final String author;
  final String genre;
  final String description;
  final String downloadUrl;
  final Color coverColor;

  const BookRecommendation({
    required this.title,
    required this.author,
    required this.genre,
    required this.description,
    required this.downloadUrl,
    required this.coverColor,
  });
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// CURATED BOOKS
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

const List<BookRecommendation> _curatedBooks = [
  BookRecommendation(
    title: 'Pride and Prejudice',
    author: 'Jane Austen',
    genre: 'Romance',
    description: 'A witty exploration of love, '
        'class and marriage in 19th century England.',
    downloadUrl: 'https://www.gutenberg.org/ebooks/1342',
    coverColor: Color(0xFF7c6af7),
  ),
  BookRecommendation(
    title: 'The Great Gatsby',
    author: 'F. Scott Fitzgerald',
    genre: 'Fiction',
    description: 'The Jazz Age, wealth, and the '
        'American Dream through one unforgettable summer.',
    downloadUrl: 'https://www.gutenberg.org/ebooks/64317',
    coverColor: Color(0xFF2ec4b6),
  ),
  BookRecommendation(
    title: 'Sherlock Holmes',
    author: 'Arthur Conan Doyle',
    genre: 'Mystery',
    description: "The world's greatest detective "
        'solving impossible crimes with brilliant logic.',
    downloadUrl: 'https://www.gutenberg.org/ebooks/1661',
    coverColor: Color(0xFFe94560),
  ),
  BookRecommendation(
    title: 'Frankenstein',
    author: 'Mary Shelley',
    genre: 'Sci-Fi',
    description: 'The original science fiction story '
        'about creation, responsibility and what makes us human.',
    downloadUrl: 'https://www.gutenberg.org/ebooks/84',
    coverColor: Color(0xFF4a9eff),
  ),
  BookRecommendation(
    title: 'Alice in Wonderland',
    author: 'Lewis Carroll',
    genre: 'Fantasy',
    description: 'A girl falls into a rabbit hole '
        'and enters an impossibly wonderful world.',
    downloadUrl: 'https://www.gutenberg.org/ebooks/11',
    coverColor: Color(0xFFf7b731),
  ),
  BookRecommendation(
    title: 'Dracula',
    author: 'Bram Stoker',
    genre: 'Horror',
    description: 'The original vampire story that '
        'defined a genre and haunts readers still.',
    downloadUrl: 'https://www.gutenberg.org/ebooks/345',
    coverColor: Color(0xFF993C1D),
  ),
  BookRecommendation(
    title: 'The Count of Monte Cristo',
    author: 'Alexandre Dumas',
    genre: 'Adventure',
    description: 'The ultimate revenge story — '
        'betrayal, imprisonment, and triumphant return.',
    downloadUrl: 'https://www.gutenberg.org/ebooks/1184',
    coverColor: Color(0xFF43aa8b),
  ),
  BookRecommendation(
    title: 'War and Peace',
    author: 'Leo Tolstoy',
    genre: 'History',
    description: "Napoleon's invasion of Russia "
        'through the lives of five aristocratic families.',
    downloadUrl: 'https://www.gutenberg.org/ebooks/2600',
    coverColor: Color(0xFF888780),
  ),
];

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// RECOMMENDATIONS SCREEN
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class RecommendationsScreen extends ConsumerStatefulWidget {
  const RecommendationsScreen({super.key});

  @override
  ConsumerState<RecommendationsScreen> createState() =>
      _RecommendationsScreenState();
}

class _RecommendationsScreenState
    extends ConsumerState<RecommendationsScreen> {
  List<String> _detectedGenres = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _detectGenres());
  }

  void _detectGenres() {
    try {
      final books = ref.read(libraryBooksProvider);
      final Set<String> genres = {};
      for (final book in books) {
        final lower =
            '${book.title} ${book.author}'.toLowerCase();
        if (lower.contains('mystery') ||
            lower.contains('detective') ||
            lower.contains('murder')) {
          genres.add('Mystery');
        }
        if (lower.contains('love') ||
            lower.contains('romance') ||
            lower.contains('heart')) {
          genres.add('Romance');
        }
        if (lower.contains('fantasy') ||
            lower.contains('dragon') ||
            lower.contains('magic')) {
          genres.add('Fantasy');
        }
        if (lower.contains('science') ||
            lower.contains('space') ||
            lower.contains('future')) {
          genres.add('Sci-Fi');
        }
        if (lower.contains('history') ||
            lower.contains('war') ||
            lower.contains('ancient')) {
          genres.add('History');
        }
      }
      if (genres.isEmpty && books.isNotEmpty) genres.add('Fiction');
      if (mounted) setState(() => _detectedGenres = genres.toList());
    } catch (_) {}
  }

  static const Map<String, Color> _genreColors = {
    'Fiction': Color(0xFF4a9eff),
    'Romance': Color(0xFFe94560),
    'Mystery': Color(0xFF7c6af7),
    'Fantasy': Color(0xFFf7b731),
    'Sci-Fi': Color(0xFF2ec4b6),
    'History': Color(0xFF888780),
    'Horror': Color(0xFF993C1D),
    'Adventure': Color(0xFF43aa8b),
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.5);
    final isPro = ref.watch(isProProvider);

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            // Header
            Row(
              children: [
                Text(
                  'Discover',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 26,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 1,
                  ),
                ),
                if (!isPro) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'PRO',
                      style: TextStyle(
                        color: _accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),

            // Genre pills
            if (_detectedGenres.isNotEmpty) ...[
              Text('Based on your reading',
                  style: TextStyle(
                      color: muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _detectedGenres.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final genre = _detectedGenres[i];
                    final color =
                        _genreColors[genre] ?? const Color(0xFF4a9eff);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: color.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        genre,
                        style: TextStyle(
                            color: color,
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 28),
            ],

            // Curated books header
            Text('You might like',
                style: TextStyle(
                    color: muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),

            // Book cards
            ...List.generate(_curatedBooks.length, (i) {
              final book = _curatedBooks[i];
              return _buildBookCard(book, scheme, muted);
            }),

            const SizedBox(height: 20),

            // Pro teaser banner
            if (!isPro)
              GestureDetector(
                onTap: () => context.push('/paywall'),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: _accent.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.auto_awesome_rounded,
                          color: _accent, size: 28),
                      const SizedBox(height: 12),
                      Text(
                        'AI Recommendations coming to Pro',
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Get suggestions based on exactly what '
                        'you love to read, powered by AI',
                        style: TextStyle(
                            color: muted, fontSize: 13, height: 1.4),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => context.push('/paywall'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(
                                vertical: 12),
                          ),
                          child: const Text('Upgrade to Pro'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildBookCard(
    BookRecommendation book,
    ColorScheme scheme,
    Color muted,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            // Cover placeholder
            Container(
              width: 56,
              height: 72,
              decoration: BoxDecoration(
                color: book.coverColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  book.title[0],
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(book.title,
                      style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(book.author,
                      style: TextStyle(color: muted, fontSize: 12)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: _accent.withValues(alpha: 0.3)),
                    ),
                    child: Text(book.genre,
                        style: const TextStyle(
                            color: _accent, fontSize: 10)),
                  ),
                  const SizedBox(height: 4),
                  Text(book.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: muted, fontSize: 12, height: 1.3)),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Download button
            IconButton(
              onPressed: () => _showDownloadSheet(book),
              icon: Icon(Icons.download_rounded,
                  color: muted, size: 22),
            ),
          ],
        ),
      ),
    );
  }

  void _showDownloadSheet(BookRecommendation book) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFF1a1a2e),
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(book.title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            Text('by ${book.author}',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 14)),
            const SizedBox(height: 16),
            Text(
              'Download this EPUB from Project Gutenberg, '
              'then Reverie will automatically find it '
              'in your Downloads folder.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 14,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () async {
                  try {
                    Navigator.pop(context);
                    await launchUrl(
                      Uri.parse(book.downloadUrl),
                      mode: LaunchMode.externalApplication,
                    );
                  } catch (_) {}
                },
                icon: const Icon(Icons.open_in_browser_rounded,
                    color: Colors.white),
                label: const Text('Open in Browser',
                    style: TextStyle(
                        color: Colors.white, fontSize: 15)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4))),
            ),
          ],
        ),
      ),
    );
  }
}
