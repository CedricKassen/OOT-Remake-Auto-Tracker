// Research tool: inspect and compare save slots.
//
//   dart run oot_save:ootsave slots  [saveDir]
//   dart run oot_save:ootsave dump   <progress.sav> [--all]
//   dart run oot_save:ootsave diff   <a.sav> <b.sav>
//   dart run oot_save:ootsave guess  <progress.sav> <name>...   (does a name exist in the save?)
import 'dart:io';

import 'package:oot_save/oot_save.dart';

String label(int hash) =>
    fieldNames[hash] ?? fieldLabels[hash] ?? '0x${hash.toRadixString(16).padLeft(8, '0').toUpperCase()}';

String show(Object? v) {
  if (v is List && v.length > 12) return '[${v.take(12).join(', ')}, … ${v.length} items]';
  if (v is double) return v.toStringAsFixed(3);
  return '$v';
}

SaveFile load(String path) => SaveFile.parse(File(path).readAsBytesSync());

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: ootsave slots|dump|diff|guess …');
    exit(64);
  }
  switch (args.first) {
    case 'slots':
      final dir = args.length > 1 ? SaveLocator.resolve(args[1]) : SaveLocator.findDefault();
      if (dir == null) {
        stderr.writeln('No save found.');
        exit(1);
      }
      print(dir);
      final slots = SaveLocator.readSlots(dir);
      final newest = newestSlot(slots);
      for (final s in slots) {
        final g = s.progress;
        print(
          '${s.id}  ${s.time}  ${s.isAutosave ? 'auto  ' : 'manual'}  '
          '${g.stringNamed('Sequence_CurrentBanc')}  '
          'hearts ${(g.integerNamed('PlayerStatus.MaxLife') ?? 0) ~/ 4}  '
          'rupees ${g.integerNamed('PlayerStatus.CurrentRupee')}  '
          'tokens ${g.integerNamed('PouchData.Item_Token_Gold.StockNum')}'
          '${identical(s, newest) ? '  <- newest' : ''}',
        );
      }
    case 'dump':
      final save = load(args[1]);
      final all = args.contains('--all');
      for (final f in save.fields.values) {
        final named = fieldNames.containsKey(f.hash) || fieldLabels.containsKey(f.hash);
        if (!all && !named) continue;
        final v = save.value(f.hash);
        if (!all && (v == false || v == 0 || v == '')) continue;
        print('${f.type.name.padRight(12)} ${label(f.hash)} = ${show(v)}');
      }
    case 'diff':
      final a = load(args[1]), b = load(args[2]);
      for (final f in a.fields.values) {
        final va = show(a.value(f.hash)), vb = show(b.value(f.hash));
        if (f.type == FieldType.binary || f.type == FieldType.unknown) continue;
        if (va != vb) print('${f.type.name.padRight(12)} ${label(f.hash)}: $va -> $vb');
      }
    case 'guess':
      final save = load(args[1]);
      for (final name in args.skip(2)) {
        final hash = murmur3(name);
        final f = save.fields[hash];
        print(
          f == null
              ? 'no   $name'
              : 'YES  $name  0x${hash.toRadixString(16).toUpperCase()}  ${f.type.name} = ${show(save.value(hash))}'
                    '${fieldNames.containsKey(hash) ? '' : '  (new name)'}',
        );
      }
    default:
      stderr.writeln('unknown command ${args.first}');
      exit(64);
  }
}
