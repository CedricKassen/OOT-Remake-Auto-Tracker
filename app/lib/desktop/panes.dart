import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:oot_tracker/oot_tracker.dart';

import '../client.dart';
import '../widgets.dart';
import 'style.dart';

const double _contentWidth = 860;

/// Scrolls [children] in a centred column of comfortable reading width.
class _Page extends StatelessWidget {
  const _Page({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(28, 20, 28, 36),
    children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _contentWidth),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ),
    ],
  );
}

class DesktopEmptyState extends StatelessWidget {
  const DesktopEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final client = ClientScope.of(context);
    final style = DesktopStyle.of(context);
    final (icon, title, detail) = switch (client.status) {
      LinkStatus.searching => (
        CupertinoIcons.wifi,
        'Looking for the tracker server…',
        'Start ootd on this Mac, or on another Mac in the same network.',
      ),
      LinkStatus.connecting => (CupertinoIcons.arrow_2_circlepath, 'Connecting…', client.targetLabel),
      _ => (CupertinoIcons.wifi_slash, 'Not connected', client.lastError ?? 'Set the server address in Settings.'),
    };
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: style.tertiary),
          const SizedBox(height: 14),
          Text(title, style: style.title),
          const SizedBox(height: 6),
          Text(detail, style: style.bodySecondary, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overview

class OverviewPane extends StatelessWidget {
  const OverviewPane({super.key, required this.state, required this.onOpenArea});
  final TrackerState state;
  final ValueChanged<String> onOpenArea;

  @override
  Widget build(BuildContext context) {
    final client = ClientScope.of(context);
    final style = DesktopStyle.of(context);
    final save = state.save;
    final area = state.areas.where((a) => a.id == save?.area).firstOrNull;
    final open = [
      for (final a in state.areas)
        if (a.progress.missing > 0) a,
    ]..sort((a, b) => b.progress.missing.compareTo(a.progress.missing));

    final progress = Row(
      children: [
        ProgressRing(
          progress: state.total,
          size: 92,
          stroke: 9,
          track: style.track,
          child: Text(percent(state.total), style: style.title),
        ),
        const SizedBox(width: 18),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${state.total.done} of ${state.total.total}', style: style.largeTitle),
            Text('${state.total.missing} still missing', style: style.bodySecondary),
          ],
        ),
      ],
    );

    final saveInfo = save == null
        ? Text(state.error ?? 'The server has not found a save yet.', style: style.bodySecondary)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(area?.name ?? save.banc, style: style.title),
              const SizedBox(height: 2),
              Text(
                '${save.slot.replaceFirst('slot_0', 'Slot ')} · ${save.autosave ? 'autosave' : 'manual save'} · '
                '${save.savedAt?.replaceFirst('T', ' at ') ?? 'unknown time'}',
                style: style.caption,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 18,
                runSpacing: 6,
                children: [
                  _Stat(CupertinoIcons.heart_fill, const Color(0xFFE5645E), '${save.hearts} hearts'),
                  _Stat(Glyph.rupee, const Color(0xFF5FBF77), '${save.rupees} rupees'),
                  _Stat(Glyph.skull, gold, '${save.tokens} tokens'),
                  _Stat(CupertinoIcons.person_fill, style.secondary, save.era == 'adult' ? 'Adult' : 'Child'),
                ],
              ),
            ],
          );

    return _Page(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (client.screenshot != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  client.screenshot!,
                  width: 300,
                  height: 169,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              ),
              const SizedBox(width: 24),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [saveInfo, const SizedBox(height: 22), progress],
              ),
            ),
          ],
        ),
        for (final m in state.mismatches)
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: GroupBox(
              padding: const EdgeInsets.all(12),
              children: [
                Row(
                  children: [
                    const Icon(CupertinoIcons.exclamationmark_triangle_fill, size: 16, color: Color(0xFFFF9F0A)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your save has ${m.estimate ? 'about ' : ''}${m.save} ${categoryName(m.category)}, '
                        'the tracker has ${m.ticked} marked.',
                        style: style.body,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        const SectionHeader('Categories'),
        GroupBox(
          children: [
            for (final e in state.byCategory.entries)
              _ProgressRow.category(e.key, e.value, onTap: () => onOpenArea('cat:${e.key}')),
          ],
        ),
        if (open.isNotEmpty) ...[
          SectionHeader('Areas with something left', trailing: '${open.length}'),
          GroupBox(
            children: [
              for (final a in open)
                _ProgressRow(
                  icon: areaIcon(a),
                  color: style.accent,
                  label: a.name,
                  progress: a.progress,
                  onTap: () => onOpenArea(a.id),
                ),
            ],
          ),
        ],
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
      AppIcon(icon, size: 14, color: color),
      const SizedBox(width: 5),
      Text(label, style: DesktopStyle.of(context).body),
    ],
  );
}

/// Icon, name, progress bar, `done/total` and how many are missing.
class _ProgressRow extends StatefulWidget {
  const _ProgressRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.progress,
    this.onTap,
  });

  factory _ProgressRow.category(String category, Progress progress, {VoidCallback? onTap}) {
    final look = CategoryStyle.of(category);
    return _ProgressRow(
      icon: look.icon,
      color: look.color,
      label: categoryName(category),
      progress: progress,
      onTap: onTap,
    );
  }

  final Object icon;
  final Color color;
  final String label;
  final Progress progress;
  final VoidCallback? onTap;

  @override
  State<_ProgressRow> createState() => _ProgressRowState();
}

class _ProgressRowState extends State<_ProgressRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final style = DesktopStyle.of(context);
    final p = widget.progress;
    final row = Container(
      color: _hover && widget.onTap != null ? style.hover : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          AppIcon(widget.icon, size: 15, color: widget.color),
          const SizedBox(width: 10),
          SizedBox(
            width: 250,
            child: Text(widget.label, style: style.body, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            child: Bar(fraction: p.fraction, color: widget.color),
          ),
          SizedBox(
            width: 70,
            child: Text('${p.done}/${p.total}', style: style.number, textAlign: TextAlign.right),
          ),
          SizedBox(
            width: 92,
            child: Text(
              p.missing == 0 ? 'complete' : '${p.missing} missing',
              style: style.caption,
              textAlign: TextAlign.right,
            ),
          ),
          if (widget.onTap != null)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Icon(CupertinoIcons.chevron_right, size: 11, color: style.tertiary),
            ),
        ],
      ),
    );
    if (widget.onTap == null) return row;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onTap, child: row),
    );
  }
}

// ---------------------------------------------------------------------------
// One area

class AreaPane extends StatelessWidget {
  const AreaPane({super.key, required this.state, required this.area, required this.missingOnly});
  final TrackerState state;
  final AreaState area;
  final bool missingOnly;

  @override
  Widget build(BuildContext context) {
    final client = ClientScope.of(context);
    final style = DesktopStyle.of(context);
    final checks = state.checks.where((c) => c.def.area == area.id).toList();
    final here = state.save?.area == area.id;

    return _Page(
      children: [
        Row(
          children: [
            ProgressRing(
              progress: area.progress,
              size: 64,
              stroke: 7,
              track: style.track,
              child: Text(percent(area.progress), style: style.headline),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${area.progress.done} of ${area.progress.total} collected', style: style.title),
                  const SizedBox(height: 2),
                  Text(
                    [
                      area.progress.missing == 0 ? 'Nothing left here' : '${area.progress.missing} still missing',
                      if (here) 'you are here',
                      if (area.visited == false) 'not visited yet',
                    ].join(' · '),
                    style: style.bodySecondary,
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: 14,
              children: [
                for (final e in area.byCategory.entries)
                  MacosTooltip(
                    message: '${categoryName(e.key)}: ${e.value.missing} missing',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppIcon(CategoryStyle.of(e.key).icon, size: 14, color: CategoryStyle.of(e.key).color),
                        const SizedBox(width: 4),
                        Text('${e.value.done}/${e.value.total}', style: style.number),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
        for (final e in area.byCategory.entries)
          _CategoryGroup(
            area: area,
            category: e.key,
            progress: e.value,
            checks: checks.where((c) => c.def.category == e.key).toList(),
            spoilerFree: client.spoilerFree,
            missingOnly: missingOnly,
          ),
      ],
    );
  }
}

class _CategoryGroup extends StatelessWidget {
  const _CategoryGroup({
    required this.area,
    required this.category,
    required this.progress,
    required this.checks,
    required this.spoilerFree,
    required this.missingOnly,
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

  @override
  Widget build(BuildContext context) {
    final client = ClientScope.of(context);
    final style = DesktopStyle.of(context);
    final look = CategoryStyle.of(category);
    final anonymous = area.anonymous[category] ?? 0;
    final counted = area.counted.contains(category);
    final manualOpen = checks.where((c) => !c.auto && !c.done).length;
    final hasManual = checks.any((c) => !c.auto);
    final unidentified = counted ? progress.done - checks.where((c) => c.done).length : anonymous;

    final sorted = [...checks]
      ..sort((a, b) {
        if (a.done != b.done) return a.done ? 1 : -1;
        final byNumber = (a.def.number ?? 0).compareTo(b.def.number ?? 0);
        return byNumber != 0 ? byNumber : a.def.title.compareTo(b.def.title);
      });
    final visible = [
      for (final c in sorted)
        if (spoilerFree ? c.done : !(missingOnly && c.done)) c,
    ];

    final rows = <Widget>[
      if (spoilerFree && progress.missing > 0)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(CupertinoIcons.question_circle, size: 15, color: style.tertiary),
              const SizedBox(width: 10),
              Expanded(child: Text('${progress.missing} still missing', style: style.body)),
              if (hasManual && !counted) ...[
                // Counts only: mark a find without revealing which ones exist.
                PushButton(
                  controlSize: ControlSize.small,
                  secondary: true,
                  onPressed: client.canEdit && anonymous > 0 ? () => client.addAnonymous(area.id, category, -1) : null,
                  child: const Text('Undo'),
                ),
                const SizedBox(width: 8),
                PushButton(
                  controlSize: ControlSize.small,
                  onPressed: client.canEdit && anonymous < manualOpen
                      ? () => client.addAnonymous(area.id, category, 1)
                      : null,
                  child: const Text('Found one'),
                ),
              ],
            ],
          ),
        ),
      for (final check in visible) _CheckRow(check: check, spoilerFree: spoilerFree),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title ?? categoryName(category),
          icon: icon ?? look.icon,
          iconColor: icon == null ? look.color : style.secondary,
          trailing: '${progress.done}/${progress.total}',
        ),
        if (!spoilerFree && unidentified > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              counted
                  ? 'Your save has $unidentified more of these than are ticked. '
                        'It does not say which, so tick the ones you have.'
                  : '$unidentified found without saying which. Tick the ones you have.',
              style: style.caption,
            ),
          ),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('Nothing to show with this filter.', style: style.caption),
          )
        else
          GroupBox(children: rows),
      ],
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.check, required this.spoilerFree});
  final CheckState check;
  final bool spoilerFree;

  @override
  Widget build(BuildContext context) {
    final client = ClientScope.of(context);
    final style = DesktopStyle.of(context);
    final def = check.def;
    final title = def.number == null ? def.title : '#${def.number}  ${def.title}';
    final tags = [
      if (def.era.length == 1) def.era.first == 'child' ? 'Child' : 'Adult',
      if (def.night) 'Night',
      ...def.requires,
    ];
    final details = !spoilerFree && !check.done;

    final Widget leading = check.auto
        ? MacosTooltip(
            message: 'Read from your save',
            child: Icon(
              check.done ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
              size: 16,
              color: check.done ? gold : style.tertiary,
            ),
          )
        : MacosCheckbox(value: check.done, size: 15, onChanged: client.canEdit ? (v) => client.tick(def.id, v) : null);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: leading),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: style.body.copyWith(color: check.done ? style.secondary : style.label)),
                if (details && def.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(def.description, style: style.caption.copyWith(fontSize: 12)),
                  ),
              ],
            ),
          ),
          if (details && (tags.isNotEmpty || !def.verified || check.uncertain))
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  alignment: WrapAlignment.end,
                  children: [
                    for (final tag in tags) _Tag(tag),
                    if (!def.verified) const _Tag('Unverified for the remake', warn: true),
                    if (check.uncertain) const _Tag('Match with save not certain', warn: true),
                  ],
                ),
              ),
            ),
        ],
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
    final style = DesktopStyle.of(context);
    const amber = Color(0xFFFF9F0A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: warn ? amber.withValues(alpha: 0.18) : style.track,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: style.caption.copyWith(color: warn ? amber : style.secondary)),
    );
  }
}

// ---------------------------------------------------------------------------
// One category across all areas

class CategoryPane extends StatelessWidget {
  const CategoryPane({
    super.key,
    required this.state,
    required this.category,
    required this.missingOnly,
    required this.onOpenArea,
  });
  final TrackerState state;
  final String category;
  final bool missingOnly;
  final ValueChanged<String> onOpenArea;

  @override
  Widget build(BuildContext context) {
    final client = ClientScope.of(context);
    final style = DesktopStyle.of(context);
    final look = CategoryStyle.of(category);
    final progress = state.byCategory[category] ?? const Progress(0, 0);
    final areas = [
      for (final a in state.areas)
        if (a.byCategory.containsKey(category) && !(missingOnly && a.byCategory[category]!.missing == 0)) a,
    ];
    final openAreas = state.areas.where((a) => (a.byCategory[category]?.missing ?? 0) > 0).length;

    return _Page(
      children: [
        Row(
          children: [
            ProgressRing(
              progress: progress,
              size: 64,
              stroke: 7,
              color: look.color,
              track: style.track,
              child: AppIcon(look.icon, size: 24, color: look.color),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${progress.done} of ${progress.total} collected', style: style.title),
                const SizedBox(height: 2),
                Text(
                  progress.missing == 0
                      ? 'All found'
                      : '${progress.missing} still missing in $openAreas ${openAreas == 1 ? 'area' : 'areas'}',
                  style: style.bodySecondary,
                ),
              ],
            ),
          ],
        ),
        for (final area in areas)
          _CategoryGroup(
            area: area,
            category: category,
            progress: area.byCategory[category]!,
            checks: state.checks.where((c) => c.def.area == area.id && c.def.category == category).toList(),
            spoilerFree: client.spoilerFree,
            missingOnly: missingOnly,
            title: area.name,
            icon: areaIcon(area),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Settings

class SettingsPane extends StatefulWidget {
  const SettingsPane({super.key});

  @override
  State<SettingsPane> createState() => _SettingsPaneState();
}

class _SettingsPaneState extends State<SettingsPane> {
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

  Widget _row(BuildContext context, String title, String? detail, Widget control) {
    final style = DesktopStyle.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: style.body),
                if (detail != null) Text(detail, style: style.caption),
              ],
            ),
          ),
          const SizedBox(width: 16),
          control,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = ClientScope.of(context);
    final style = DesktopStyle.of(context);
    _host ??= TextEditingController(text: client.host);
    _port ??= TextEditingController(text: '${client.port}');
    _token ??= TextEditingController(text: client.token);

    final status = switch (client.status) {
      LinkStatus.live => 'Connected to ${client.targetLabel}',
      LinkStatus.connecting => 'Connecting to ${client.targetLabel}…',
      LinkStatus.searching => 'Looking for a server on this network…',
      LinkStatus.offline => client.lastError ?? 'Not connected',
    };

    return _Page(
      children: [
        const SectionHeader('Display'),
        GroupBox(
          children: [
            _row(
              context,
              'Spoiler-free mode',
              'Show only how many are missing per area, never where or how.',
              MacosSwitch(value: client.spoilerFree, onChanged: client.setSpoilerFree),
            ),
          ],
        ),
        const SectionHeader('Server'),
        GroupBox(
          children: [
            _row(
              context,
              'Status',
              null,
              Flexible(
                child: Text(status, style: style.bodySecondary, textAlign: TextAlign.right),
              ),
            ),
            _row(
              context,
              'Find the server automatically',
              client.found.isEmpty
                  ? 'No server found yet'
                  : client.found.map((s) => '${s.name} (${s.host}:${s.port})').join(', '),
              MacosSwitch(
                value: client.autoDiscover,
                onChanged: (v) => _apply(client, auto: v),
              ),
            ),
            if (!client.autoDiscover)
              _row(
                context,
                'Address and port',
                null,
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 190,
                      child: MacosTextField(
                        controller: _host,
                        placeholder: '192.168.1.20',
                        onSubmitted: (_) => _apply(client),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 70,
                      child: MacosTextField(controller: _port, onSubmitted: (_) => _apply(client)),
                    ),
                  ],
                ),
              ),
            _row(
              context,
              'Access token',
              'Only needed if the server was started with --token.',
              SizedBox(
                width: 268,
                child: MacosTextField(controller: _token, obscureText: true, onSubmitted: (_) => _apply(client)),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Align(
            alignment: Alignment.centerRight,
            child: PushButton(
              controlSize: ControlSize.regular,
              onPressed: () => _apply(client),
              child: const Text('Connect'),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 28),
          child: Text('Unofficial fan project. Not affiliated with or endorsed by Nintendo.', style: style.caption),
        ),
      ],
    );
  }
}
