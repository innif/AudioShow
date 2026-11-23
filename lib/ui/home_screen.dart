import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import 'settings_screen.dart';

/// Route name for the show view; argument is the show name.
const showRoute = '/show';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _openSettings(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));

  Future<void> _openShow(BuildContext context, String name) async {
    await Navigator.of(context).pushNamed(showRoute, arguments: name);
    if (context.mounted) await context.read<AppState>().rescan();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final autoOpen = state.takeAutoOpenShow();
    if (autoOpen != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) _openShow(context, autoOpen);
      });
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('AudioShow'),
        actions: [
          IconButton(
            tooltip: 'Aktualisieren',
            icon: const Icon(Icons.refresh),
            onPressed: state.settings.cueRoot == null ? null : state.rescan,
          ),
          IconButton(
            tooltip: 'Einstellungen',
            icon: const Icon(Icons.settings),
            onPressed: () => _openSettings(context),
          ),
        ],
      ),
      body: !state.ready ? const Center(child: CircularProgressIndicator()) : _body(context, state),
      floatingActionButton: state.ready && state.library.error == null && state.settings.cueRoot != null
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Neue Show'),
              onPressed: () async {
                final show = await state.createShowToday();
                if (context.mounted) await _openShow(context, show.name);
              },
            )
          : null,
    );
  }

  Widget _message(BuildContext context, IconData icon, String text, String button, VoidCallback onPressed) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 24),
            FilledButton(onPressed: onPressed, child: Text(button)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AppState state) {
    if (!state.hasPermission) {
      return _message(
        context,
        Icons.lock_outline,
        'AudioShow braucht „Zugriff auf alle Dateien“, um den Cue-Ordner zu lesen und Einstellungen zu speichern.',
        'Zugriff erlauben',
        state.requestPermission,
      );
    }
    if (state.settings.cueRoot == null) {
      return _message(context, Icons.folder_open, 'Noch kein Cue-Ordner festgelegt.', 'Cue-Ordner wählen',
          () => _openSettings(context));
    }
    if (state.library.error != null) {
      return _message(context, Icons.error_outline, state.library.error!, 'Einstellungen öffnen',
          () => _openSettings(context));
    }
    if (state.showNames.isEmpty) {
      return const Center(child: Text('Noch keine Shows. Lege mit „Neue Show“ den heutigen Abend an.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: state.showNames.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final name = state.showNames[i];
        return ListTile(
          minTileHeight: 64,
          leading: const Icon(Icons.queue_music),
          title: Text(name, style: Theme.of(context).textTheme.titleLarge),
          onTap: () => _openShow(context, name),
          trailing: PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'dup') {
                final show = await state.duplicateForToday(name);
                if (context.mounted) await _openShow(context, show.name);
              } else if (v == 'del') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: Text('Show „$name“ löschen?'),
                    content: const Text('Die Audiodateien und Cue-Einstellungen bleiben erhalten.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
                      FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Löschen')),
                    ],
                  ),
                );
                if (ok == true) await state.deleteShow(name);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'dup', child: Text('Als Vorlage für heute')),
              PopupMenuItem(value: 'del', child: Text('Löschen')),
            ],
          ),
        );
      },
    );
  }
}
