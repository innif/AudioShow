import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../model/cue_settings.dart';
import '../storage/app_settings.dart';
import 'format.dart';

const _fadeChoices = [
  Duration(milliseconds: 500),
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 3),
  Duration(seconds: 5),
  Duration(seconds: 8),
  Duration(seconds: 10),
];

String goBehaviorLabel(GoBehavior b) => switch (b) {
      GoBehavior.fadeOut => 'Ausblenden',
      GoBehavior.stop => 'Stoppen',
      GoBehavior.keepRunning => 'Weiterlaufen',
    };

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _setRoot(BuildContext context, String path) async {
    final state = context.read<AppState>();
    try {
      await Directory(path).create(recursive: true);
    } on FileSystemException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ordner nicht anlegbar: ${e.message}')));
      }
    }
    await state.updateSettings(state.settings.copyWith(cueRoot: path));
  }

  Widget _durationDropdown(Duration value, ValueChanged<Duration> onChanged) {
    final choices = {..._fadeChoices, value}.toList()..sort();
    return DropdownButton<Duration>(
      value: value,
      items: [for (final d in choices) DropdownMenuItem(value: d, child: Text(formatSeconds(d)))],
      onChanged: (d) => d == null ? null : onChanged(d),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = state.settings;
    void update(AppSettings n) => state.updateSettings(n);
    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Cue-Ordner', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(s.cueRoot ?? 'nicht gewählt'),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 8, children: [
            FilledButton.icon(
              icon: const Icon(Icons.folder_open),
              label: const Text('Ordner wählen'),
              onPressed: () async {
                final path = await FilePicker.getDirectoryPath();
                if (path != null && context.mounted) await _setRoot(context, path);
              },
            ),
            OutlinedButton(
              onPressed: () => _setRoot(context, AppSettings.suggestedCueRoot),
              child: const Text('Vorschlag: ${AppSettings.suggestedCueRoot}'),
            ),
          ]),
          if (!state.hasPermission) ...[
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: state.requestPermission, child: const Text('Zugriff auf alle Dateien erlauben')),
          ],
          const Divider(height: 40),
          Text('GO-Verhalten', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text('Was mit laufenden Playbacks passiert, wenn GO gedrückt wird. Pro Cue überschreibbar.'),
          const SizedBox(height: 12),
          SegmentedButton<GoBehavior>(
            segments: [
              for (final b in GoBehavior.values) ButtonSegment(value: b, label: Text(goBehaviorLabel(b))),
            ],
            selected: {s.goBehavior},
            onSelectionChanged: (v) => update(s.copyWith(goBehavior: v.single)),
          ),
          const SizedBox(height: 12),
          Row(children: [
            const Text('Ausblendzeit bei GO: '),
            _durationDropdown(s.goFade, (d) => update(s.copyWith(goFade: d))),
          ]),
          const Divider(height: 40),
          Text('Fade-Knöpfe', style: Theme.of(context).textTheme.titleLarge),
          Row(children: [
            const Text('Kurz: '),
            _durationDropdown(s.fadeShort, (d) => update(s.copyWith(fadeShort: d))),
            const SizedBox(width: 32),
            const Text('Lang: '),
            _durationDropdown(s.fadeLong, (d) => update(s.copyWith(fadeLong: d))),
          ]),
        ],
      ),
    );
  }
}
