import 'dart:typed_data';

import 'save_file.dart';

/// The time the game wrote into a slot's `caption.sav`: the local wall-clock
/// time of the console or port at the moment of saving, without a time zone.
class SaveTime implements Comparable<SaveTime> {
  const SaveTime(this.year, this.month, this.day, this.hour, this.minute, this.second);
  final int year, month, day, hour, minute, second;

  static const _year = 0x9811A3F7;
  static const _month = 0xDFD840D3;
  static const _day = 0xBD46F485;
  static const _hour = 0x23F3D75E;
  static const _minute = 0x27853BF7;
  static const _second = 0x5EE50BED;

  /// The save time of a parsed `caption.sav`, or null if it has none or any
  /// part is out of range. A caption without the seconds field reads as :00.
  static SaveTime? read(SaveFile caption) {
    final y = caption.integer(_year), mo = caption.integer(_month), d = caption.integer(_day);
    final h = caption.integer(_hour), mi = caption.integer(_minute);
    final s = caption.has(_second) ? caption.integer(_second) : 0;
    if (y == null || mo == null || d == null || h == null || mi == null || s == null) return null;
    bool within(int v, int lo, int hi) => v >= lo && v <= hi;
    if (!within(y, 1980, 2107) || !within(mo, 1, 12) || !within(d, 1, 31)) return null;
    if (!within(h, 0, 23) || !within(mi, 0, 59) || !within(s, 0, 59)) return null;
    return SaveTime(y, mo, d, h, mi, s);
  }

  int get _order => DateTime.utc(year, month, day, hour, minute, second).millisecondsSinceEpoch;

  @override
  int compareTo(SaveTime other) => _order.compareTo(other._order);

  String _2(int v) => v.toString().padLeft(2, '0');

  /// ISO 8601 local time without a zone, e.g. `2026-11-21T14:14:38`.
  @override
  String toString() => '$year-${_2(month)}-${_2(day)}T${_2(hour)}:${_2(minute)}:${_2(second)}';
}

/// One save slot: its parsed `progress.sav` and `caption.sav`.
class SaveSlot {
  SaveSlot({required this.id, required this.progress, required this.caption})
    : time = SaveTime.read(caption);

  /// Folder name, e.g. `slot_03`.
  final String id;
  final SaveFile progress;
  final SaveFile caption;
  final SaveTime? time;

  static const _autosave = 0x25F03CAA;
  static const _screenshot = 0x63696A32;

  bool get isAutosave =>
      caption.boolean(_autosave) ?? ((caption.integer(_autosave) ?? 0) != 0);

  /// The JPEG screenshot stored in the caption, if any.
  Uint8List? get screenshot {
    final image = caption.binary(_screenshot);
    return image != null && image.length > 2 && image[0] == 0xFF && image[1] == 0xD8
        ? image
        : null;
  }
}

/// The slot the game would continue from: the most recently saved one.
/// Slots without a valid save time rank last; ties go to the earlier slot.
SaveSlot? newestSlot(List<SaveSlot> slots) {
  SaveSlot? best;
  for (final slot in slots) {
    if (best == null) {
      best = slot;
    } else if (slot.time != null && (best.time == null || slot.time!.compareTo(best.time!) > 0)) {
      best = slot;
    }
  }
  return best;
}
