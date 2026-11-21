import 'package:material_ui/material_ui.dart';
import 'package:oot_tracker/oot_tracker.dart';

import '../widgets.dart';
import 'area_detail.dart';

class OverviewScreen extends StatelessWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final client = ClientScope.of(context);
    final state = client.state;
    if (state == null) return const EmptyState();
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (state.save == null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.save_outlined),
              title: const Text('No save loaded'),
              subtitle: Text(state.error ?? 'The server has not found a save yet.'),
            ),
          )
        else
          _SaveCard(state: state),
        const SizedBox(height: 16),
        Row(
          children: [
            ProgressRing(
              progress: state.total,
              size: 112,
              stroke: 10,
              child: Text(percent(state.total), style: theme.textTheme.headlineSmall),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${state.total.done} of ${state.total.total}', style: theme.textTheme.headlineSmall),
                  Text('${state.total.missing} still missing', style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
        for (final m in state.mismatches) _MismatchCard(m),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, box) {
            final columns = (box.maxWidth / 260).floor().clamp(1, 4);
            final width = (box.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final entry in state.byCategory.entries)
                  SizedBox(width: width, child: _CategoryTile(entry.key, entry.value)),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SaveCard extends StatelessWidget {
  const _SaveCard({required this.state});
  final TrackerState state;

  @override
  Widget build(BuildContext context) {
    final client = ClientScope.of(context);
    final save = state.save!;
    final theme = Theme.of(context);
    final area = state.areas.where((a) => a.id == save.area).firstOrNull;
    final saved = save.savedAt?.replaceFirst('T', ' · ') ?? 'unknown time';

    final stats = Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        _Stat(Icons.favorite, const Color(0xFFE5645E), '${save.hearts} hearts'),
        _Stat(Glyph.rupee, const Color(0xFF7BC67E), '${save.rupees}'),
        _Stat(Glyph.skull, gold, '${save.tokens} tokens'),
        _Stat(Icons.person, theme.colorScheme.onSurfaceVariant, save.era == 'adult' ? 'Adult' : 'Child'),
      ],
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (client.screenshot != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: Image.memory(client.screenshot!, fit: BoxFit.cover, gaplessPlayback: true),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(area?.name ?? save.banc, style: theme.textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(
                  '${save.slot.replaceFirst('slot_0', 'Slot ')} · ${save.autosave ? 'autosave' : 'manual save'} · $saved',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                stats,
              ],
            ),
          ),
        ],
      ),
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
      AppIcon(icon, size: 18, color: color),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.bodyMedium),
    ],
  );
}

class _MismatchCard extends StatelessWidget {
  const _MismatchCard(this.mismatch);
  final Mismatch mismatch;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = categoryName(mismatch.category);
    final gap = mismatch.save - mismatch.ticked;
    return Card(
      margin: const EdgeInsets.only(top: 16),
      color: scheme.tertiaryContainer,
      child: ListTile(
        leading: Icon(Icons.rule, color: scheme.onTertiaryContainer),
        title: Text(
          gap > 0 ? '$gap $name not marked yet' : '${-gap} $name marked too many',
          style: TextStyle(color: scheme.onTertiaryContainer),
        ),
        subtitle: Text(
          'Your save has ${mismatch.estimate ? 'about ' : ''}${mismatch.save}, '
          'the tracker has ${mismatch.ticked} marked. Mark them in their areas.',
          style: TextStyle(color: scheme.onTertiaryContainer),
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile(this.category, this.progress);
  final String category;
  final Progress progress;

  @override
  Widget build(BuildContext context) {
    final style = CategoryStyle.of(category);
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          final client = ClientScope.of(context);
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ClientScope(
                client: client,
                child: CategoryDetailScreen(category: category),
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppIcon(style.icon, color: style.color, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(categoryName(category), style: theme.textTheme.titleSmall)),
                  Text('${progress.done}/${progress.total}', style: theme.textTheme.titleSmall),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress.fraction,
                  minHeight: 6,
                  color: style.color,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
