import 'package:flutter/foundation.dart';

import '../models/travel_state.dart';
import '../services/api_service.dart';

/// One chat bubble in the conversational intake flow.
class ChatMessage {
  final String text;
  final bool isUser;
  const ChatMessage(this.text, {required this.isUser});
}

/// Single source of truth for the trip-planning flow, shared across the
/// conversational intake, slot-parsing, generation, critic-repair and final
/// map screens. Backed by [ApiService] which talks to the FastAPI backend.
class TravelProvider extends ChangeNotifier {
  ApiService _api = ApiService();

  final List<ChatMessage> messages = [];
  TravelState? state;
  bool loading = false;

  /// True only while a message the user typed is in flight. The composer gates
  /// on this, not on [loading]: [loading] is also true during the automatic
  /// greeting fired on screen entry, and gating the composer on that meant a
  /// slow or failed greeting left the send button and the return key dead
  /// while the field still accepted text — the chat looked like it refused to
  /// let you type.
  bool sending = false;
  String? error;

  /// Stops the user picked on the selection screen, in visit order. Consumed
  /// by the route-variation screen. Empty until the user selects.
  List<Poi> selectedStops = [];

  /// Transit legs recomputed by the backend for [selectedStops] (one per
  /// consecutive pair). Null while loading or on failure → screen falls back
  /// to the original itinerary legs / straight-line estimate.
  List<TransitLeg>? recomputedLegs;
  bool legsLoading = false;

  /// Whether the one-time "how to pay for Seoul transit" tip has been
  /// dismissed this session. Shown once on first entry to the route screen so
  /// first-time foreign visitors know how fares work.
  bool transitTipDismissed = false;

  void dismissTransitTip() {
    if (transitTipDismissed) return;
    transitTipDismissed = true;
    notifyListeners();
  }

  bool get hasItinerary => state?.itinerary != null;
  bool get confirmed => state?.confirmed ?? false;
  Itinerary? get itinerary => state?.itinerary;

  /// The backend thread id for this planning session, reused as the trip id so
  /// check-in records line up with the conversation that produced the plan.
  String get tripId => _api.threadId;

  /// All itinerary POIs flattened across days, in itinerary order.
  List<Poi> get allPois => [
        for (final d in (itinerary?.days ?? const [])) ...d.pois,
      ];

  void setSelectedStops(List<Poi> stops) {
    selectedStops = stops;
    recomputedLegs = null; // invalidate any previous result
    notifyListeners();
  }

  /// Ask the backend for fresh ODsay transit legs for the current selection.
  Future<void> recomputeTransit() async {
    if (selectedStops.length < 2) {
      recomputedLegs = const [];
      notifyListeners();
      return;
    }
    legsLoading = true;
    notifyListeners();
    try {
      recomputedLegs = await _api.fetchTransitLegs(selectedStops);
    } catch (_) {
      recomputedLegs = null; // leave null → screen uses fallback
    } finally {
      legsLoading = false;
      notifyListeners();
    }
  }

  /// Thin passthroughs so screens never need direct [ApiService] access —
  /// every call must share this session's [_api] instance (and therefore its
  /// [threadId]) or the backend has no persisted itinerary to look up.
  Future<List<Map<String, dynamic>>> fetchSwapCandidates({
    required int day,
    required int slotIndex,
    required String currentPoi,
    required String dayArea,
    String? currentPoiType,
    List<String> excludedIds = const [],
  }) =>
      _api.fetchSwapCandidates(
        day: day,
        slotIndex: slotIndex,
        currentPoi: currentPoi,
        dayArea: dayArea,
        currentPoiType: currentPoiType,
        excludedIds: excludedIds,
      );

  Future<Map<String, dynamic>> revalidate({
    List<String> excludedIds = const [],
    Map<String, String> swappedSlots = const {},
    Map<String, List<String>> dayOrder = const {},
    Map<String, int> dayStartShift = const {},
  }) =>
      _api.revalidate(
        excludedIds: excludedIds,
        swappedSlots: swappedSlots,
        dayOrder: dayOrder,
        dayStartShift: dayStartShift,
      );

  /// The real transit leg the backend computed between two POIs that were
  /// adjacent in the original itinerary, or null if they weren't adjacent.
  TransitLeg? legBetween(Poi a, Poi b) {
    for (final day in itinerary?.days ?? const <ItineraryDay>[]) {
      for (var i = 0; i < day.pois.length - 1; i++) {
        if (_samePoi(day.pois[i], a) &&
            _samePoi(day.pois[i + 1], b) &&
            i < day.transitLegs.length) {
          return day.transitLegs[i];
        }
      }
    }
    return null;
  }

  static bool _samePoi(Poi a, Poi b) =>
      a.name == b.name && a.lat == b.lat && a.lng == b.lng;

  /// Fires the backend greeting once, on first entry to the chat screen.
  Future<void> startGreeting() async {
    if (messages.isNotEmpty || loading) return;
    await _send(null);
  }

  /// Sends a user message, appends it optimistically, then the AI reply.
  /// [timeout] overrides the default conversational budget. The itinerary
  /// generation turn passes ApiService.generationTimeout.
  Future<void> sendMessage(String text, {Duration? timeout}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    messages.add(ChatMessage(trimmed, isUser: true));
    sending = true;
    notifyListeners();
    try {
      await _send(trimmed, timeout: timeout);
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  Future<void> _send(String? text, {Duration? timeout}) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final s = await _api.chat(text, timeout: timeout);
      state = s;
      final reply = s.reply;
      if (reply != null && reply.isNotEmpty) {
        messages.add(ChatMessage(reply, isUser: false));
      }
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Clears everything and starts a brand-new backend thread.
  Future<void> reset() async {
    try {
      await _api.reset();
    } catch (_) {
      // Ignore — we're discarding this thread anyway.
    }
    _api = ApiService();
    messages.clear();
    state = null;
    error = null;
    loading = false;
    sending = false;
    notifyListeners();
  }
}
