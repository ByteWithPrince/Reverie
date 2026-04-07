import 'package:flutter/material.dart';

const Color _accent = Color(0xFFE94560);

class AiCompanionSheet extends StatefulWidget {
  final String bookTitle;
  final String currentChapter;

  const AiCompanionSheet({
    super.key,
    required this.bookTitle,
    required this.currentChapter,
  });

  @override
  State<AiCompanionSheet> createState() => _AiCompanionSheetState();
}

class _AiCompanionSheetState extends State<AiCompanionSheet> {
  final TextEditingController _inputController = TextEditingController();

  static const List<String> _suggestions = [
    'Summarize this chapter',
    'Who are the main characters?',
    'What are the key themes?',
    'Explain what just happened',
    'What should I expect next?',
  ];

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _onSend(String question) {
    try {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('AI Companion coming soon in a future update'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1a1a2e),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Title row
            Row(
              children: [
                const Icon(Icons.auto_awesome_rounded,
                    color: _accent, size: 22),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'AI Companion',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded,
                      color: Colors.white38, size: 22),
                ),
              ],
            ),

            // Book info
            const SizedBox(height: 4),
            Text(
              widget.currentChapter.isNotEmpty
                  ? '${widget.bookTitle} · ${widget.currentChapter}'
                  : widget.bookTitle,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 20),

            // Suggestions
            Text('Suggested questions',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _suggestions.map((q) {
                return GestureDetector(
                  onTap: () => _onSend(q),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Text(
                      q,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Input field
            Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _inputController,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Ask anything about the book...',
                        hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.3),
                            fontSize: 14),
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                      ),
                      onSubmitted: (val) {
                        if (val.trim().isNotEmpty) _onSend(val.trim());
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    final text = _inputController.text.trim();
                    if (text.isNotEmpty) _onSend(text);
                  },
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _accent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.send_rounded,
                        color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
