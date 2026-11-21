import 'package:oot_tracker/oot_tracker.dart';

/// What the checklist of one category in one area shows, worked out the same
/// way for every interface.
class CheckSection {
  CheckSection({
    required AreaState area,
    required String category,
    required Progress progress,
    required List<CheckState> checks,
    required bool spoilerFree,
    required bool missingOnly,
    String era = 'any',
  }) : anonymous = area.anonymous[category] ?? 0,
       counted = area.counted.contains(category),
       manualOpen = checks.where((c) => !c.auto && !c.done).length,
       hasManual = checks.any((c) => !c.auto) {
    unidentified = counted ? progress.done - checks.where((c) => c.done).length : anonymous;
    // Missing first, then by number or title.
    final sorted = [...checks]
      ..sort((a, b) {
        if (a.done != b.done) return a.done ? 1 : -1;
        final byNumber = (a.def.number ?? 0).compareTo(b.def.number ?? 0);
        return byNumber != 0 ? byNumber : a.def.title.compareTo(b.def.title);
      });
    visible = [
      for (final c in sorted)
        if (spoilerFree
            ? c.done
            : (!missingOnly || !c.done) && (era == 'any' || c.def.era.isEmpty || c.def.era.contains(era)))
          c,
    ];
  }

  /// Finds counted without saying which entry they are.
  final int anonymous;

  /// The save counts this category here but cannot say which checks they are.
  final bool counted;

  /// Entries the user ticks by hand that are not ticked yet.
  final int manualOpen;
  final bool hasManual;

  /// Finds that no entry is ticked for.
  late final int unidentified;

  /// The entries to list. In spoiler-free mode only the collected ones.
  late final List<CheckState> visible;

  /// Explains [unidentified] finds, when there are any to explain.
  String? get unidentifiedNote => unidentified <= 0
      ? null
      : counted
      ? 'Your save has $unidentified more of these than are ticked. '
            'It does not say which, so tick the ones you have.'
      : '$unidentified found without saying which. Tick the ones you have.';
}

/// When and with what a check can be collected, as short labels.
List<String> checkTags(CheckDef def) => [
  if (def.era.length == 1) def.era.first == 'child' ? 'Child' : 'Adult',
  if (def.night) 'Night',
  ...def.requires,
];
