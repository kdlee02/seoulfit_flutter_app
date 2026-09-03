import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_status_bar.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/mascot_widget.dart';
import '../widgets/animations.dart';
import '../widgets/chat_mode_toggle.dart';
import '../config/api_base.dart';
import '../providers/travel_provider.dart';

/// Starter prompts shown before the traveller has typed anything, so the empty
/// chat is an invitation to act rather than a blank box.
const List<String> _starterPrompts = [
  '3 days in Seoul, love cafés & K-pop',
  'Family trip, relaxed pace, halal food',
  'Solo weekend, history & palaces',
  'Foodie night out in Hongdae',
];

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
    await _sendText(_controller.text);
  }

  Future<void> _sendText(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;
    _controller.clear();
    await context.read<TravelProvider>().sendMessage(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TravelProvider>();
    final messages = provider.messages;
    final mq = MediaQuery.of(context);
    final keyboardInset = mq.viewInsets.bottom;
    // viewPadding, not padding: padding.bottom collapses to 0 the moment the
    // keyboard appears, which is half of the jump this screen used to have.
    final safeBottom = mq.viewPadding.bottom;
    final keyboardOpen = keyboardInset > 0;
    _scrollToBottom();

    return Scaffold(
      backgroundColor: kCanvas,
      body: SafeArea(
        // Bottom inset handled by _BottomChrome so it can shrink continuously.
        bottom: false,
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
                  const MascotWidget(size: 38),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SeoulFit Buddy 🐣',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: kInk,
                          ),
                        ),
                        Text(
                          'Ready to explore Seoul?',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12, color: kSubtext),
                        ),
                      ],
                    ),
                  ),
                  const ChatModeToggle(liveMode: false),
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
                        final msg = messages[i];
                        // Each bubble animates in once; existing bubbles keep
                        // their (already-finished) state on rebuild, so only
                        // the newest message slides in.
                        return FadeSlideIn(
                          key: ValueKey('msg_$i'),
                          offsetY: 10,
                          offsetX: msg.isUser ? 24 : -24,
                          child: _ChatBubble(message: msg),
                        );
                      },
                    ),
            ),
            // Suggested prompts: only while the conversation is just starting.
            // Also dropped while the keyboard is up: the fixed chrome above and
            // below the message list already fills a shrunken body, and holding
            // the chips there overflows it. They are a starting hint anyway —
            // nobody needs suggestions while they are mid-sentence.
            if (messages.length <= 1 && !provider.loading && !keyboardOpen)
              _SuggestedPrompts(onTap: _sendText),
            if (provider.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                // Name the URL we actually tried. On a physical device the
                // default apiBase is http://localhost:8000, which is the phone
                // itself — the old ':8000' wording sent you looking at a
                // backend that was running fine on your Mac all along. Pass
                // --dart-define=API_BASE_URL=http://<your-LAN-ip>:8000.
                child: Text(
                  "Can't reach the backend at "
                  '${apiBase.isEmpty ? "same-origin" : apiBase}'
                  ' — on a real device pass --dart-define=API_BASE_URL.',
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
                        onSubmitted: provider.sending ? null : (_) => _send(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PressableScale(
                    onTap: provider.sending ? null : _send,
                    scale: 0.88,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: provider.sending
                            ? kMint.withValues(alpha: 0.4)
                            : kMint,
                        shape: BoxShape.circle,
                        boxShadow:
                            provider.sending ? null : Elevations.mintGlow,
                      ),
                      child: const Icon(Icons.send_rounded,
                          color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            // The tab bar and the home-indicator inset used to vanish the
            // instant viewInsets.bottom became non-zero, while Scaffold had
            // shrunk the body by only a pixel. Net effect: the input row
            // lurched 105px DOWN out from under the user's finger on the first
            // frame of the keyboard animation. The tap never landed, focus was
            // never taken, the keyboard retracted and the bar sprang back —
            // "the whole bar comes down and I can't type". Collapse them in
            // step with the keyboard instead.
            _BottomChrome(keyboardInset: keyboardInset, safeBottom: safeBottom),
          ],
        ),
      ),
    );
  }
}

/// Tab bar + home-indicator inset, consumed by the keyboard from the bottom up
/// rather than removed all at once.
///
/// Their combined height exactly matches how much Scaffold shrinks the body, so
/// the input row above stays put until the keyboard has eaten both, then rides
/// up with it. Removing them on `viewInsets.bottom > 0` instead made the row
/// jump down by their full height on the animation's first frame.
class _BottomChrome extends StatelessWidget {
  final double keyboardInset;
  final double safeBottom;

  const _BottomChrome({required this.keyboardInset, required this.safeBottom});

  /// Matches the fixed height in AppBottomNav.
  static const double _navHeight = 72;

  @override
  Widget build(BuildContext context) {
    // The keyboard covers the home-indicator gap first, then the tab bar.
    final safeLeft = (safeBottom - keyboardInset).clamp(0.0, safeBottom);
    final eatenFromNav = (keyboardInset - safeBottom).clamp(0.0, _navHeight);
    final navLeft = _navHeight - eatenFromNav;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (navLeft > 0)
          // Align's heightFactor reserves a fraction of the child's height and
          // ClipRect hides the rest, so the bar slides out of view instead of
          // being squashed or overflowing.
          ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: navLeft / _navHeight,
              child: const AppBottomNav(currentIndex: 0),
            ),
          ),
        SizedBox(height: safeLeft),
      ],
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
          const MascotWidget(size: 96, variant: MascotVariant.loading),
          const SizedBox(height: 18),
          Text(
            'Saying hello…',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13, color: kSubtext, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

/// Round buddy avatar backed by the real mascot art (no emoji-as-icon).
class _BuddyAvatar extends StatelessWidget {
  const _BuddyAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      padding: const EdgeInsets.all(3),
      decoration: const BoxDecoration(color: kYellowLight, shape: BoxShape.circle),
      child: Image.asset('assets/images/seoulfit_mascot.png',
          fit: BoxFit.contain),
    );
  }
}

class _SuggestedPrompts extends StatelessWidget {
  final void Function(String) onTap;
  const _SuggestedPrompts({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(Insets.lg, 0, Insets.lg, Insets.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: Insets.sm, left: 2),
            child: Text(
              'Try one of these',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: kSubtext,
                letterSpacing: 0.3,
              ),
            ),
          ),
          Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            children: List.generate(_starterPrompts.length, (i) {
              final prompt = _starterPrompts[i];
              return FadeSlideIn(
                delay: Motion.stagger * i,
                offsetY: 8,
                child: PressableScale(
                  onTap: () => onTap(prompt),
                  borderRadius: BorderRadius.circular(50),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: kCard,
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(color: kMintLight, width: 1.5),
                    ),
                    child: Text(
                      prompt,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: kInk,
                      ),
                    ),
                  ),
                ),
              );
            }),
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
        const _BuddyAvatar(),
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
          const _BuddyAvatar(),
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
