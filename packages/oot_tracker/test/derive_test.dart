import 'dart:convert';
import 'dart:io';

import 'package:oot_save/oot_save.dart';
import 'package:oot_tracker/oot_tracker.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final root = p.normalize(p.join(Directory.current.path, '..', '..'));

void main() {
  late GameData data;

  /// The same data without the collectible flags: everything manual.
  late GameData plain;
  late List<SaveSlot> slots;

  setUpAll(() {
    Object read(String name) => jsonDecode(File(p.join(root, 'data', name)).readAsStringSync());
    data = GameData.fromJson(
      read('areas.json') as List,
      read('checks.json') as List,
      read('collectibles.json') as List,
      read('check_links.json') as Map,
    );
    plain = GameData.fromJson(read('areas.json') as List, read('checks.json') as List);
    slots = SaveLocator.readSlots(p.join(root, 'fixtures', 'save'));
  });

  group('game data', () {
    test('is consistent', () {
      final areas = {for (final a in data.areas) a.id};
      expect(areas.length, data.areas.length);
      expect({for (final c in data.checks) c.id}.length, data.checks.length);
      for (final c in data.checks) {
        expect(areas, contains(c.area), reason: c.id);
        expect(categories, contains(c.category), reason: c.id);
      }
      List<int?> numbers(String category) =>
          [for (final c in data.checks) if (c.category == category) c.number]..sort();
      expect(numbers('skulltula'), [for (var i = 1; i <= 100; i++) i]);
      expect(numbers('heart_piece'), [for (var i = 1; i <= 36; i++) i]);
    });

    test('every save source can be read from a real save', () {
      final save = slots.first.progress;
      for (final c in data.checks) {
        if (c.source != null) expect(evaluateSource(save, c.source), isNotNull, reason: c.id);
      }
      for (final a in data.areas) {
        if (a.visitFlag != null) expect(save.booleanNamed(a.visitFlag!), isNotNull, reason: a.id);
      }
    });
  });

  test('a bottle without its own flag is the one the others do not explain', () {
    // The fixture owns four bottles: potion shop, Super Cucco, Cucco Lady and Ruto's Letter.
    final save = slots.first.progress;
    const others = [
      'Npc_Hylia_020_Shop_Item_Bottle_Present',
      'IsClear_Minigame_FindOutCucco',
      'MiniGame_CatchCucco_IsCompleted',
      'Get_StoneOfWater_GetRutoLetter',
    ];
    for (final flag in others) {
      expect(evaluateSource(save, {'flag': flag}), isTrue, reason: flag);
    }
    expect(evaluateSource(save, {'bottleBeyond': others}), isFalse);
    expect(evaluateSource(save, {'bottleBeyond': others.sublist(1)}), isTrue);
  });

  group('deriveState', () {
    test('reads the player and totals from the newest slot', () {
      final state = deriveState(data, newestSlot(slots));
      expect(state.save!.slot, 'slot_03');
      expect(state.save!.area, 'kokiri_forest');
      expect(state.save!.era, 'adult');
      expect(state.save!.hearts, 17);
      expect(state.save!.tokens, 82);
      expect(state.total.total, data.checks.length);
      expect(state.total.done, state.areas.fold(0, (sum, a) => sum + a.progress.done));
      expect(state.areas.fold(0, (sum, a) => sum + a.progress.total), data.checks.length);
      // Skulltulas and heart pieces are counted from the save in every area.
      expect(state.byCategory['skulltula']!.done, 82);
      expect(state.byCategory['heart_piece']!.done, 29);
      expect(state.mismatches, isEmpty);
      final forest = state.areas.firstWhere((a) => a.id == 'forest_temple');
      expect(forest.counted, contains('skulltula'));
      expect(forest.byCategory['skulltula']!.done, 5);
      // All five are collected, so each Forest Temple skulltula is known done.
      final inForest = state.checks.where((c) => c.def.area == 'forest_temple' && c.def.category == 'skulltula');
      expect(inForest.every((c) => c.done && c.auto), isTrue);
      final inSpirit = state.checks.where((c) => c.def.area == 'spirit_temple' && c.def.category == 'skulltula');
      expect(inSpirit.every((c) => !c.done && c.auto), isTrue);
      // Without the flags the tracker falls back to ticks and reports the gap.
      final manual = deriveState(plain, newestSlot(slots));
      expect(manual.mismatches.map((m) => (m.category, m.save, m.ticked)), contains(('skulltula', 82, 0)));
    });

    test('skulltula counts follow the three fixture saves', () {
      int tokens(String id) =>
          deriveState(data, slots.firstWhere((s) => s.id == id)).byCategory['skulltula']!.done;
      expect([tokens('slot_01'), tokens('slot_02'), tokens('slot_00')], [80, 81, 82]);
      for (final slot in slots) {
        expect(deriveState(data, slot).byCategory['skulltula']!.done, slot.progress.integerNamed('PouchData.Item_Token_Gold.StockNum'));
      }
    });

    test('manual ticks and anonymous finds count, within what is open', () {
      final data = plain;
      final slot = newestSlot(slots);
      final manual = data.checks.where((c) => c.category == 'skulltula' && c.area == 'kokiri_forest').toList();
      expect(manual.length, 3);
      var state = deriveState(data, slot, manualTicks: {manual.first.id}, anonymous: {'kokiri_forest/skulltula': 1});
      var area = state.areas.firstWhere((a) => a.id == 'kokiri_forest');
      expect(area.byCategory['skulltula']!.done, 2);
      expect(area.anonymous, {'skulltula': 1});
      expect(state.byCategory['skulltula']!.done, 2);
      expect(state.checks.firstWhere((c) => c.def.id == manual.first.id).auto, isFalse);

      // More anonymous finds than open checks are capped.
      state = deriveState(data, slot, manualTicks: {manual.first.id}, anonymous: {'kokiri_forest/skulltula': 9});
      area = state.areas.firstWhere((a) => a.id == 'kokiri_forest');
      expect(area.byCategory['skulltula']!.done, 3);
    });

    test('a mapped flag turns a manual check into a save-driven one', () {
      final id = data.checks.firstWhere((c) => c.category == 'skulltula').id;
      // 0x9B0DBE55 flips to true between the 80- and 82-token saves.
      final before = deriveState(plain, slots.firstWhere((s) => s.id == 'slot_01'), flagMap: {id: 0x9B0DBE55});
      final after = deriveState(plain, slots.firstWhere((s) => s.id == 'slot_03'), flagMap: {id: 0x9B0DBE55});
      expect(before.checks.firstWhere((c) => c.def.id == id).auto, isTrue);
      expect(before.checks.firstWhere((c) => c.def.id == id).done, isFalse);
      expect(after.checks.firstWhere((c) => c.def.id == id).done, isTrue);
    });

    test('without a save everything is manual and the state round-trips', () {
      final state = deriveState(data, null, error: 'No save found');
      expect(state.save, isNull);
      expect(state.checks.any((c) => c.auto), isFalse);
      final copy = TrackerState.fromJson(jsonDecode(jsonEncode(state.toJson())) as Json);
      expect(jsonEncode(copy.toJson()), jsonEncode(state.toJson()));
    });

    test('every located collectible is on a map of its own area', () {
      final index = MapIndex.fromJson(jsonDecode(File(p.join(root, 'data', 'maps.json')).readAsStringSync()) as Json);
      final state = deriveState(data, newestSlot(slots));
      expect(state.pins.length, 136);
      expect(state.pins.where((pin) => pin.done).length, 82 + 29);
      final lost = <String>[];
      for (final pin in state.pins) {
        final maps = index.ofArea(pin.area);
        final hits = maps.where((m) => index.pinsOn(m, [pin]).isNotEmpty);
        if (hits.isEmpty) lost.add('${pin.category} ${pin.area} ${pin.scenes}');
        for (final m in hits) {
          final placed = index.pinsOn(m, [pin]).single;
          expect(placed.x, inInclusiveRange(-40, m.width + 40), reason: '${pin.id} on ${m.id}');
          expect(placed.y, inInclusiveRange(-40, m.height + 40), reason: '${pin.id} on ${m.id}');
        }
      }
      // Two graveyard heart pieces are underground, which no map shows.
      expect(lost, hasLength(2));
      expect(lost.every((entry) => entry.startsWith('heart_piece graveyard')), isTrue);
      // The player of the newest fixture slot stands in Kokiri Forest.
      expect(index.ofPlayer(state.save!)!.id, 'KokiriForest');
    });

    test('every skulltula and heart piece entry is ticked from the save', () {
      final state = deriveState(data, newestSlot(slots));
      final entries = state.checks.where((c) => c.def.category == 'skulltula' || c.def.category == 'heart_piece');
      expect(entries.length, 136);
      expect(entries.every((c) => c.auto), isTrue);
      expect(entries.where((c) => c.def.category == 'skulltula' && c.done).length, 82);
      expect(entries.where((c) => c.def.category == 'heart_piece' && c.done).length, 29);
      expect(state.pins.every((p) => p.check != null), isTrue);
      // In every area the ticked entries equal what the save counts there.
      for (final area in state.areas) {
        for (final category in ['skulltula', 'heart_piece']) {
          final ticked = entries.where((c) => c.def.area == area.id && c.def.category == category && c.done).length;
          expect(area.byCategory[category]?.done ?? 0, ticked, reason: '${area.id} $category');
        }
      }
      // Each of the two Forest Temple skulltulas killed between the fixture
      // saves ticks exactly one Forest Temple entry.
      Set<String> done(String slot) => {
        for (final c in deriveState(data, slots.firstWhere((s) => s.id == slot)).checks)
          if (c.done && c.def.category == 'skulltula') c.def.id,
      };
      final first = done('slot_02').difference(done('slot_01'));
      final second = done('slot_00').difference(done('slot_02'));
      expect(first, hasLength(1));
      expect(second, hasLength(1));
      final areaOf = {for (final c in data.checks) c.id: c.area};
      expect({areaOf[first.single], areaOf[second.single]}, {'forest_temple'});
    });

    test('a link ticks exactly its entry from the save', () {
      // Link the three Kokiri Forest skulltula checks to the three located there.
      final ids = [for (final c in data.checks) if (c.area == 'kokiri_forest' && c.category == 'skulltula') c.id];
      final found = [for (final c in data.collectibles) if (c.area == 'kokiri_forest' && c.category == 'skulltula') c];
      final linked = GameData(
        areas: data.areas,
        checks: data.checks,
        collectibles: data.collectibles,
        links: {
          ids[0]: (found[0].instance, 'certain'),
          ids[1]: (found[1].instance, 'likely'),
          ids[2]: (found[2].instance, 'guess'),
        },
      );
      final slot = newestSlot(slots)!;
      final state = deriveState(linked, slot);
      for (var i = 0; i < 3; i++) {
        final check = state.checks.firstWhere((c) => c.def.id == ids[i]);
        expect(check.auto, isTrue);
        expect(check.done, slot.progress.hasKey64(found[i].key64!), reason: ids[i]);
        expect(check.uncertain, i != 0);
        expect(state.pins.firstWhere((p) => p.id == found[i].instance).check, ids[i]);
      }
      // Ticked entries and the save's count agree, so nothing is left unnamed.
      final area = state.areas.firstWhere((a) => a.id == 'kokiri_forest');
      expect(
        area.byCategory['skulltula']!.done,
        state.checks.where((c) => ids.contains(c.def.id) && c.done).length,
      );
    });

    test('scene names map to areas', () {
      expect(areaOfBanc('KokiriForest_Adult', data.areas), 'kokiri_forest');
      expect(areaOfBanc('SacredForestMeadow_Adult', data.areas), 'lost_woods');
      expect(areaOfBanc('ForestTemple', data.areas), 'forest_temple');
      expect(areaOfBanc('Nowhere', data.areas), isNull);
    });
  });
}
