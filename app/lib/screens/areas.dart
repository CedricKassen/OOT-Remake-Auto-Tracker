import 'package:flutter/material.dart';
import 'package:oot_tracker/oot_tracker.dart';

import '../widgets.dart';
import 'area_detail.dart';

void openArea(BuildContext context, String areaId) {
  final client = ClientScope.of(context);
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ClientScope(
        client: client,
        child: AreaDetailScreen(areaId: areaId),
      ),
    ),
  );
}

class AreasScreen extends StatefulWidget {
  const AreasScreen({super.key});

  @override
  State<AreasScreen> createState() => _AreasScreenState();
}

class _AreasScreenState extends State<AreasScreen> {
  bool _hideComplete = false;

  @override
  Widget build(BuildContext context) {
    final state = ClientScope.of(context).state;
    if (state == null) return const EmptyState();
    final areas = [
      for (final a in state.areas)
        if (a.progress.total > 0 && !(_hideComplete && a.progress.missing == 0)) a,
    ];
    final complete = state.areas.where((a) => a.progress.total > 0 && a.progress.missing == 0).length;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: areas.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            title: const Text('Hide completed areas'),
            subtitle: Text('$complete of ${state.areas.length} areas complete'),
            value: _hideComplete,
            onChanged: (v) => setState(() => _hideComplete = v),
          );
        }
        final area = areas[index - 1];
        return _AreaCard(area: area, here: state.save?.area == area.id);
      },
    );
  }
}

class _AreaCard extends StatelessWidget {
  const _AreaCard({required this.area, required this.here});
  final AreaState area;
  final bool here;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final missing = area.progress.missing;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openArea(context, area.id),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              ProgressRing(
                progress: area.progress,
                size: 52,
                stroke: 5,
                child: missing == 0
                    ? const Icon(Icons.check, color: gold, size: 22)
                    : Text('$missing', style: theme.textTheme.titleMedium),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(areaIcon(area), size: 16, color: theme.colorScheme.outline),
                        ),
                        Flexible(
                          child: Text(area.name, style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis),
                        ),
                        if (here)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Chip(
                              label: const Text('You are here'),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              labelStyle: theme.textTheme.labelSmall,
                              side: BorderSide.none,
                              backgroundColor: theme.colorScheme.primaryContainer,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 14,
                      runSpacing: 6,
                      children: [
                        for (final e in area.byCategory.entries) CategoryCount(category: e.key, progress: e.value),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
