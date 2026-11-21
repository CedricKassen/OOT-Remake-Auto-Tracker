import 'dart:io';

import 'package:oot_save/oot_save.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The real six-slot save in `fixtures/save` at the repository root.
final fixture = p.normalize(p.join(Directory.current.path, '..', '..', 'fixtures', 'save'));

void main() {
  group('murmur3', () {
    test('matches known field hashes', () {
      expect(murmur3('PlayerStatus.CurrentRupee'), 0xA77921D7);
      expect(murmur3('PlayerStatus.MaxLife'), 0xFBE01DA1);
      expect(murmur3('IsGet.Item_Melody_ZeldaLullaby'), 0x01C20002);
      expect(murmur3('English'), 0x82591FA9);
      expect(murmur3(''), 0);
    });

    test('every catalog name hashes to its key', () {
      fieldNames.forEach((hash, name) => expect(murmur3(name), hash, reason: name));
    });
  });

  group('fixture save', () {
    late List<SaveSlot> slots;
    setUpAll(() => slots = SaveLocator.readSlots(fixture));

    test('has six slots with the full field table', () {
      expect(slots.map((s) => s.id), ['slot_00', 'slot_01', 'slot_02', 'slot_03', 'slot_04', 'slot_05']);
      for (final slot in slots) {
        expect(slot.progress.headerEnd, 0x175D8);
        expect(slot.progress.fields.length, 11926);
        expect(slot.caption.fields.length, 47);
      }
    });

    test('section types agree with the catalog', () {
      final save = slots.first.progress;
      expect(save.fields[murmur3('PlayerStatus.CurrentRupee')]!.type, FieldType.int_);
      expect(save.fields[murmur3('Sequence_CurrentBanc')]!.type, FieldType.string64);
      expect(save.fields[murmur3('PlayerStatus.SavePos')]!.type, FieldType.vector3);
      expect(save.fields[murmur3('Sequence_IsChildhood')]!.type, FieldType.bool_);
      expect(fieldNames.keys.every(save.has), isTrue);
    });

    test('reads plausible values of every kind', () {
      for (final slot in slots) {
        final save = slot.progress;
        expect(save.integerNamed('PlayerStatus.CurrentRupee'), inInclusiveRange(0, 999));
        final maxLife = save.integerNamed('PlayerStatus.MaxLife')!;
        expect(maxLife % 4, 0);
        expect(maxLife ~/ 4, inInclusiveRange(3, 20));
        expect(save.integerNamed('PouchData.Item_Token_Gold.StockNum'), inInclusiveRange(0, 100));
        expect(save.stringNamed('Sequence_CurrentBanc'), isNotEmpty);
        expect(save.vector3(murmur3('PlayerStatus.SavePos')), hasLength(3));
        expect(save.booleanNamed('Sequence_IsChildhood'), isNotNull);
        expect(save.array(0x0744746A), hasLength(936));
        // Every field decodes without running outside the file.
        for (final hash in save.fields.keys) {
          save.value(hash);
        }
      }
    });

    test('reads save time and screenshot from the caption', () {
      for (final slot in slots) {
        expect(slot.time, isNotNull);
        expect(slot.time!.year, 2026);
        expect(slot.screenshot, isNotNull);
      }
    });

    test('newest slot is the latest save time', () {
      final newest = newestSlot(slots)!;
      for (final slot in slots) {
        expect(newest.time!.compareTo(slot.time!), greaterThanOrEqualTo(0));
      }
    });
  });

  group('SaveLocator.resolve', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('oot_save_test'));
    tearDown(() => tmp.deleteSync(recursive: true));

    void slot(String dir) {
      Directory(dir).createSync(recursive: true);
      File(p.join(dir, 'progress.sav')).writeAsBytesSync([4, 3, 2, 1]);
      File(p.join(dir, 'caption.sav')).writeAsBytesSync([4, 3, 2, 1]);
    }

    String real(String path) => Directory(path).resolveSymbolicLinksSync();
    String? resolve(String path) {
      final found = SaveLocator.resolve(path);
      return found == null ? null : real(found);
    }

    test('save folder, slot folder and Switch backup', () {
      slot(p.join(tmp.path, 'a', 'slot_00'));
      slot(p.join(tmp.path, 'b', 'files', 'slot_02'));
      expect(resolve(p.join(tmp.path, 'a')), real(p.join(tmp.path, 'a')));
      expect(resolve(p.join(tmp.path, 'a', 'slot_00')), real(p.join(tmp.path, 'a')));
      expect(resolve(p.join(tmp.path, 'b')), real(p.join(tmp.path, 'b', 'files')));
      expect(resolve(p.join(tmp.path, 'missing')), isNull);
    });

    test('port and emulator layouts, from any folder on the way', () {
      final port = p.join(tmp.path, 'Longshot', 'save', portUserId);
      final other = p.join(tmp.path, 'Longshot', 'save', 'aaaa');
      slot(p.join(port, 'slot_00'));
      slot(p.join(other, 'slot_00'));
      expect(resolve(p.join(tmp.path, 'Longshot')), real(port));
      expect(resolve(p.join(tmp.path, 'Longshot', 'save')), real(port));

      final emu = p.join(tmp.path, 'eden', 'nand', 'user', 'save', '0000000000000000', 'prof', titleId);
      slot(p.join(emu, 'slot_01'));
      expect(resolve(p.join(tmp.path, 'eden')), real(emu));
      expect(resolve(p.join(tmp.path, 'eden', 'nand', 'user', 'save')), real(emu));
    });

    test('folder of backups uses the newest one', () {
      slot(p.join(tmp.path, 'old', 'files', 'slot_00'));
      slot(p.join(tmp.path, 'new', 'files', 'slot_00'));
      File(p.join(tmp.path, 'old', 'files', 'slot_00', 'progress.sav'))
          .setLastModifiedSync(DateTime(2020));
      expect(resolve(tmp.path), real(p.join(tmp.path, 'new', 'files')));
    });
  });
}
