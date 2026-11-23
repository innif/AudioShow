import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../library/library.dart';
import '../model/show.dart';
import '../playback/show_engine.dart';
import 'cue_settings_dialog.dart';
import 'format.dart';
import 'library_pane.dart';

/// Route name for show mode; argument is the show name.
const showModeRoute = '/showmode';

String cueDetails(ResolvedCue c) {
  final s = c.settings;
  return [
    if (c.missing) 'Datei fehlt',
    if (s.startAt > Duration.zero) 'ab ${formatTime(s.startAt)}',
    if (s.endAt != null) 'bis ${formatTime(s.endAt!)}',
    if (s.volume != 100) '${s.volume} %',
    if (s.note.isNotEmpty) s.note,
  ].join(' · ');
}

class ShowEditorScreen extends StatefulWidget {
  const ShowEditorScreen({super.key, required this.showName});
  final String showName;

  @override
  State<ShowEditorScreen> createState() => _ShowEditorScreenState();
}

class _ShowEditorScreenState extends State<ShowEditorScreen> {
  Show? _show;
  List<ResolvedCue> _cues = const [];
  String? _error;
  late final AppState _state = context.read<AppState>();

  @override
  void initState() {
    super.initState();
    _load();
    _state.addListener(_refresh);
  }

  @override
  void dispose() {
    _state.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final show = await _state.showStore!.load(widget.showName);
      final cues = await _state.resolve(show);
      if (mounted) setState(() => (_show = show, _cues = cues));
    } catch (e) {
      if (mounted) setState(() => _error = 'Show konnte nicht geladen werden: $e');
    }
  }

  /// Re-resolve when settings or the library change.
  Future<void> _refresh() async {
    final show = _show;
    if (show == null) return;
    final cues = await _state.resolve(show);
    if (mounted && identical(show, _show)) setState(() => _cues = cues);
  }

  Future<void> _update(List<String> entries) async {
    final show = _show!.copyWith(entries: entries);
    setState(() => _show = show);
    await _state.showStore!.save(show);
    final cues = await _state.resolve(show);
    if (mounted && identical(show, _show)) setState(() => _cues = cues);
  }

  void _add(AudioFileRef ref) {
    _update([..._show!.entries, ref.relPath]);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('${ref.artist} – ${ref.fileName} hinzugefügt'), duration: const Duration(seconds: 1)));
  }

  void _remove(int i) => _update([..._show!.entries]..removeAt(i));

  void _reorder(int from, int to) {
    final e = [..._show!.entries];
    e.insert(to, e.removeAt(from));
    _update(e);
  }

  Future<void> _edit(int i) async {
    final c = _cues[i];
    if (c.missing) return;
    final ref = AudioFileRef.parse(c.relPath);
    final result = await showCueSettingsDialog(context, ref, c.settings);
    if (result != null) await _state.saveCueSettings(ref, result);
  }

  Widget _showList() {
    final show = _show!;
    if (show.entries.isEmpty) {
      return const Center(child: Text('Noch leer. Füge Playbacks aus dem Archiv hinzu.'));
    }
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: show.entries.length,
      onReorderItem: _reorder,
      itemBuilder: (context, i) {
        final rel = show.entries[i];
        final cue = i < _cues.length && _cues[i].relPath == rel ? _cues[i] : null;
        final ref = AudioFileRef.parse(rel);
        final details = cue == null ? '' : cueDetails(cue);
        final missing = cue?.missing ?? false;
        return ListTile(
          key: ValueKey('entry-$i-$rel'),
          minTileHeight: 64,
          leading: missing ? const Icon(Icons.warning_amber, color: Colors.orange) : null,
          title: Text('${i + 1}  ${ref.artist} – ${ref.fileName}'),
          subtitle: details.isEmpty ? null : Text(details, style: missing ? const TextStyle(color: Colors.orange) : null),
          onTap: () => _edit(i),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(tooltip: 'Entfernen', icon: const Icon(Icons.remove_circle_outline), onPressed: () => _remove(i)),
            ReorderableDragStartListener(
              index: i,
              child: Padding(
                key: ValueKey('handle-$i'),
                padding: const EdgeInsets.all(12),
                child: const Icon(Icons.drag_handle),
              ),
            ),
          ]),
        );
      },
    );
  }

  void _openArchiveSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => FractionallySizedBox(heightFactor: 0.85, child: LibraryPane(onAdd: _add)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPlayable = _cues.any((c) => !c.missing);
    return Scaffold(
      appBar: AppBar(
        title: Text('Show ${widget.showName}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('Show starten'),
              onPressed: hasPlayable
                  ? () async {
                      _state.stopPreview();
                      await Navigator.of(context).pushNamed(showModeRoute, arguments: widget.showName);
                      _refresh();
                    }
                  : null,
            ),
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : _show == null
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(builder: (context, c) {
                  if (c.maxWidth < 900) {
                    return Scaffold(
                      body: _showList(),
                      floatingActionButton: FloatingActionButton.extended(
                        icon: const Icon(Icons.library_music),
                        label: const Text('Aus Archiv hinzufügen'),
                        onPressed: _openArchiveSheet,
                      ),
                    );
                  }
                  return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(flex: 2, child: LibraryPane(onAdd: _add)),
                    const VerticalDivider(width: 1),
                    Expanded(flex: 3, child: _showList()),
                  ]);
                }),
    );
  }
}
