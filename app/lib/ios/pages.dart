import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:oot_tracker/oot_tracker.dart';

import '../checks.dart';
import '../client.dart';
import '../widgets.dart';
import 'style.dart';

// The route's title names the back button of a page opened from it.
void openIosArea(BuildContext context, String areaId) => Navigator.of(context).push(
  CupertinoPageRoute<void>(
    title: ClientScope.of(context).state?.areas.where((a) => a.id == areaId).firstOrNull?.name,
    builder: (_) => IosAreaPage(areaId: areaId),
  ),
);

void openIosCategory(BuildContext context, String category) => Navigator.of(context).push(
  CupertinoPageRoute<void>(
    title: categoryName(category),
    builder: (_) => IosCategoryPage(category: category),
  ),
);

/// Shown instead of content while there is no state at all.
class IosEmptyState extends StatelessWidget {
  const IosEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final client = ClientScope.of(context);
    final style = IosStyle.of(context);
    final (icon, title, detail) = switch (client.status) {
      LinkStatus.searching => (
        CupertinoIcons.wifi,
        'Looking for the tracker server…',
        'Start the server on your computer. Both devices need to be on the same Wi-Fi.',
      ),
      LinkStatus.connecting => (CupertinoIcons.arrow_2_circlepath, 'Connecting…', client.targetLabel),
      _ => (CupertinoIcons.wifi_slash, 'Not connected', client.lastError ?? 'Set the server address in Settings.'),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: style.tertiary),
            const SizedBox(height: 16),
            Text(title, style: style.headline, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(detail, style: style.subhead, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// The connection to the server as a coloured dot and a word, below the
/// title in the bar.
class _Status extends StatelessWidget {
  const _Status();

  @override
  Widget build(BuildContext context) {
    final client = ClientScope.of(context);
    final (color, text) = switch (client.status) {
      LinkStatus.live => (CupertinoColors.systemGreen, 'Live'),
      LinkStatus.connecting => (CupertinoColors.systemOrange, 'Connecting'),
      LinkStatus.searching => (CupertinoColors.systemOrange, 'Searching'),
      LinkStatus.offline => (CupertinoColors.systemRed, 'Offline'),
    };
    final style = IosStyle.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color.resolveFrom(context), shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(text, style: style.footnote.copyWith(fontSize: 11)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Overview

class IosOverviewPage extends StatelessWidget {
  const IosOverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final client = ClientScope.of(context);
    final style = IosStyle.of(context);
    final state = client.state;
    if (state == null) {
      return const IosPage(title: 'Overview', subtitle: _Status(), filling: IosEmptyState());
    }
    final save = state.save;
    final area = state.areas.where((a) => a.id == save?.area).firstOrNull;

    return IosPage(
      title: 'Overview',
      subtitle: const _Status(),
      children: [
        IosCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (save != null && client.screenshot != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: Image.memory(client.screenshot!, fit: BoxFit.cover, gaplessPlayback: true),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: save == null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('No save loaded', style: style.headline),
                          const SizedBox(height: 2),
                          Text(state.error ?? 'The server has not found a save yet.', style: style.subhead),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(area?.name ?? save.banc, style: style.title),
                          const SizedBox(height: 2),
                          Text(
                            '${save.slot.replaceFirst('slot_0', 'Slot ')} · '
                            '${save.autosave ? 'autosave' : 'manual save'} · '
                            '${save.savedAt?.replaceFirst('T', ' at ') ?? 'unknown time'}',
                            style: style.footnote,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 16,
                            runSpacing: 6,
                            children: [
                              _Stat(CupertinoIcons.heart_fill, const Color(0xFFE5645E), '${save.hearts} hearts'),
                              _Stat(Glyph.rupee, const Color(0xFF5FBF77), '${save.rupees}'),
                              _Stat(Glyph.skull, gold, '${save.tokens} tokens'),
                              _Stat(
                                CupertinoIcons.person_fill,
                                style.secondary,
                                save.era == 'adult' ? 'Adult' : 'Child',
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
        IosCard(
          child: Row(
            children: [
              ProgressRing(
                progress: state.total,
                size: 96,
                stroke: 9,
                track: style.fill,
                child: Text(percent(state.total), style: style.title),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${state.total.done} of ${state.total.total}', style: style.title),
                    Text('${state.total.missing} still missing', style: style.subhead),
                  ],
                ),
              ),
            ],
          ),
        ),
        for (final m in state.mismatches)
          IosCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  CupertinoIcons.exclamationmark_triangle_fill,
                  size: 20,
                  color: IosStyle.orange.resolveFrom(context),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your save has ${m.estimate ? 'about ' : ''}${m.save} ${categoryName(m.category)}, '
                    'the tracker has ${m.ticked} marked. Mark them in their areas.',
                    style: style.subhead.copyWith(color: style.label),
                  ),
                ),
              ],
            ),
          ),
        CupertinoListSection.insetGrouped(
          header: const IosSectionHeader('Categories'),
          children: [
            for (final e in state.byCategory.entries)
              CupertinoListTile(
                padding: iosTilePadding,
                leading: AppIcon(CategoryStyle.of(e.key).icon, size: 22, color: CategoryStyle.of(e.key).color),
                title: _ProgressLine(
                  color: CategoryStyle.of(e.key).color,
                  label: categoryName(e.key),
                  progress: e.value,
                ),
                trailing: const CupertinoListTileChevron(),
                onTap: () => openIosCategory(context, e.key),
              ),
          ],
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.color, this.label);
  final Object icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      AppIcon(icon, size: 17, color: color),
      const SizedBox(width: 6),
      Text(label, style: IosStyle.of(context).subhead.copyWith(color: IosStyle.of(context).label)),
    ],
  );
}

/// Name and `done/total` above a progress bar.
class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.color, required this.label, required this.progress});
  final Color color;
  final String label;
  final Progress progress;

  @override
  Widget build(BuildContext context) {
    final style = IosStyle.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: style.body)),
            Text('${progress.done}/${progress.total}', style: style.number),
          ],
        ),
        const SizedBox(height: 7),
        CupertinoLinearActivityIndicator(progress: progress.fraction.clamp(0.0, 1.0), color: color),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Areas

class IosAreasPage extends StatefulWidget {
  const IosAreasPage({super.key});

  @override
  State<IosAreasPage> createState() => _IosAreasPageState();
}

class _IosAreasPageState extends State<IosAreasPage> {
  bool _openOnly = false;

  @override
  Widget build(BuildContext context) {
    final state = ClientScope.of(context).state;
    if (state == null) return const IosPage(title: 'Areas', filling: IosEmptyState());
    final style = IosStyle.of(context);
    final all = state.areas.where((a) => a.progress.total > 0).toList();
    final complete = all.where((a) => a.progress.missing == 0).length;
    final shown = [
      for (final a in all)
        if (!(_openOnly && a.progress.missing == 0)) a,
    ];
    final here = state.save?.area;

    Widget section(String title, List<AreaState> areas) => CupertinoListSection.insetGrouped(
      header: IosSectionHeader(title),
      additionalDividerMargin: 42 + 14,
      children: [
        for (final a in areas)
          CupertinoListTile(
            padding: iosTilePadding,
            leadingSize: 42,
            leading: _AreaRing(area: a),
            title: IosTileBody(
              child: _AreaLine(area: a, here: a.id == here),
            ),
            trailing: const CupertinoListTileChevron(),
            onTap: () => openIosArea(context, a.id),
          ),
      ],
    );
    final overworld = shown.where((a) => a.kind != 'dungeon').toList();
    final dungeons = shown.where((a) => a.kind == 'dungeon').toList();

    return IosPage(
      title: 'Areas',
      children: [
        IosSegments<bool>(
          value: _openOnly,
          options: const {false: 'All', true: 'Something left'},
          onChanged: (v) => setState(() => _openOnly = v),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Text('$complete of ${all.length} areas complete', style: style.footnote),
        ),
        if (overworld.isNotEmpty) section('Hyrule', overworld),
        if (dungeons.isNotEmpty) section('Dungeons', dungeons),
      ],
    );
  }
}

/// How much of an area is done, with the number still missing in the middle.
class _AreaRing extends StatelessWidget {
  const _AreaRing({required this.area});
  final AreaState area;

  @override
  Widget build(BuildContext context) {
    final style = IosStyle.of(context);
    final missing = area.progress.missing;
    return ProgressRing(
      progress: area.progress,
      size: 42,
      stroke: 4,
      track: style.fill,
      child: missing == 0
          ? const Icon(CupertinoIcons.checkmark_alt, color: gold, size: 20)
          : Text('$missing', style: style.headline.copyWith(fontSize: 15)),
    );
  }
}

/// Name of an area above its counts per category.
class _AreaLine extends StatelessWidget {
  const _AreaLine({required this.area, required this.here});
  final AreaState area;
  final bool here;

  @override
  Widget build(BuildContext context) {
    final style = IosStyle.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(area.name, style: style.body, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (here)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(CupertinoIcons.location_fill, size: 13, color: style.accent),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [for (final e in area.byCategory.entries) _CategoryCount(e.key, e.value)],
        ),
      ],
    );
  }
}

/// Icon plus `done/total` for one category; dimmed when complete.
class _CategoryCount extends StatelessWidget {
  const _CategoryCount(this.category, this.progress);
  final String category;
  final Progress progress;

  @override
  Widget build(BuildContext context) {
    final look = CategoryStyle.of(category);
    return Opacity(
      opacity: progress.missing == 0 ? 0.45 : 1,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(look.icon, size: 14, color: look.color),
          const SizedBox(width: 4),
          Text('${progress.done}/${progress.total}', style: IosStyle.of(context).footnote),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// One area, one category

/// Ring, counts and a line of detail at the top of a checklist page.
class _Summary extends StatelessWidget {
  const _Summary({required this.progress, required this.detail, this.color, this.icon});
  final Progress progress;
  final String detail;
  final Color? color;

  /// Shown in the ring instead of the percentage.
  final Object? icon;

  @override
  Widget build(BuildContext context) {
    final style = IosStyle.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Row(
        children: [
          ProgressRing(
            progress: progress,
            size: 72,
            stroke: 7,
            color: color,
            track: style.fill,
            child: icon != null
                ? AppIcon(icon!, size: 28, color: color)
                : Text(percent(progress), style: style.headline),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${progress.done} of ${progress.total} collected', style: style.headline),
                const SizedBox(height: 2),
                Text(detail, style: style.subhead),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class IosAreaPage extends StatefulWidget {
  const IosAreaPage({super.key, required this.areaId});
  final String areaId;

  @override
  State<IosAreaPage> createState() => _IosAreaPageState();
}

class _IosAreaPageState extends State<IosAreaPage> {
  bool _missingOnly = false;
  String _era = 'any';

  @override
  Widget build(BuildContext context) {
    final client = ClientScope.of(context);
    final state = client.state;
    final area = state?.areas.where((a) => a.id == widget.areaId).firstOrNull;
    if (state == null || area == null) return const IosPage(title: '', filling: IosEmptyState());
    final spoilerFree = client.spoilerFree;
    final checks = state.checks.where((c) => c.def.area == area.id).toList();

    return IosPage(
      title: area.name,
      children: [
        _Summary(
          progress: area.progress,
          detail: [
            area.progress.missing == 0 ? 'Nothing left here' : '${area.progress.missing} still missing',
            if (state.save?.area == area.id) 'you are here',
            if (area.visited == false) 'not visited yet',
          ].join(' · '),
        ),
        if (!spoilerFree) ...[
          IosSegments<bool>(
            value: _missingOnly,
            options: const {false: 'All', true: 'Missing'},
            onChanged: (v) => setState(() => _missingOnly = v),
          ),
          IosSegments<String>(
            value: _era,
            options: const {'any': 'Any time', 'child': 'Child', 'adult': 'Adult'},
            onChanged: (v) => setState(() => _era = v),
          ),
        ],
        for (final e in area.byCategory.entries)
          _ChecksSection(
            area: area,
            category: e.key,
            progress: e.value,
            checks: checks.where((c) => c.def.category == e.key).toList(),
            spoilerFree: spoilerFree,
            missingOnly: _missingOnly,
            era: _era,
          ),
      ],
    );
  }
}

/// Every entry of one category, grouped by area.
class IosCategoryPage extends StatefulWidget {
  const IosCategoryPage({super.key, required this.category});
  final String category;

  @override
  State<IosCategoryPage> createState() => _IosCategoryPageState();
}

class _IosCategoryPageState extends State<IosCategoryPage> {
  bool _missingOnly = false;
  String _era = 'any';

  @override
  Widget build(BuildContext context) {
    final client = ClientScope.of(context);
    final state = client.state;
    final category = widget.category;
    if (state == null) return IosPage(title: categoryName(category), filling: const IosEmptyState());
    final look = CategoryStyle.of(category);
    final progress = state.byCategory[category] ?? const Progress(0, 0);
    final spoilerFree = client.spoilerFree;
    final areas = [
      for (final a in state.areas)
        if (a.byCategory.containsKey(category) && !(_missingOnly && a.byCategory[category]!.missing == 0)) a,
    ];
    final openAreas = state.areas.where((a) => (a.byCategory[category]?.missing ?? 0) > 0).length;

    return IosPage(
      title: categoryName(category),
      children: [
        _Summary(
          progress: progress,
          color: look.color,
          icon: look.icon,
          detail: progress.missing == 0
              ? 'All found'
              : '${progress.missing} still missing in $openAreas ${openAreas == 1 ? 'area' : 'areas'}',
        ),
        IosSegments<bool>(
          value: _missingOnly,
          options: {false: 'All', true: spoilerFree ? 'Something left' : 'Missing'},
          onChanged: (v) => setState(() => _missingOnly = v),
        ),
        if (!spoilerFree)
          IosSegments<String>(
            value: _era,
            options: const {'any': 'Any time', 'child': 'Child', 'adult': 'Adult'},
            onChanged: (v) => setState(() => _era = v),
          ),
        for (final area in areas)
          _ChecksSection(
            area: area,
            category: category,
            progress: area.byCategory[category]!,
            checks: state.checks.where((c) => c.def.area == area.id && c.def.category == category).toList(),
            spoilerFree: spoilerFree,
            missingOnly: _missingOnly,
            era: _era,
            title: area.name,
            icon: areaIcon(area),
          ),
      ],
    );
  }
}

class _ChecksSection extends StatelessWidget {
  const _ChecksSection({
    required this.area,
    required this.category,
    required this.progress,
    required this.checks,
    required this.spoilerFree,
    required this.missingOnly,
    required this.era,
    this.title,
    this.icon,
  });

  /// Heading and its icon; the category's by default.
  final String? title;
  final Object? icon;

  final AreaState area;
  final String category;
  final Progress progress;
  final List<CheckState> checks;
  final bool spoilerFree;
  final bool missingOnly;
  final String era;

  @override
  Widget build(BuildContext context) {
    final client = ClientScope.of(context);
    final style = IosStyle.of(context);
    final look = CategoryStyle.of(category);
    final section = CheckSection(
      area: area,
      category: category,
      progress: progress,
      checks: checks,
      spoilerFree: spoilerFree,
      missingOnly: missingOnly,
      era: era,
    );
    // Counts only: mark a find without revealing which ones exist.
    final counter = spoilerFree && section.hasManual && !section.counted;

    final rows = <Widget>[
      if (spoilerFree && progress.missing > 0)
        CupertinoListTile(
          leading: Icon(CupertinoIcons.question_circle, size: 24, color: style.tertiary),
          title: Text('${progress.missing} still missing'),
          trailing: !counter
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _RoundButton(
                      icon: CupertinoIcons.minus_circle,
                      label: 'Undo a find',
                      onPressed: client.canEdit && section.anonymous > 0
                          ? () => client.addAnonymous(area.id, category, -1)
                          : null,
                    ),
                    _RoundButton(
                      icon: CupertinoIcons.plus_circle_fill,
                      label: 'Found one here',
                      onPressed: client.canEdit && section.anonymous < section.manualOpen
                          ? () => client.addAnonymous(area.id, category, 1)
                          : null,
                    ),
                  ],
                ),
        ),
      for (final check in section.visible) _CheckRow(check: check, spoilerFree: spoilerFree),
    ];
    final note = spoilerFree ? null : section.unidentifiedNote;

    return CupertinoListSection.insetGrouped(
      header: IosSectionHeader(
        title ?? categoryName(category),
        icon: icon ?? look.icon,
        iconColor: icon == null ? look.color : null,
        trailing: '${progress.done}/${progress.total}',
      ),
      footer: note == null ? null : Text(note, style: style.footnote),
      children: rows.isEmpty ? null : rows,
    );
  }
}

/// A round symbol button inside a row.
class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.label, required this.onPressed});
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    child: CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      minimumSize: const Size(40, 32),
      onPressed: onPressed,
      child: Icon(icon, size: 28),
    ),
  );
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.check, required this.spoilerFree});
  final CheckState check;
  final bool spoilerFree;

  @override
  Widget build(BuildContext context) {
    final client = ClientScope.of(context);
    final style = IosStyle.of(context);
    final def = check.def;
    final title = def.number == null ? def.title : '#${def.number}  ${def.title}';
    final tags = checkTags(def);
    final details = !spoilerFree && !check.done;

    // Read from the save: gold, and not for the user to change. Ticked by
    // hand: in the accent colour, like a reminder.
    final mark = Icon(
      check.done ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
      size: 24,
      color: check.auto ? (check.done ? gold : style.tertiary) : (check.done ? style.accent : style.secondary),
    );
    final canTick = !check.auto && client.canEdit;

    return CupertinoListTile(
      padding: iosTilePadding,
      onTap: canTick ? () => client.tick(def.id, !check.done) : null,
      leading: Semantics(
        checked: check.done,
        label: check.auto ? 'Read from your save' : null,
        child: Opacity(opacity: check.auto || canTick ? 1 : 0.4, child: mark),
      ),
      title: IosTileBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: style.body.copyWith(color: check.done ? style.secondary : style.label)),
            if (details && def.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(def.description, style: style.subhead),
              ),
            if (details && (tags.isNotEmpty || !def.verified || check.uncertain))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in tags) _Tag(tag),
                    if (!def.verified) const _Tag('Unverified for the remake', warn: true),
                    if (check.uncertain) const _Tag('Match with save not certain', warn: true),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, {this.warn = false});
  final String label;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final style = IosStyle.of(context);
    final orange = IosStyle.orange.resolveFrom(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: warn ? orange.withValues(alpha: 0.18) : style.fill,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: style.footnote.copyWith(fontSize: 12, color: warn ? orange : style.secondary)),
    );
  }
}

// ---------------------------------------------------------------------------
// Settings

class IosSettingsPage extends StatefulWidget {
  const IosSettingsPage({super.key});

  @override
  State<IosSettingsPage> createState() => _IosSettingsPageState();
}

class _IosSettingsPageState extends State<IosSettingsPage> {
  TextEditingController? _host, _port, _token;

  @override
  void dispose() {
    _host?.dispose();
    _port?.dispose();
    _token?.dispose();
    super.dispose();
  }

  void _apply(TrackerClient client, {bool? auto}) => client.setServer(
    auto: auto ?? client.autoDiscover,
    host: _host!.text,
    port: int.tryParse(_port!.text) ?? 7437,
    token: _token!.text,
  );

  @override
  Widget build(BuildContext context) {
    final client = ClientScope.of(context);
    final style = IosStyle.of(context);
    _host ??= TextEditingController(text: client.host);
    _port ??= TextEditingController(text: '${client.port}');
    _token ??= TextEditingController(text: client.token);

    final status = switch (client.status) {
      LinkStatus.live => 'Connected to ${client.targetLabel}',
      LinkStatus.connecting => 'Connecting to ${client.targetLabel}…',
      LinkStatus.searching => 'Looking for a server on this network…',
      LinkStatus.offline => client.lastError ?? 'Not connected',
    };
    Widget footer(String text) => Text(text, style: style.footnote);
    Widget field(
      String label,
      TextEditingController controller, {
      String? placeholder,
      bool obscure = false,
      bool number = false,
    }) => CupertinoTextFormFieldRow(
      controller: controller,
      prefix: SizedBox(width: 120, child: Text(label, style: style.body)),
      placeholder: placeholder,
      obscureText: obscure,
      autocorrect: false,
      keyboardType: number ? TextInputType.number : null,
      textInputAction: TextInputAction.done,
      padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 6, 6),
      onFieldSubmitted: (_) => _apply(client),
    );

    return IosPage(
      title: 'Settings',
      children: [
        CupertinoListSection.insetGrouped(
          hasLeading: false,
          footer: footer('Shows only how many are missing per area, never where or how.'),
          children: [
            CupertinoListTile(
              title: const Text('Spoiler-free mode'),
              trailing: IosSwitch(value: client.spoilerFree, onChanged: client.setSpoilerFree),
            ),
          ],
        ),
        CupertinoListSection.insetGrouped(
          hasLeading: false,
          header: const IosSectionHeader('Server'),
          footer: footer(status),
          children: [
            CupertinoListTile(
              title: const Text('Find automatically'),
              subtitle: Text(
                client.found.isEmpty
                    ? 'No server found yet'
                    : client.found.map((s) => '${s.name} (${s.host}:${s.port})').join(', '),
              ),
              trailing: IosSwitch(
                value: client.autoDiscover,
                onChanged: (v) => _apply(client, auto: v),
              ),
            ),
            if (!client.autoDiscover) ...[
              field('Address', _host!, placeholder: '192.168.1.20'),
              field('Port', _port!, number: true),
            ],
          ],
        ),
        CupertinoListSection.insetGrouped(
          hasLeading: false,
          footer: footer('Only needed if the server asks for a token.'),
          children: [
            field('Access token', _token!, placeholder: 'None', obscure: true),
            CupertinoListTile(
              title: Text('Connect', style: TextStyle(color: style.accent)),
              onTap: () => _apply(client),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: footer('Unofficial fan project. Not affiliated with or endorsed by Nintendo.'),
        ),
      ],
    );
  }
}
