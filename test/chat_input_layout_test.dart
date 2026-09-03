// Regression tests for "I opened the app on my iPhone and tried to type in the
// chat but it wouldn't let me."
//
// Two separate defects produced that symptom, both invisible on the iOS
// Simulator with a hardware keyboard and a backend on localhost:
//
//   1. ConversationalIntakeScreen fires startGreeting() on mount. The composer
//      gated its send button and its return key on TravelProvider.loading,
//      which is also true for that automatic greeting. ApiService.chat() had no
//      timeout, so against a host that drops packets rather than refusing them
//      the greeting never completed and the composer stayed dead forever. You
//      could put the caret in the field and type, and nothing would send.
//
//   2. The header Row packed a MascotVariant.chip pill (which renders
//      "SeoulFit Buddy" and ignores `size` for its width), a title column, and
//      the Plan/On-trip toggle into one row. It overflowed at every iPhone
//      width, ellipsizing both title lines.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:seoulfit_flutter/providers/travel_provider.dart';
import 'package:seoulfit_flutter/screens/conversational_intake_screen.dart';

/// iPhone 17 / 16 / 15 / 14 logical size, and the smallest phone still on iOS 18.
const _iPhone17 = Size(402, 874);
const _iPhoneSE = Size(375, 667);

/// iOS software keyboard heights, English QWERTY with the suggestion strip.
const _keyboardTall = 336.0;
const _keyboardShort = 260.0;

/// Pumps the chat screen at [size] with [keyboardInset] logical pixels of
/// bottom viewInsets, as the framework reports while the keyboard is up.
///
/// These go on the *view*, not a MediaQuery widget: MaterialApp builds its own
/// MediaQuery.fromView internally, so a MediaQuery wrapped around it is
/// silently discarded.
Future<TravelProvider> _pumpChat(
  WidgetTester tester, {
  Size size = _iPhone17,
  double keyboardInset = 0,
  double topPadding = 59,
  double bottomPadding = 34,
}) async {
  tester.view.devicePixelRatio = 1.0; // logical px == physical px
  tester.view.physicalSize = size;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboardInset);
  // While the keyboard is up iOS reports no bottom safe-area inset: the
  // keyboard already covers the home indicator.
  tester.view.padding = FakeViewPadding(
    top: topPadding,
    bottom: keyboardInset > 0 ? 0 : bottomPadding,
  );
  tester.view.viewPadding =
      FakeViewPadding(top: topPadding, bottom: bottomPadding);
  addTearDown(tester.view.reset);

  final provider = TravelProvider();
  await tester.pumpWidget(
    ChangeNotifierProvider<TravelProvider>.value(
      value: provider,
      child: const MaterialApp(home: ConversationalIntakeScreen()),
    ),
  );
  // Lay out, then drain the FadeSlideIn / PopIn entry timers so the test does
  // not fail teardown on a pending timer. Not pumpAndSettle: the mascot's float
  // animation repeats forever and would never settle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  return provider;
}

void main() {
  testWidgets('composer still sends while the opening greeting is in flight',
      (tester) async {
    final provider = await _pumpChat(tester);

    // Exactly the state a slow or hung greeting leaves behind: the automatic
    // request is outstanding, the user has typed nothing yet.
    provider.loading = true;
    provider.sending = false;
    provider.notifyListeners();
    await tester.pump();

    final field = find.byType(TextField);
    await tester.enterText(field, 'palaces for 2 days');
    await tester.pump();
    expect(find.text('palaces for 2 days'), findsOneWidget,
        reason: 'the field must accept text');

    // Pressing the return key must reach _send. Before the fix onSubmitted was
    // null whenever loading was true, so this did nothing at all.
    await tester.testTextInput.receiveAction(TextInputAction.send);
    // Drain the bubble's FadeSlideIn entry timer so the test ends clean.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(provider.messages.any((m) => m.isUser), isTrue,
        reason: 'the typed message must be submitted, not swallowed');
  });

  // Only the iPhone 17 width is asserted here. Under flutter_test the
  // GoogleFonts network fetch fails and text falls back to the test font, whose
  // metrics differ from the real ones — at 375pt that fallback reports a
  // vertical overflow that may or may not exist on a real SE. This width was
  // cross-checked against a screenshot from a booted simulator, so it is real.
  testWidgets('header does not overflow at iPhone 17 width', (tester) async {
    await _pumpChat(tester, size: _iPhone17);
    expect(tester.takeException(), isNull,
        reason: 'header Row overflows at ${_iPhone17.width}pt wide');
  });

  // The bug the user actually hit: tapping the field made "the whole bar come
  // down". Removing the tab bar and the home-indicator inset on
  // `viewInsets.bottom > 0` dropped 106px of chrome on the animation's first
  // frame, while Scaffold had shrunk the body by ~1px, so the input row lurched
  // DOWN out from under the finger. The tap never landed, focus was never
  // taken, the keyboard retracted and the row sprang back — untypable.
  testWidgets('input row never moves down while the keyboard opens',
      (tester) async {
    final provider = await _pumpChat(tester);
    provider.messages
        .add(const ChatMessage('Hi! I am SeoulFit Buddy', isUser: false));
    provider.notifyListeners();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    double? previousTop;
    // iOS animates viewInsets.bottom from 0 to ~336 over roughly 250ms.
    for (final inset in <double>[0, 1, 5, 20, 60, 120, 200, 280, 336]) {
      tester.view.viewInsets = FakeViewPadding(bottom: inset);
      tester.view.padding =
          FakeViewPadding(top: 59, bottom: inset > 0 ? 0 : 34);
      await tester.pump();

      final bar = tester.getRect(find.byType(TextField));
      expect(bar.bottom, lessThanOrEqualTo(_iPhone17.height - inset),
          reason: 'input row is under the keyboard at inset $inset');
      if (previousTop != null) {
        expect(bar.top, lessThanOrEqualTo(previousTop + 0.5),
            reason: 'input row moved DOWN at inset $inset '
                '($previousTop -> ${bar.top}); it must only rise');
      }
      previousTop = bar.top;
    }
  });

  testWidgets('input stays above the keyboard and is tappable', (tester) async {
    await _pumpChat(tester, keyboardInset: _keyboardTall);
    expect(tester.takeException(), isNull);

    final field = find.byType(TextField);
    final box = tester.getRect(field);
    // A field pushed below the visible body paints but refuses hit tests.
    expect(box.bottom, lessThanOrEqualTo(_iPhone17.height - _keyboardTall),
        reason: 'input row is under the keyboard, so it cannot be tapped');
    expect(box.top, greaterThanOrEqualTo(0));

    await tester.tap(field);
    await tester.pump();
  });

  testWidgets('input stays above the keyboard on SE-class devices',
      (tester) async {
    await _pumpChat(
      tester,
      size: _iPhoneSE,
      keyboardInset: _keyboardShort,
      topPadding: 20,
      bottomPadding: 0,
    );
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.byType(TextField)).bottom,
        lessThanOrEqualTo(_iPhoneSE.height - _keyboardShort));
  });
}
