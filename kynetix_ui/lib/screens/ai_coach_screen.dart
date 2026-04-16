import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/ai_coach_service.dart';

// ─── Design constants ─────────────────────────────────────────────────────────
// Top-level so they can be used inside const widget trees.
const _kCard        = Color(0xFF1E1E2C);
const _kBorder      = Color(0xFF2E2E3E);
const _kGreen       = Color(0xFF52B788);
const _kGreenDark   = Color(0xFF2D6A4F);
const _kMuted       = Color(0xFF6B7280);
const _kLight       = Color(0xFF9CA3AF);

// ─── Chat message model ───────────────────────────────────────────────────────

enum _Role { user, assistant }

class _ChatMessage {
  final _Role      role;
  final String     text;
  final Uint8List? imageBytes;
  final String?    providerUsed;
  final bool       fallbackUsed;

  const _ChatMessage({
    required this.role,
    required this.text,
    this.imageBytes,
    this.providerUsed,
    this.fallbackUsed = false,
  });
}

// ─── Quick suggestion chips ───────────────────────────────────────────────────

const _kQuickSuggestions = [
  '🍽️ What should I eat for dinner?',
  '💪 How much protein left?',
  '🌾 How many roti should I eat?',
  '🛵 Best thing to order right now?',
  '⚖️ Will this fit my calories?',
  '🥗 How do I complete my protein today?',
];

// ─── AiCoachScreen ────────────────────────────────────────────────────────────

class AiCoachScreen extends StatefulWidget {
  final String dateKey; // YYYYMMDD

  const AiCoachScreen({super.key, required this.dateKey});

  @override
  State<AiCoachScreen> createState() => _AiCoachScreenState();
}

class _AiCoachScreenState extends State<AiCoachScreen> {
  final _controller    = TextEditingController();
  final _scrollCtrl    = ScrollController();
  final _imagePicker   = ImagePicker();

  // Static so history persists across navigations within the same session.
  static final List<_ChatMessage> _messages = [];

  bool        _loading    = false;
  Uint8List?  _pendingImg; // image attached but not yet sent


  @override
  void dispose() {
    _controller.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> _pickImage() async {
    final xFile = await _imagePicker.pickImage(
      source:      ImageSource.gallery,
      imageQuality: 75,
      maxWidth:    1024,
    );
    if (xFile == null) return;
    final bytes = await xFile.readAsBytes();
    setState(() => _pendingImg = bytes);
  }

  Future<void> _send([String? overrideText]) async {
    final text = (overrideText ?? _controller.text).trim();
    if ((text.isEmpty && _pendingImg == null) || _loading) return;

    final imageBytes = _pendingImg;
    setState(() {
      _messages.add(_ChatMessage(
        role:       _Role.user,
        text:       text,
        imageBytes: imageBytes,
      ));
      _loading    = true;
      _pendingImg = null;
    });
    _controller.clear();
    _scrollToBottom();

    try {
      final res = await AiCoachService.instance.sendMessage(
        message:    text,
        imageBytes: imageBytes,
        dateKey:    widget.dateKey,
      );

      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(
          role:         _Role.assistant,
          text:         res.message,
          providerUsed: res.providerUsed,
          fallbackUsed: res.fallbackUsed,
        ));
        _loading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(
          role: _Role.assistant,
          text: 'Something went wrong: ${e.toString().replaceAll('Exception: ', '')}',
        ));
        _loading = false;
      });
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF13131F),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState()
                : _buildMessageList(),
          ),
          if (_pendingImg != null) _buildImagePreview(),
          _buildInputBar(),
        ],
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF1A1A28),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Row(
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF52B788), Color(0xFF2D6A4F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AI Coach',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
              ),
              Text(
                'Knows your meals & targets',
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      children: [
        // Hero icon
        Center(
          child: Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF52B788), Color(0xFF2D6A4F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: _kGreen.withValues(alpha: 0.3),
                  blurRadius: 20, offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 36),
          ),
        ),
        const SizedBox(height: 20),
        const Center(
          child: Text(
            'Your Nutrition Coach',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22, fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Center(
          child: Text(
            'I already know your meals, calories,\nprotein targets, and eating habits.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _kLight, fontSize: 14, height: 1.5),
          ),
        ),
        const SizedBox(height: 32),
        const Text(
          'Try asking',
          style: TextStyle(color: _kMuted, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.8),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: _kQuickSuggestions.map((s) => _QuickChip(
            label: s,
            onTap: () => _send(s),
          )).toList(),
        ),
        const SizedBox(height: 20),
        // Image upload hint
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2C),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF2E2E3E)),
          ),
          child: Row(
            children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: _kGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.add_photo_alternate_rounded, color: _kGreen, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Upload a menu or food photo', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    SizedBox(height: 2),
                    Text('Swiggy / Zomato screenshots work too', style: TextStyle(color: _kMuted, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: _messages.length + (_loading ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == _messages.length) return const _TypingBubble();
        return _ChatBubble(message: _messages[i]);
      },
    );
  }

  Widget _buildImagePreview() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      height: 72,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(_pendingImg!, width: 72, height: 72, fit: BoxFit.cover),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Image ready to send', style: TextStyle(color: _kLight, fontSize: 13)),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: _kMuted, size: 20),
            onPressed: () => setState(() => _pendingImg = null),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A28),
        border: Border(top: BorderSide(color: const Color(0xFF2E2E3E).withValues(alpha: 0.6))),
      ),
      padding: EdgeInsets.fromLTRB(
        12, 10, 12, MediaQuery.of(context).viewInsets.bottom + 10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Image button
          _IconBtn(
            icon: Icons.add_photo_alternate_rounded,
            color: _pendingImg != null ? _kGreen : _kMuted,
            onTap: _pickImage,
          ),
          const SizedBox(width: 8),
          // Text field
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2C),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF2E2E3E)),
              ),
              child: TextField(
                controller: _controller,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                maxLines:   null,
                minLines:   1,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText:        'Ask anything about your nutrition…',
                  hintStyle:       TextStyle(color: _kMuted, fontSize: 14),
                  border:          InputBorder.none,
                  contentPadding:  EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Send button
          _SendBtn(loading: _loading, onTap: _send),
        ],
      ),
    );
  }
}

// ─── Chat bubble ──────────────────────────────────────────────────────────────

class _ChatBubble extends StatelessWidget {
  final _ChatMessage message;
  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == _Role.user;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            // AI avatar
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_kGreen, _kGreenDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // Image preview (user side only)
                if (message.imageBytes != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        message.imageBytes!,
                        width: 180, height: 180,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                // Bubble
                if (message.text.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isUser ? _kGreenDark : _kCard,
                      borderRadius: BorderRadius.only(
                        topLeft:     const Radius.circular(18),
                        topRight:    const Radius.circular(18),
                        bottomLeft:  Radius.circular(isUser ? 18 : 4),
                        bottomRight: Radius.circular(isUser ? 4 : 18),
                      ),
                      border: Border.all(
                        color: isUser ? _kGreen.withValues(alpha: 0.2) : _kBorder,
                      ),
                    ),
                    child: isUser
                        ? Text(
                            message.text,
                            style: const TextStyle(
                              color: Colors.white, fontSize: 14, height: 1.55,
                            ),
                          )
                        : _MarkdownText(message.text),
                  ),
                  // Provider badge (assistant only)
                if (!isUser && message.providerUsed != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 2),
                    child: _ProviderBadge(
                      provider:     message.providerUsed!,
                      fallbackUsed: message.fallbackUsed,
                    ),
                  ),
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }
}

// ─── Inline markdown renderer ─────────────────────────────────────────────────
// Handles **bold**, *italic*, `code`, and bullet / numbered lists.
// Zero external dependencies — pure Flutter RichText spans.

class _MarkdownText extends StatelessWidget {
  final String text;
  const _MarkdownText(this.text);

  static const _base    = TextStyle(color: Colors.white, fontSize: 14, height: 1.6);
  static const _bold    = TextStyle(color: Colors.white, fontSize: 14, height: 1.6, fontWeight: FontWeight.w700);
  static const _italic  = TextStyle(color: Colors.white, fontSize: 14, height: 1.6, fontStyle: FontStyle.italic);
  static const _code    = TextStyle(color: Color(0xFF52B788), fontSize: 13, height: 1.6, fontFamily: 'monospace');

  /// Splits a line into [TextSpan]s handling **bold**, *italic*, `code`.
  List<TextSpan> _parseInline(String line) {
    final spans = <TextSpan>[];
    // Pattern: **bold** or *italic* or `code`
    final re = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*|`(.+?)`');
    int cursor = 0;
    for (final m in re.allMatches(line)) {
      if (m.start > cursor) {
        spans.add(TextSpan(text: line.substring(cursor, m.start), style: _base));
      }
      if (m.group(1) != null) {
        spans.add(TextSpan(text: m.group(1), style: _bold));
      } else if (m.group(2) != null) {
        spans.add(TextSpan(text: m.group(2), style: _italic));
      } else if (m.group(3) != null) {
        spans.add(TextSpan(text: m.group(3), style: _code));
      }
      cursor = m.end;
    }
    if (cursor < line.length) {
      spans.add(TextSpan(text: line.substring(cursor), style: _base));
    }
    if (spans.isEmpty) spans.add(TextSpan(text: line, style: _base));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    final widgets = <Widget>[];

    for (int i = 0; i < lines.length; i++) {
      final raw = lines[i];
      final trimmed = raw.trim();

      if (trimmed.isEmpty) {
        // Blank line → small gap between paragraphs
        if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 6));
        continue;
      }

      // ── Heading: ### or ## or #
      final headMatch = RegExp(r'^(#{1,3})\s+(.+)$').firstMatch(trimmed);
      if (headMatch != null) {
        final level = headMatch.group(1)!.length;
        final headText = headMatch.group(2)!;
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: Text(
            headText,
            style: TextStyle(
              color: Colors.white,
              fontSize: level == 1 ? 16 : level == 2 ? 15 : 14,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
        ));
        continue;
      }

      // ── Bullet list: - item  or  • item
      final bulletMatch = RegExp(r'^[-•*]\s+(.+)$').firstMatch(trimmed);
      if (bulletMatch != null) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 4, top: 1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 5, right: 8),
                child: CircleAvatar(
                  radius: 3,
                  backgroundColor: Color(0xFF52B788),
                ),
              ),
              Expanded(
                child: RichText(
                  text: TextSpan(children: _parseInline(bulletMatch.group(1)!)),
                ),
              ),
            ],
          ),
        ));
        continue;
      }

      // ── Numbered list: 1. item
      final numMatch = RegExp(r'^(\d+)\.\s+(.+)$').firstMatch(trimmed);
      if (numMatch != null) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 4, top: 1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  '${numMatch.group(1)}.',
                  style: _bold.copyWith(color: const Color(0xFF52B788)),
                ),
              ),
              Expanded(
                child: RichText(
                  text: TextSpan(children: _parseInline(numMatch.group(2)!)),
                ),
              ),
            ],
          ),
        ));
        continue;
      }

      // ── Plain paragraph line
      widgets.add(RichText(
        text: TextSpan(children: _parseInline(trimmed)),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }
}

// ─── Provider badge ───────────────────────────────────────────────────────────

class _ProviderBadge extends StatelessWidget {
  final String provider;
  final bool   fallbackUsed;
  const _ProviderBadge({
    required this.provider,
    required this.fallbackUsed,
  });

  @override
  Widget build(BuildContext context) {
    final isOpenAI = provider == 'openai';

    final Color  color = isOpenAI ? const Color(0xFF52B788) : const Color(0xFF818CF8);
    final String label = isOpenAI ? '⚡ OpenAI' : (fallbackUsed ? '↩ OpenRouter' : '~ OpenRouter');


    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ─── Typing indicator ─────────────────────────────────────────────────────────

class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF52B788), Color(0xFF2D6A4F)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2C),
              borderRadius: const BorderRadius.only(
                topLeft:     Radius.circular(18),
                topRight:    Radius.circular(18),
                bottomRight: Radius.circular(18),
                bottomLeft:  Radius.circular(4),
              ),
              border: Border.all(color: const Color(0xFF2E2E3E)),
            ),
            child: FadeTransition(
              opacity: _anim,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Dot(),
                  SizedBox(width: 5),
                  _Dot(),
                  SizedBox(width: 5),
                  _Dot(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8, height: 8,
      decoration: BoxDecoration(
        color: const Color(0xFF52B788).withValues(alpha: 0.7),
        shape: BoxShape.circle,
      ),
    );
  }
}

// ─── Quick chip ───────────────────────────────────────────────────────────────

class _QuickChip extends StatelessWidget {
  final String       label;
  final VoidCallback onTap;
  const _QuickChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2C),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF2E2E3E)),
        ),
        child: Text(
          label,
          style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
        ),
      ),
    );
  }
}

// ─── Icon button ──────────────────────────────────────────────────────────────

class _IconBtn extends StatelessWidget {
  final IconData     icon;
  final Color        color;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42, height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2C),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: const Color(0xFF2E2E3E)),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }
}

// ─── Send button ──────────────────────────────────────────────────────────────

class _SendBtn extends StatelessWidget {
  final bool     loading;
  final VoidCallback onTap;
  const _SendBtn({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 42, height: 42,
        decoration: BoxDecoration(
          gradient: loading
              ? null
              : const LinearGradient(
                  colors: [Color(0xFF52B788), Color(0xFF2D6A4F)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          color: loading ? const Color(0xFF2E2E3E) : null,
          borderRadius: BorderRadius.circular(13),
        ),
        child: loading
            ? const Center(
                child: SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF52B788),
                  ),
                ),
              )
            : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
      ),
    );
  }
}
