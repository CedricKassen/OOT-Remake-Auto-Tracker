import 'package:material_ui/material_ui.dart';
import 'package:oot_tracker/oot_tracker.dart';

import '../checks.dart';
import '../widgets.dart';

class AreaDetailScreen extends StatefulWidget {
  const AreaDetailScreen({super.key, required this.areaId});
  final String areaId;

  @override
  State<AreaDetailScreen> createState() => _AreaDetailScreenState();
}

class _AreaDetailScreenState extends State<AreaDetailScreen> {
  bool _missingOnly = false;
  String _era = 'any';

  @override
  Widget build(BuildContext context) {
    final client = ClientScope.of(context);
    final state = client.state;
    final area = state?.areas.where((a) => a.id == widget.areaId).firstOrNull;
    if (state == null || area == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState());
    }
    final theme = Theme.of(context);
    final spoilerFree = client.spoilerFree;
    final checks = state.checks.where((c) => c.def.area == area.id).toList();

    return Scaffold(
      appBar: AppBar(title: Text(area.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(
            children: [
              ProgressRing(
                progress: area.progress,
                size: 72,
                stroke: 7,
                child: Text(percent(area.progress), style: theme.textTheme.titleMedium),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${area.progress.done} of ${area.progress.total} collected',
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      area.progress.missing == 0 ? 'Nothing left here' : '${area.progress.missing} still missing',
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (area.visited == false) Text('Not visited yet', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          if (!spoilerFree) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                  label: const Text('Missing only'),
                  selected: _missingOnly,
                  onSelected: (v) => setState(() => _missingOnly = v),
                ),
                for (final (value, label) in [('child', 'Child'), ('adult', 'Adult')])
                  FilterChip(
                    label: Text(label),
                    selected: _era == value,
                    onSelected: (v) => setState(() => _era = v ? value : 'any'),
                  ),
              ],
            ),
          ],
          for (final entry in area.byCategory.entries)
            _CategorySection(
              area: area,
              category: entry.key,
              progress: entry.value,
              checks: checks.where((c) => c.def.category == entry.key).toList(),
              spoilerFree: spoilerFree,
              missingOnly: _missingOnly,
              era: _era,
            ),
        ],
      ),
    );
  }
}

/// Every entry of one category, grouped by area.
class CategoryDetailScreen extends StatefulWidget {
  const CategoryDetailScreen({super.key, required this.category});
  final String category;

  @override
  State<CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends State<CategoryDetailScreen> {
  bool _missingOnly = false;
  String _era = 'any';

  @override
  Widget build(BuildContext context) {
    final client = ClientScope.of(context);
    final state = client.state;
    final category = widget.category;
    if (state == null) return Scaffold(appBar: AppBar(), body: const EmptyState());
    final theme = Theme.of(context);
    final look = CategoryStyle.of(category);
    final progress = state.byCategory[category] ?? const Progress(0, 0);
    final spoilerFree = client.spoilerFree;
    final areas = [
      for (final a in state.areas)
        if (a.byCategory.containsKey(category) && !(_missingOnly && a.byCategory[category]!.missing == 0)) a,
    ];

    return Scaffold(
      appBar: AppBar(title: Text(categoryName(category))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(
            children: [
              ProgressRing(
                progress: progress,
                size: 72,
                stroke: 7,
                color: look.color,
                child: AppIcon(look.icon, size: 28, color: look.color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${progress.done} of ${progress.total} collected', style: theme.textTheme.titleMedium),
                    Text(
                      progress.missing == 0 ? 'All found' : '${progress.missing} still missing',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: Text(spoilerFree ? 'Hide completed areas' : 'Missing only'),
                selected: _missingOnly,
                onSelected: (v) => setState(() => _missingOnly = v),
              ),
              if (!spoilerFree)
                for (final (value, label) in [('child', 'Child'), ('adult', 'Adult')])
                  FilterChip(
                    label: Text(label),
                    selected: _era == value,
                    onSelected: (v) => setState(() => _era = v ? value : 'any'),
                  ),
            ],
          ),
          for (final area in areas)
            _CategorySection(
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
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({
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
    final theme = Theme.of(context);
    final style = CategoryStyle.of(category);
    final section = CheckSection(
      area: area,
      category: category,
      progress: progress,
      checks: checks,
      spoilerFree: spoilerFree,
      missingOnly: missingOnly,
      era: era,
    );
    final anonymous = section.anonymous;
    final counted = section.counted;
    final manualOpen = section.manualOpen;
    final hasManual = section.hasManual;
    final unidentified = section.unidentified;
    final visible = section.visible;

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIcon(icon ?? style.icon, color: icon == null ? style.color : theme.colorScheme.outline, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(title ?? categoryName(category), style: theme.textTheme.titleMedium)),
              Text('${progress.done}/${progress.total}', style: theme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 6),
          if (spoilerFree && hasManual && !counted)
            // Counts only: mark a find without revealing which ones exist.
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        progress.missing == 0 ? 'All found' : '${progress.missing} still missing',
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Undo a find',
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: client.canEdit && anonymous > 0
                          ? () => client.addAnonymous(area.id, category, -1)
                          : null,
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Found one here',
                      icon: const Icon(Icons.add),
                      onPressed: client.canEdit && anonymous < manualOpen
                          ? () => client.addAnonymous(area.id, category, 1)
                          : null,
                    ),
                  ],
                ),
              ),
            )
          else if (spoilerFree && progress.missing > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('${progress.missing} still missing', style: theme.textTheme.bodyMedium),
            ),
          if (!spoilerFree && unidentified > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                section.unidentifiedNote!,
                style: theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.tertiary),
              ),
            ),
          for (final check in visible) _CheckTile(check: check, spoilerFree: spoilerFree),
        ],
      ),
    );
  }
}

class _CheckTile extends StatelessWidget {
  const _CheckTile({required this.check, required this.spoilerFree});
  final CheckState check;
  final bool spoilerFree;

  @override
  Widget build(BuildContext context) {
    final client = ClientScope.of(context);
    final theme = Theme.of(context);
    final def = check.def;
    final title = def.number == null ? def.title : '#${def.number} · ${def.title}';
    final tags = checkTags(def);
    final dim = check.done ? theme.colorScheme.onSurfaceVariant : null;

    final Widget leading = check.auto
        ? Tooltip(
            message: 'Read from your save',
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(
                check.done ? Icons.check_circle : Icons.radio_button_unchecked,
                color: check.done ? gold : theme.colorScheme.outline,
              ),
            ),
          )
        : Checkbox(value: check.done, onChanged: client.canEdit ? (v) => client.tick(def.id, v ?? false) : null);

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 14, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            leading,
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.bodyLarge!.copyWith(color: dim)),
                    if (!spoilerFree && !check.done) ...[
                      if (def.description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(def.description, style: theme.textTheme.bodyMedium),
                        ),
                      if (tags.isNotEmpty || !def.verified || check.uncertain)
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
                  ],
                ),
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
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: warn ? scheme.errorContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall!.copyWith(color: warn ? scheme.onErrorContainer : scheme.onSurfaceVariant),
      ),
    );
  }
}
