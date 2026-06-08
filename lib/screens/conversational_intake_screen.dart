import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_status_bar.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/mascot_widget.dart';
import '../providers/travel_provider.dart';
import '../utils/app_state.dart';

class ConversationalIntakeScreen extends StatefulWidget {
  const ConversationalIntakeScreen({super.key});

  @override
  State<ConversationalIntakeScreen> createState() =>
      _ConversationalIntakeScreenState();
}

class _ConversationalIntakeScreenState
    extends State<ConversationalIntakeScreen> {
  final _controller = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    AppState.hasChatData = true;
    // Kick off the backend greeting once the first frame is mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TravelProvider>().startGreeting();
    });
  }

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
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    await context.read<TravelProvider>().sendMessage(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TravelProvider>();
    final messages = provider.messages;
    _scrollToBottom();

    return Scaffold(
      backgroundColor: kCanvas,
      body: SafeArea(
        child: Column(
          children: [
            const AppStatusBar(),
            // Header
            Container(
              color: kCard,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const MascotWidget(size: 38, variant: MascotVariant.chip),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SeoulFit Buddy 🐣',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: kInk,
                          ),
                        ),
                        Text(
                          'Ready to explore Seoul?',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12, color: kSubtext),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: kMintLight,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'AI Chat',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: kMint),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Messages
            Expanded(
              child: messages.isEmpty && provider.loading
                  ? const _GreetingLoader()
                  : ListView.separated(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length + (provider.loading ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) {
                        if (i == messages.length) {
                          return const _TypingIndicator();
                        }
                        return _ChatBubble(message: messages[i]);
                      },
                    ),
            ),
            if (provider.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Connection error — is the backend running on :8000?',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, color: kWarningBorder),
                ),
              ),
            // Proceed button — enabled once the backend has collected slots.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: provider.state == null
                      ? null
                      : () => Navigator.pushNamed(context, '/slot-parsing'),
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: const Text('Confirm & Parse My Request'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kMint,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: kMint.withValues(alpha: 0.4),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50)),
                    elevation: 0,
                    textStyle: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ),
            ),
            // Input field
            Container(
              color: kCard,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: kCanvas,
                        borderRadius: BorderRadius.circular(50),
                        border: Border.all(color: kCardBorder),
                      ),
                      child: TextField(
                        controller: _controller,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 14, color: kInk),
                        decoration: InputDecoration(
                          hintText: 'Type your travel preference...',
                          hintStyle: GoogleFonts.plusJakartaSans(
                              fontSize: 14, color: kSubtext),
                          isDense: true,
                          border: InputBorder.none,
                        ),
                        maxLines: null,
                        textInputAction: TextInputAction.send,
                        onSubmitted: provider.loading ? null : (_) => _send(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: provider.loading ? null : _send,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                          color: provider.loading
                              ? kMint.withValues(alpha: 0.4)
                              : kMint,
                          shape: BoxShape.circle),
                      child: const Icon(Icons.send_rounded,
                          color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            const AppBottomNav(currentIndex: 0),
          ],
        ),
      ),
    );
  }
}

class _GreetingLoader extends StatelessWidget {
  const _GreetingLoader();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🐣', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 14),
          Text(
            'Saying hello…',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13, color: kSubtext, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 16),
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: kMint),
          ),
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
              color: kYellow, shape: BoxShape.circle),
          child: const Center(child: Text('🐣', style: TextStyle(fontSize: 14))),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kCardBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: kMint),
              ),
              const SizedBox(width: 10),
              Text(
                'Buddy is thinking…',
                style: GoogleFonts.plusJakartaSans(fontSize: 13, color: kInk),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Row(
      mainAxisAlignment:
          isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!isUser) ...[
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
                color: kYellow, shape: BoxShape.circle),
            child: const Center(
              child: Text('🐣', style: TextStyle(fontSize: 14)),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: isUser ? kMint : kCard,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isUser ? 18 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 18),
              ),
              border: isUser ? null : Border.all(color: kCardBorder),
              boxShadow: [
                BoxShadow(
                  color: kMint.withValues(alpha: isUser ? 0.18 : 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Text(
              message.text,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: isUser ? Colors.white : kInk,
                height: 1.5,
              ),
            ),
          ),
        ),
        if (isUser) ...[
          const SizedBox(width: 8),
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              color: kMintLight,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                'U',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: kMint),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
