import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../library/library.dart';
import '../library/search.dart';
import 'cue_settings_dialog.dart';
import 'format.dart';

enum _Sort { alpha, recent }

/// Searchable archive of all playbacks in the cue folder.
class LibraryPane extends StatefulWidget {
  const LibraryPane({super.key, required this.onAdd});
  final void Function(AudioFileRef) onAdd;

  @override
  State<LibraryPane> createState() => _LibraryPaneState();
}

class _LibraryPaneState extends State<LibraryPane> {
  final _query = TextEditingController();
  _Sort _sort = _Sort.alpha;
  Future<void> _togglePreview(AppState state, AudioFileRef ref) async {
    try {
      await state.togglePreview(ref);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Vorhören fehlgeschlagen: $e')));
      }
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _editSettings(AppState state, AudioFileRef ref) async {
    final result = await showCueSettingsDialog(context, ref, state.settingsOf(ref));
    if (result != null) await state.saveCueSettings(ref, result);
  }

  Future<void> _import(AppState state) async {
    final picked = await FilePicker.pickFiles(dialogTitle: 'Playbacks importieren', type: FileType.audio);
    if (picked.isEmpty || !mounted) return;
    final artist = await _askArtist(state);
    if (artist == null || !mounted) return;
    final tmp = await Directory.systemTemp.createTemp('import');
    try {
      final files = <File>[];
      for (final f in picked) {
        if (f.path != null) {
          files.add(File(f.path!));
        } else {
          final target = p.join(tmp.path, f.name);
          await f.xFile.saveTo(target);
          files.add(File(target));
        }
      }
      final refs = await state.importFiles(artist, files);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${refs.length} Datei(en) nach „$artist“ importiert')));
        _query.text = artist;
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import fehlgeschlagen: $e')));
      }
    } finally {
      unawaited(tmp.delete(recursive: true).catchError((_) => tmp));
    }
  }

  Future<String?> _askArtist(AppState state) {
    final names = state.library.artists.map((a) => a.name).toList();
    String value = '';
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Für welche*n Künstler*in?'),
        content: SizedBox(
          width: 420,
          child: Autocomplete<String>(
            optionsBuilder: (v) {
              final q = normalizeForSearch(v.text);
              return names.where((n) => normalizeForSearch(n).contains(q));
            },
            onSelected: (v) => value = v,
            fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
              controller: controller,
              focusNode: focus,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name (vorhanden oder neu)'),
              onChanged: (v) => value = v,
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.pop(c, value.trim().isEmpty ? null : value.trim()),
            child: const Text('Importieren'),
          ),
        ],
      ),
    );
  }

  Widget _fileTile(AppState state, AudioFileRef ref, {required bool showArtist}) {
    final s = state.settingsOf(ref);
    final details = [
      if (showArtist) ref.artist,
      if (s.startAt > Duration.zero) 'ab ${formatTime(s.startAt)}',
      if (s.volume != 100) '${s.volume} %',
      if (s.note.isNotEmpty) s.note,
    ].join(' · ');
    final playing = ref == state.previewRef;
    return ListTile(
      title: Text(ref.fileName),
      subtitle: details.isEmpty ? null : Text(details),
      onTap: () => widget.onAdd(ref),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: playing ? 'Vorhören stoppen' : 'Vorhören',
          icon: Icon(playing ? Icons.stop_circle_outlined : Icons.headphones),
          onPressed: () => _togglePreview(state, ref),
        ),
        IconButton(
          tooltip: 'Einstellungen',
          icon: const Icon(Icons.tune),
          onPressed: () => _editSettings(state, ref),
        ),
        IconButton(
          tooltip: 'Zur Show hinzufügen',
          icon: const Icon(Icons.add_circle),
          onPressed: () => widget.onAdd(ref),
        ),
      ]),
    );
  }

  List<Artist> _sortedArtists(Library lib, Map<String, DateTime> lastUsed) {
    final artists = List.of(lib.artists);
    if (_sort == _Sort.recent) {
      DateTime last(Artist a) => a.files
          .map((f) => lastUsed[f.relPath])
          .whereType<DateTime>()
          .fold(DateTime(0), (m, d) => d.isAfter(m) ? d : m);
      artists.sort((a, b) {
        final c = last(b).compareTo(last(a));
        return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    }
    return artists;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final lib = state.library;
    final searching = _query.text.trim().isNotEmpty;
    Widget list;
    if (searching) {
      final results = searchLibrary(lib, _query.text);
      list = results.isEmpty
          ? const Center(child: Text('Nichts gefunden'))
          : ListView.builder(
              itemCount: results.length,
              itemBuilder: (_, i) => _fileTile(state, results[i], showArtist: true),
            );
    } else {
      final artists = _sortedArtists(lib, state.lastUsed);
      list = artists.isEmpty
          ? const Center(child: Text('Der Cue-Ordner ist leer. Importiere Playbacks oder lege Ordner an.'))
          : ListView.builder(
              itemCount: artists.length,
              itemBuilder: (_, i) {
                final a = artists[i];
                return ExpansionTile(
                  key: PageStorageKey('artist-${a.name}'),
                  title: Text(a.name),
                  subtitle: Text('${a.files.length} Datei(en)'),
                  children: [for (final f in a.files) _fileTile(state, f, showArtist: false)],
                );
              },
            );
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: TextField(
          key: const Key('librarySearch'),
          controller: _query,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Künstler*in oder Datei suchen…',
            border: const OutlineInputBorder(),
            suffixIcon: searching
                ? IconButton(
                    tooltip: 'Suche löschen',
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(_query.clear),
                  )
                : null,
          ),
          onChanged: (_) => setState(() {}),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          SegmentedButton<_Sort>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _Sort.alpha, label: Text('A–Z')),
              ButtonSegment(value: _Sort.recent, label: Text('Zuletzt')),
            ],
            selected: {_sort},
            onSelectionChanged: (v) => setState(() => _sort = v.single),
          ),
          const Spacer(),
          IconButton(tooltip: 'Ordner neu einlesen', icon: const Icon(Icons.refresh), onPressed: state.rescan),
          TextButton.icon(
            icon: const Icon(Icons.file_download),
            label: const Text('Importieren'),
            onPressed: () => _import(state),
          ),
        ]),
      ),
      Expanded(child: list),
    ]);
  }
}
