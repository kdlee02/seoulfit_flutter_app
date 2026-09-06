// formatDateRange output is a wire contract, not a display string: the backend
// matches it with graph._PICKED_DATES_RE and rejects anything else as
// hand-typed. Dropping a year, using a dash instead of "to", or abbreviating
// the month all break the dates question outright, so pin the exact shape.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seoulfit_flutter/screens/conversational_intake_screen.dart';

void main() {
  test('multi-day range repeats the year on both ends', () {
    final out = formatDateRange(DateTimeRange(
      start: DateTime(2026, 6, 15),
      end: DateTime(2026, 6, 17),
    ));
    expect(out, 'June 15, 2026 to June 17, 2026');
  });

  test('a range crossing New Year keeps each end on its own year', () {
    final out = formatDateRange(DateTimeRange(
      start: DateTime(2026, 12, 30),
      end: DateTime(2027, 1, 2),
    ));
    expect(out, 'December 30, 2026 to January 2, 2027');
  });

  test('single day collapses to one date, not a to-itself range', () {
    final out = formatDateRange(DateTimeRange(
      start: DateTime(2027, 1, 5),
      end: DateTime(2027, 1, 5),
    ));
    expect(out, 'January 5, 2027');
  });

  test('question order matches the backend FIELD_ORDER, dates first', () {
    expect(kFieldOrder.first, 'travel_dates');
    expect(kFieldOrder.length, 6);
    // Dates are picker-only, so that question deliberately has no typed
    // shortcuts — a "3 days" chip would just hit the backend's bounce.
    expect(kFieldPrompts['travel_dates'], isNull);
    for (final f in kFieldOrder.skip(1)) {
      expect(kFieldPrompts[f], isNotNull, reason: 'no quick replies for $f');
      expect(kFieldPrompts[f], isNotEmpty);
    }
  });
}
