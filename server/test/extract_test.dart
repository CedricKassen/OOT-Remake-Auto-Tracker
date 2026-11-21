// The zstd decoder against data compressed by the reference implementation,
// and, where the game is available, the whole map extraction.
//
//   OOT_GAME_FILES=<RomFS.img or folder> dart test     also extracts every
//   map from the real game and checks the pictures' sizes.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:ootd/extract/maps.dart';
import 'package:ootd/extract/zstd.dart';
import 'package:test/test.dart';

// name -> (zstd frame, SHA-256 of the content, length of the content)
const _samples = {
  'compressed': (
    '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'
        '/QM8+rDXjT+ZJPoRvoJjEKC/JMW/yIYv/QE=',
    'e998e7f95bb11b246eb565106345d6ce1af3db036f17f81cce9785190648d8a4',
    30976,
  ),
  'fast': (
    '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'
        'CHP/ItwH8Ac=',
    'e998e7f95bb11b246eb565106345d6ce1af3db036f17f81cce9785190648d8a4',
    30976,
  ),
  'incompressible': (
    'KLUv/WAsAGEJAP4aZezNn/TBnvCjsJ+0NiP35NUGdGpqubk/EezdDEPbL16UtjNxHXC73VDCJ9Vnp5qoX/sFScFUXQg5uRscagtu'
        '7E9tSU7gD9lFhI13127vGy8CrlR5gnZZdllnOOxui9ka+gDiLCPUSKPrV26s0X1ldFLRtt+bnlJv5CtIYqE/l17V9eH48o3xZfFK'
        'VncltMQjzjO12au0yE3uAxX0tc3dmFACSrvMp3CuUM5dkjtFDaX14f2MugqzpvQ7qoLGhQi9xiK5Bo2qk/1SwQsmYmseR0ufdHAd'
        '34c+NkktTN5iFP7F2C9bQJoTKxxSPxMLp1Y57VI2XGW3Zbg93qbI0YHkd/cMWVRcTbMe5BHhB+fgC6zKSxhI/lnEUAICudRgwtGq'
        '9VKhwGGJbAKnog==',
    '0b57a90f7303057d3ffb8ef97efee5f346bd7a2b18312a492b1b8ecd46bc4fa2',
    300,
  ),
  'rle': (
    'KLUv/WCIEk0AABBhYQEAg9MDLA==',
    'c526c6222044dab5674de9c4ac7f4566ebb5e4d8bf9d8ea34c9cc8a7cc3c869c',
    5000,
  ),
};

void main() {
  group('zstd', () {
    _samples.forEach((name, sample) {
      test('decompresses $name data', () {
        final out = zstdDecompress(base64.decode(sample.$1));
        expect(out.length, sample.$3);
        expect(sha256.convert(out).toString(), sample.$2);
      });
    });

    test('rejects damaged and foreign data', () {
      final good = base64.decode(_samples['compressed']!.$1);
      expect(
        () => zstdDecompress(Uint8List.fromList([1, 2, 3, 4, 5, 6])),
        throwsA(isA<ZstdException>()),
      );
      expect(
        () => zstdDecompress(Uint8List.sublistView(good, 0, good.length ~/ 2)),
        throwsA(isA<ZstdException>()),
      );
    });
  });

  group('game files', () {
    test('a folder without the game is refused with a readable message', () {
      final dir = Directory.systemTemp.createTempSync('oot-extract-test');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/RomFS.img').writeAsStringSync('not an image');
      expect(
        () => extractMaps(
          source: dir.path,
          dataDir: '../data',
          outDir: '${dir.path}/out',
        ),
        throwsA(
          isA<ExtractException>().having(
            (e) => e.message,
            'message',
            contains('No game files'),
          ),
        ),
      );
      expect(
        () => extractMaps(
          source: '${dir.path}/RomFS.img',
          dataDir: '../data',
          outDir: '${dir.path}/out',
        ),
        throwsA(isA<ExtractException>()),
      );
    });

    final game = Platform.environment['OOT_GAME_FILES'];
    test(
      'extracts every map from the real game',
      skip: game == null ? 'set OOT_GAME_FILES to run' : null,
      () {
        final out = Directory.systemTemp.createTempSync('oot-extract-test');
        addTearDown(() => out.deleteSync(recursive: true));
        final result = extractMaps(
          source: game!,
          dataDir: '../data',
          outDir: out.path,
        );
        final maps =
            (jsonDecode(File('../data/maps.json').readAsStringSync())
                    as Map)['maps']
                as List;
        expect(result.written, maps.length);
        expect(result.missing, isEmpty);
        expect(result.resized, isEmpty);
        for (final map in maps.cast<Map>()) {
          final picture = img.decodePng(
            File('${out.path}/${map['file']}').readAsBytesSync(),
          )!;
          expect(
            (picture.width, picture.height),
            (map['width'], map['height']),
            reason: '${map['id']}',
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });
}
