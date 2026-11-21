# OoT Auto Tracker

A 100% progress tracker for the Ocarina of Time remake (Switch 2) that reads
your save file live. A small server on the Mac watches the save and serves the
progress; a native app for macOS and Android shows it, with a spoiler-free
mode and a map of Hyrule.

Unofficial fan project, not affiliated with or endorsed by Nintendo.

## Run it

```sh
# 1. Server (on the Mac that has the save)
cd server
dart compile exe bin/ootd.dart -o ootd
./ootd                      # finds the nxnative save by itself
./ootd --save-dir <folder>  # or: an emulator's data folder, a Switch backup, a folder of backups
./install-launchd.sh        # optional: start at login

# 2. App
cd app
flutter run -d macos
flutter build apk --release && flutter install   # Android phone on the same Wi-Fi
```

The app finds the server through Bonjour. If that fails, switch off "Find the
server automatically" in Settings and enter the Mac's address and port 7437.

`ootd --help` lists the options (`--slot`, `--port`, `--bind`, `--token`, …).
The server only ever reads save files.

## What is tracked

| | How |
|---|---|
| Items, equipment, upgrades, masks, bottles, songs, dungeon rewards | Read from the save, per entry |
| Gold Skulltulas (100), Heart Pieces (36) | Read from the save, per entry. `data/check_links.json` says which save flag is which entry; 13 of the 136 links rest on map position alone and are tagged as not certain in the app |
| Cuccos, Epona, Scarecrow's Song | Ticked by hand |

Spoiler-free mode (the default) shows only how many are missing per area and
category. Switch it off with the eye icon to see every entry with its location.

## Map

The map uses the game's own artwork: the world illustration with a badge per
area, and the area and dungeon-floor maps with a pin for every Gold Skulltula
and Heart Piece (only with spoilers shown) and your position at the last save.
The artwork is not part of this repository. It is extracted from your own copy
of the game into `data/local/maps/` (ignored by git) and served to the apps by
`ootd`:

```sh
pip install Pillow texture2ddecoder numpy zstandard
python3 tools/extract_maps.py
```

Without it the apps show a drawn diagram of the areas instead. On macOS the
app has its own desktop interface (sidebar, toolbar); Android uses Material.

## Layout

| Path | |
|---|---|
| `packages/oot_save` | Save parser (pure Dart), save-folder discovery, `ootsave` research CLI |
| `packages/oot_tracker` | Game data model, save → progress rules, API models |
| `server` | `ootd`: watcher, HTTP + WebSocket API, Bonjour, manual ticks, change journal |
| `app` | Flutter app (macOS, Android) |
| `data` | `areas.json`, `checks.json` (the checklist), `collectibles.json` (save flags and positions per collectible), `maps.json` (map calibration), `check_links.json` (which collectible is which checklist entry) |
| `tools` | Python scripts that derive `collectibles.json` from your own game files |
| `fixtures/save` | A real save used by the tests |

## API (v1)

| | |
|---|---|
| `GET /api/v1/state` | Full tracker state |
| `GET /api/v1/ws` | WebSocket: the state on connect and on every change |
| `GET /api/v1/screenshot` | Screenshot of the current slot (JPEG) |
| `PUT`/`DELETE /api/v1/manual/{checkId}` | Tick / untick a manual check |
| `POST /api/v1/anonymous/{area}/{category}?delta=±1` | Count a find without naming the entry |
| `GET /api/v1/maps`, `/api/v1/maps/{file}` | Map index and map images |
| `GET /api/v1/fields[?all]` | Raw save fields |
| `POST /api/v1/reload` | Re-read `data/` after editing it |

Manual ticks and a journal of every save-field change are kept in
`~/Library/Application Support/oot-tracker/`.

## Editing the checklist

`data/checks.json` entries have a `source` that says how the save answers them:
`{"stock": "<actor>"}`, `{"flag": "<field name>"}`, `{"hash": "0x…"}`,
`{"magic": 48}`, `{"bottle": n}`, or `null` for manual. Entries with
`"verified": false` were written from the original game and not checked
against the remake. After editing: `curl -X POST localhost:7437/api/v1/reload`.

## Tests

```sh
(cd packages/oot_save && dart test)
(cd packages/oot_tracker && dart test)
(cd app && flutter test)     # OOT_SHOTS=<dir> also writes a PNG of every screen
```

## Regenerating the collectible flags

Needs your own copy of the game as nxnative's `RomFS.img` and `pip install zstandard`.
See the usage comment at the top of each script in `tools/`, then run
`python3 tools/assign_areas.py --check`.

## Releases

GitHub Actions run the tests on every push and build the server and both apps
when a `v*` tag is pushed. Setup and usage: [RELEASING.md](RELEASING.md).

## Credits

Save format and field catalog: [OOT-SW2SE](https://github.com/Traiver/OOT-SW2SE) (MIT). See `NOTICE`.
