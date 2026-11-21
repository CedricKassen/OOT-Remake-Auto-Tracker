// Copies the checklist data from the repository's `data` folder into
// `assets/data`, from where it is bundled with the app. Run it from `host`
// before building or running:
//
//   dart run tool/sync_data.dart
import 'dart:io';

const files = ['areas.json', 'checks.json', 'collectibles.json', 'check_links.json', 'maps.json'];

void main() {
  final target = Directory('assets/data')..createSync(recursive: true);
  for (final name in files) {
    final source = File('../data/$name');
    if (!source.existsSync()) {
      stderr.writeln('Missing ${source.path}. Run this from the host folder of the repository.');
      exit(66);
    }
    source.copySync('${target.path}/$name');
  }
  stdout.writeln('Copied ${files.length} files to ${target.path}');
}
