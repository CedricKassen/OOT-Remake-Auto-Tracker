import 'package:material_ui/material_ui.dart';

import '../client.dart';
import '../widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  TextEditingController? _host, _port, _token;

  @override
  void dispose() {
    _host?.dispose();
    _port?.dispose();
    _token?.dispose();
    super.dispose();
  }

  void _apply(TrackerClient client, {bool? auto}) {
    client.setServer(
      auto: auto ?? client.autoDiscover,
      host: _host!.text,
      port: int.tryParse(_port!.text) ?? 7437,
      token: _token!.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = ClientScope.of(context);
    _host ??= TextEditingController(text: client.host);
    _port ??= TextEditingController(text: '${client.port}');
    _token ??= TextEditingController(text: client.token);
    final theme = Theme.of(context);

    final (statusIcon, statusText) = switch (client.status) {
      LinkStatus.live => (Icons.check_circle, 'Connected to ${client.targetLabel}'),
      LinkStatus.connecting => (Icons.sync, 'Connecting to ${client.targetLabel}…'),
      LinkStatus.searching => (Icons.wifi_find, 'Looking for a server on this network…'),
      LinkStatus.offline => (Icons.cloud_off, 'Not connected'),
    };

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SwitchListTile(
          title: const Text('Spoiler-free mode'),
          subtitle: const Text('Show only how many are missing per area, never where or how.'),
          value: client.spoilerFree,
          onChanged: client.setSpoilerFree,
        ),
        const Divider(height: 32),
        ListTile(
          leading: Icon(statusIcon),
          title: Text(statusText),
          subtitle: client.status != LinkStatus.live && client.lastError != null ? Text(client.lastError!) : null,
        ),
        SwitchListTile(
          title: const Text('Find the server automatically'),
          subtitle: Text(
            client.found.isEmpty
                ? 'No server found yet'
                : client.found.map((s) => '${s.name} (${s.host}:${s.port})').join(', '),
          ),
          value: client.autoDiscover,
          onChanged: (v) => _apply(client, auto: v),
        ),
        if (!client.autoDiscover)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _host,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Address', hintText: '192.168.1.20'),
                    onSubmitted: (_) => _apply(client),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _port,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Port'),
                    onSubmitted: (_) => _apply(client),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _token,
            autocorrect: false,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Access token',
              helperText: 'Only needed if the server was started with --token',
            ),
            onSubmitted: (_) => _apply(client),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonal(onPressed: () => _apply(client), child: const Text('Connect')),
          ),
        ),
        const Divider(height: 32),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Unofficial fan project. Not affiliated with or endorsed by Nintendo.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
