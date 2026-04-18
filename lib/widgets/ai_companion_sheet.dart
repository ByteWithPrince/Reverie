import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:reverie/providers/pro_provider.dart';
import 'package:reverie/services/ai_service.dart';

const Color _accent = Color(0xFFE94560);

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime time;
  ChatMessage({required this.text, required this.isUser, required this.time});
}

class AiCompanionSheet extends ConsumerStatefulWidget {
  final String bookTitle;
  final String author;
  final String currentChapter;

  const AiCompanionSheet({
    super.key,
    required this.bookTitle,
    required this.author,
    required this.currentChapter,
  });

  @override
  ConsumerState<AiCompanionSheet> createState() => _AiCompanionSheetState();
}

class _AiCompanionSheetState extends ConsumerState<AiCompanionSheet>
    with SingleTickerProviderStateMixin {
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _showUpgradeBanner = false;
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final AnimationController _dotAnim;

  static const List<Map<String, dynamic>> _suggestions = [
    {'text': 'What just happened?', 'pro': false},
    {'text': 'Summarize this chapter', 'pro': false},
    {'text': 'Who are the main characters?', 'pro': false},
    {'text': 'Analyze the themes in depth 🔒', 'pro': true},
    {'text': 'Predict what happens next 🔒', 'pro': true},
    {'text': 'Character psychology deep dive 🔒', 'pro': true},
  ];

  @override
  void initState() {
    super.initState();
    _dotAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _dotAnim.dispose();
    super.dispose();
  }

  Future<void> _sendMessage(String question) async {
    if (question.trim().isEmpty || _isLoading) return;
    setState(() {
      _messages.add(
        ChatMessage(text: question, isUser: true, time: DateTime.now()),
      );
      _isLoading = true;
    });
    _inputController.clear();
    _scrollToBottom();

    try {
      final isPro = ref.read(isProProvider);
      final response = await AiService.askAboutBook(
        bookTitle: widget.bookTitle,
        currentChapter: widget.currentChapter,
        question: question,
        isPro: isPro,
      );

      if (!mounted) return;

      if (response == 'DAILY_LIMIT_REACHED') {
        setState(() {
          _messages.add(
            ChatMessage(
              text:
                  "You have used all 5 free questions "
                  "today. Upgrade to Pro for unlimited "
                  "AI access. Resets tomorrow.",
              isUser: false,
              time: DateTime.now(),
            ),
          );
          _isLoading = false;
        });
        return;
      }

      if (response == 'ADD_API_KEY') {
        setState(() {
          _messages.add(
            ChatMessage(
              text:
                  "Add your free Gemini API key in "
                  "Settings to use AI Companion. "
                  "Get it free at aistudio.google.com",
              isUser: false,
              time: DateTime.now(),
            ),
          );
          _isLoading = false;
        });
        return;
      }

      HapticFeedback.mediumImpact();
      setState(() {
        _messages.add(
          ChatMessage(text: response, isUser: false, time: DateTime.now()),
        );
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(
            ChatMessage(
              text: 'Something went wrong. Please try again.',
              isUser: false,
              time: DateTime.now(),
            ),
          );
          _isLoading = false;
        });
      }
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0f0f1a),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: Column(
          children: [
            _buildHandle(),
            _buildHeader(),
            const SizedBox(height: 2),
            _buildRemainingCount(),
            const SizedBox(height: 4),
            _buildBookInfo(),
            const Divider(color: Colors.white10, height: 24),
            Expanded(
              child: _messages.isEmpty ? _buildSuggestions() : _buildChat(),
            ),
            if (_isLoading) _buildThinkingDots(),
            if (_showUpgradeBanner) _buildUpgradeBanner(),
            const SizedBox(height: 8),
            _buildInputRow(),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildHandle() => Center(
    child: Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );

  Widget _buildHeader() => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Row(
      children: [
        const Icon(Icons.auto_awesome_rounded, color: _accent, size: 22),
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
          icon: const Icon(
            Icons.close_rounded,
            color: Colors.white38,
            size: 22,
          ),
        ),
      ],
    ),
  );

  Widget _buildRemainingCount() => FutureBuilder<int>(
    future: AiService.getRemainingQuestions(),
    builder: (ctx, snap) {
      final remaining = snap.data ?? 5;
      return Text(
        '$remaining questions left today',
        style: TextStyle(
          color: remaining > 0 ? Colors.white38 : Colors.red.shade300,
          fontSize: 11,
        ),
      );
    },
  );

  Widget _buildBookInfo() => Align(
    alignment: Alignment.centerLeft,
    child: Text(
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
  );

  Widget _buildSuggestions() => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Suggested questions',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _suggestions.map((s) {
            final text = s['text'] as String;
            final isPro = s['pro'] as bool;
            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _sendMessage(text);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      text,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    ),
  );

  Widget _buildChat() => ListView.builder(
    controller: _scrollController,
    itemCount: _messages.length,
    itemBuilder: (_, i) => _buildBubble(_messages[i]),
  );

  Widget _buildBubble(ChatMessage msg) {
    final isUser = msg.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? _accent.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isUser ? 12 : 0),
            bottomRight: Radius.circular(isUser ? 0 : 12),
          ),
          border: isUser
              ? Border.all(color: _accent.withValues(alpha: 0.3))
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              msg.text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                '${msg.time.hour.toString().padLeft(2, '0')}:${msg.time.minute.toString().padLeft(2, '0')}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.25),
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThinkingDots() => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: FadeTransition(
        opacity: _dotAnim,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dot(),
            const SizedBox(width: 4),
            _dot(),
            const SizedBox(width: 4),
            _dot(),
          ],
        ),
      ),
    ),
  );

  Widget _dot() => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(
      color: _accent.withValues(alpha: 0.6),
      shape: BoxShape.circle,
    ),
  );

  Widget _buildUpgradeBanner() => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(
      color: _accent.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _accent.withValues(alpha: 0.2)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            'Unlimited AI with Pro',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 13,
            ),
          ),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            context.push('/paywall');
          },
          child: const Text(
            'Upgrade',
            style: TextStyle(
              color: _accent,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildInputRow() => Row(
    children: [
      Expanded(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(24),
          ),
          child: TextField(
            controller: _inputController,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Ask anything about the book...',
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 14,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) _sendMessage(v.trim());
            },
          ),
        ),
      ),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          final t = _inputController.text.trim();
          if (t.isNotEmpty) _sendMessage(t);
        },
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _isLoading ? Colors.grey : _accent,
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
        ),
      ),
    ],
  );
}
