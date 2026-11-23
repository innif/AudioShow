import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../library/library.dart';
import '../model/show.dart';
import '../playback/show_engine.dart';
import '../playback/show_keepalive.dart';
import 'cue_settings_dialog.dart';
import 'format.dart';
import 'library_pane.dart';
import 'running_row.dart';

const _goGreen = Color(0xFF2E9E44);
const _stopRed = Color(0xFFC62828);
const _rowHeight = 72.0;

/// One view to build and run a show. The edit switch only shows/hides the
/// editing tools; GO, STOP ALL, fades and cue selection always work.
class ShowScreen extends StatefulWidget {
  const ShowScreen({super.key, required this.showName, this.keepAwake = true});
  final String showName;

  /// Wakelock + foreground service; disabled in widget tests.
  final bool keepAwake;

  @override
  State<ShowScreen> createState() => _ShowScreenState();
}

class _ShowScreenState extends State<ShowScreen> {
  late final AppState _state = context.read<AppState>();
  late final ShowEngine _engine = ShowEngine(backend: _state.backend, settings: _state.settings);
  final _scroll = ScrollController();

  Show? _show;
  List<int> _ids = const []; // stable entry ids, parallel to _show.entries
  int _nextEntryId = 0;
  int _version = 0; // guards against out-of-order async resolves
  bool _edit = true;
  String? _error;
  int? _lastNext;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _engine.addListener(_onEngine);
    _state.addListener(_onAppState);
    _load();
    if (widget.keepAwake) unawaited(ShowKeepAlive.enter(widget.showName));
  }

  @override
  void dispose() {
    _state.removeListener(_onAppState);
    _engine.removeListener(_onEngine);
    _engine.dispose();
    _scroll.dispose();
    _state.stopPreview();
    if (widget.keepAwake) unawaited(ShowKeepAlive.leave());
    super.dispose();
  }

  // --- data ---

  Future<void> _load() async {
    try {
      final show = await _state.showStore!.load(widget.showName);
      final ids = [for (var i = 0; i < show.entries.length; i++) i];
      _nextEntryId = ids.length;
      final cues = await _state.resolve(show, ids: ids);
      if (!mounted) return;
      _engine.setCues(cues);
      setState(() {
        _show = show;
        _ids = ids;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Show konnte nicht geladen werden: $e');
    }
  }

  bool _resyncing = false;
  bool _resyncAgain = false;

  /// Re-reads files/settings for the current list (after settings or library
  /// changes) and hands it to the engine. Never interrupts playback.
  Future<void> _resync() async {
    if (_show == null) return;
    if (_resyncing) {
      _resyncAgain = true;
      return;
    }
    _resyncing = true;
    try {
      do {
        _resyncAgain = false;
        final version = _version;
        final cues = await _state.resolve(_show!, ids: _ids);
        if (!mounted) return;
        if (version != _version) {
          _resyncAgain = true; // list was edited meanwhile: resolve the new one
          continue;
        }
        _engine.updateCues(cues);
      } while (_resyncAgain && mounted);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cue-Ordner nicht lesbar: $e')));
      }
    } finally {
      _resyncing = false;
    }
  }

  void _onAppState() => _resync();

  /// Applies an edit synchronously (list + engine), then saves in the background.
  void _apply(List<String> entries, List<int> ids, List<ResolvedCue> cues) {
    _version++;
    setState(() {
      _show = _show!.copyWith(entries: entries);
      _ids = ids;
    });
    _engine.updateCues(cues);
    unawaited(_save(_show!));
  }

  Future<void> _save(Show show) async {
    try {
      await _state.showStore!.save(show);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Speichern fehlgeschlagen: $e')));
      }
    }
  }

  void _add(AudioFileRef ref) {
    final cue = ResolvedCue(
      id: _nextEntryId++,
      relPath: ref.relPath,
      absPath: _state.library.fileFor(ref).path,
      settings: _state.settingsOf(ref),
    );
    _apply([..._show!.entries, ref.relPath], [..._ids, cue.id], [..._engine.cues, cue]);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('${ref.artist} – ${ref.fileName} hinzugefügt'),
        duration: const Duration(seconds: 1),
      ));
  }

  void _remove(int entryId) {
    final i = _ids.indexOf(entryId);
    if (i < 0) return; // already gone (e.g. double tap)
    _apply([..._show!.entries]..removeAt(i), [..._ids]..removeAt(i),
        _engine.cues.where((c) => c.id != entryId).toList());
  }

  void _reorder(int from, int to) {
    final e = [..._show!.entries], ids = [..._ids], cues = [..._engine.cues];
    e.insert(to, e.removeAt(from));
    ids.insert(to, ids.removeAt(from));
    cues.insert(to, cues.removeAt(from));
    _apply(e, ids, cues);
  }

  Future<void> _editSettings(int i) async {
    final c = _engine.cues[i];
    if (c.missing) return;
    final ref = AudioFileRef.parse(c.relPath);
    final result = await showCueSettingsDialog(context, ref, c.settings);
    if (result == null) return;
    try {
      await _state.saveCueSettings(ref, result); // notifies → _resync
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Speichern fehlgeschlagen: $e')));
      }
    }
  }

  // --- engine feedback ---

  void _onEngine() {
    if (!mounted) return;
    final next = _engine.nextIndex;
    if (next != _lastNext) {
      _lastNext = next;
      if (next != null && _scroll.hasClients) {
        final target = ((next - 1).clamp(0, 1 << 30) * _rowHeight).toDouble();
        _scroll.animateTo(target.clamp(0.0, _scroll.position.maxScrollExtent),
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    }
    final err = _engine.lastError;
    if (err != null && err != _lastError) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
    _lastError = err;
  }

  void _go() {
    _state.stopPreview(); // a preview must never play under the show
    _engine.go();
  }

  void _setEdit(bool v) {
    if (!v) _state.stopPreview();
    setState(() => _edit = v);
  }

  Future<bool> _confirmLeave() async {
    if (_engine.running.isEmpty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Show verlassen?'),
        content: const Text('Laufende Playbacks werden gestoppt.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Weiter spielen')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Stoppen und verlassen')),
        ],
      ),
    );
    if (ok == true) _engine.stopAll();
    return ok == true;
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmLeave()) nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 52,
          title: Text('Show ${widget.showName}'),
          actions: [
            if (_edit && MediaQuery.sizeOf(context).width < 900) ...[
              FilledButton.tonalIcon(
                icon: const Icon(Icons.library_music),
                label: const Text('Archiv'),
                onPressed: _openArchiveSheet,
              ),
              const SizedBox(width: 16),
            ],
            const Text('Bearbeiten'),
            const SizedBox(width: 8),
            Switch(key: const Key('editSwitch'), value: _edit, onChanged: _setEdit),
            const SizedBox(width: 16),
          ],
        ),
        body: _error != null
            ? Center(child: Text(_error!))
            : _show == null
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(builder: (context, c) {
                    final showPane = ListenableBuilder(listenable: _engine, builder: (context, _) => _showPane());
                    if (!_edit) return showPane;
                    if (c.maxWidth < 900) return showPane;
                    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Expanded(flex: 2, child: LibraryPane(onAdd: _add)),
                      const VerticalDivider(width: 1),
                      Expanded(flex: 3, child: showPane),
                    ]);
                  }),
      ),
    );
  }

  void _openArchiveSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => FractionallySizedBox(heightFactor: 0.85, child: LibraryPane(onAdd: _add)),
    );
  }

  Widget _showPane() {
    return Column(children: [
      for (final r in _engine.running) RunningRow(key: ValueKey('running-${r.id}'), engine: _engine, cue: r),
      if (_engine.running.isNotEmpty) const Divider(height: 1),
      Expanded(child: _cueList()),
      _controls(),
    ]);
  }

  Widget _cueList() {
    final cues = _engine.cues;
    final scheme = Theme.of(context).colorScheme;
    final endText = Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Text(
          cues.isEmpty
              ? (_edit ? 'Noch leer. Füge Playbacks aus dem Archiv hinzu.' : 'Noch leer. Schalte „Bearbeiten“ ein.')
              : _engine.nextIndex == null
                  ? 'Ende der Show'
                  : '— Ende der Liste —',
          style: TextStyle(color: scheme.outline),
        ),
      ),
    );
    return ReorderableListView.builder(
      scrollController: _scroll,
      buildDefaultDragHandles: false,
      itemCount: cues.length,
      onReorderItem: _reorder,
      footer: endText,
      itemBuilder: (context, i) => _cueTile(cues[i], i),
    );
  }

  Widget _cueTile(ResolvedCue c, int i) {
    final scheme = Theme.of(context).colorScheme;
    final isNext = i == _engine.nextIndex;
    final isRunning = _engine.isRunning(i);
    Widget? status;
    if (isNext) {
      status = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: _goGreen, borderRadius: BorderRadius.circular(6)),
        child: const Text('NÄCHSTER', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
      );
    } else if (isRunning) {
      status = Text('läuft', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.bold));
    } else if (_engine.isPlayed(i)) {
      status = Icon(Icons.check, color: scheme.outline);
    }
    final details = [
      if (c.missing) 'Datei fehlt – wird übersprungen',
      if (c.settings.startAt > Duration.zero) 'ab ${formatTime(c.settings.startAt)}',
      if (c.settings.endAt != null) 'bis ${formatTime(c.settings.endAt!)}',
      if (c.settings.volume != 100) '${c.settings.volume} %',
      if (c.settings.note.isNotEmpty) c.settings.note,
    ].join(' · ');
    return SizedBox(
      key: ValueKey('entry-${c.id}'),
      height: _rowHeight,
      child: Center(
        child: ListTile(
          selected: isNext,
          selectedTileColor: _goGreen.withValues(alpha: 0.15),
          leading: c.missing
              ? const Icon(Icons.warning_amber, color: Colors.orange)
              : CircleAvatar(
                  radius: 16,
                  backgroundColor: isRunning ? scheme.primary : scheme.surfaceContainerHighest,
                  child: Text('${i + 1}', style: const TextStyle(fontSize: 14)),
                ),
          title: Text('${c.artist} – ${c.fileName}', style: const TextStyle(fontSize: 20)),
          subtitle: details.isEmpty
              ? null
              : Text(details,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: c.missing ? const TextStyle(color: Colors.orange) : null),
          onTap: () => _engine.select(i),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            ?status,
            if (_edit) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Einstellungen',
                icon: const Icon(Icons.tune),
                onPressed: c.missing ? null : () => _editSettings(i),
              ),
              IconButton(
                tooltip: 'Entfernen',
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () => _remove(c.id),
              ),
              ReorderableDragStartListener(
                index: i,
                child: Padding(
                  key: ValueKey('handle-$i'),
                  padding: const EdgeInsets.all(12),
                  child: const Icon(Icons.drag_handle),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _controls() {
    final s = _state.settings;
    final canGo = _engine.nextIndex != null;
    final h = _edit ? 72.0 : 120.0;
    final bigText = TextStyle(fontSize: _edit ? 16 : 20, fontWeight: FontWeight.bold);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.all(_edit ? 8 : 12),
        child: SizedBox(
          height: h,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            OutlinedButton(
              onPressed: () => _engine.fadeAll(s.fadeShort),
              child: Text('Fade ${formatSeconds(s.fadeShort)}', style: bigText),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => _engine.fadeAll(s.fadeLong),
              child: Text('Fade ${formatSeconds(s.fadeLong)}', style: bigText),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _stopRed, foregroundColor: Colors.white),
              onPressed: _engine.stopAll,
              child: Text('STOP ALL', style: bigText),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: FilledButton(
                key: const Key('goButton'),
                style: FilledButton.styleFrom(
                  backgroundColor: _goGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: canGo ? _go : null,
                child: Text('GO', style: TextStyle(fontSize: _edit ? 32 : 48, fontWeight: FontWeight.w900)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
