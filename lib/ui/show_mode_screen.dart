import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../playback/show_engine.dart';
import '../playback/show_keepalive.dart';
import 'format.dart';

const _goGreen = Color(0xFF2E9E44);
const _stopRed = Color(0xFFC62828);
const _tileHeight = 72.0;

/// The screen used during the performance: GO, Stop All, fades, seeking.
class ShowModeScreen extends StatefulWidget {
  const ShowModeScreen({super.key, required this.showName, this.keepAwake = true});
  final String showName;

  /// Wakelock + foreground service; disabled in widget tests.
  final bool keepAwake;

  @override
  State<ShowModeScreen> createState() => _ShowModeScreenState();
}

class _ShowModeScreenState extends State<ShowModeScreen> {
  late final AppState _state = context.read<AppState>();
  late final ShowEngine _engine = ShowEngine(backend: _state.backend, settings: _state.settings);
  final _scroll = ScrollController();
  bool _loaded = false;
  String? _error;
  int? _lastNext;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _engine.addListener(_onEngine);
    _load();
    if (widget.keepAwake) unawaited(ShowKeepAlive.enter(widget.showName));
  }

  Future<void> _load() async {
    try {
      final show = await _state.showStore!.load(widget.showName);
      final cues = await _state.resolve(show);
      if (!mounted) return;
      _engine.setCues(cues);
      setState(() => _loaded = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Show konnte nicht geladen werden: $e');
    }
  }

  void _onEngine() {
    if (!mounted) return;
    final next = _engine.nextIndex;
    if (next != _lastNext) {
      _lastNext = next;
      if (next != null && _scroll.hasClients) {
        final target = (next - 1).clamp(0, 1 << 30) * _tileHeight;
        _scroll.animateTo(target.clamp(0, _scroll.position.maxScrollExtent),
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    }
    final err = _engine.lastError;
    if (err != null && err != _lastError) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
    _lastError = err;
  }

  @override
  void dispose() {
    _engine.removeListener(_onEngine);
    _engine.dispose();
    _scroll.dispose();
    if (widget.keepAwake) unawaited(ShowKeepAlive.leave());
    super.dispose();
  }

  Future<bool> _confirmLeave() async {
    if (_engine.running.isEmpty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Show-Modus verlassen?'),
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
        appBar: AppBar(title: Text('Show ${widget.showName}'), toolbarHeight: 48),
        body: _error != null
            ? Center(child: Text(_error!))
            : !_loaded
                ? const Center(child: CircularProgressIndicator())
                : ListenableBuilder(
                    listenable: _engine,
                    builder: (context, _) => Column(children: [
                      for (final r in _engine.running) _RunningRow(key: ValueKey('running-${r.id}'), engine: _engine, cue: r),
                      if (_engine.running.isNotEmpty) const Divider(height: 1),
                      Expanded(child: _cueList()),
                      _controls(),
                    ]),
                  ),
      ),
    );
  }

  Widget _cueList() {
    final cues = _engine.cues;
    final runningIdx = _engine.running.map((r) => r.showIndex).toSet();
    return ListView.builder(
      controller: _scroll,
      itemExtent: _tileHeight,
      itemCount: cues.length + 1,
      itemBuilder: (context, i) {
        if (i == cues.length) {
          return Center(
            child: Text(_engine.nextIndex == null ? 'Ende der Show' : '— Ende der Liste —',
                style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          );
        }
        final c = cues[i];
        final isNext = i == _engine.nextIndex;
        final isRunning = runningIdx.contains(i);
        final scheme = Theme.of(context).colorScheme;
        Widget? trailing;
        if (isNext) {
          trailing = Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: _goGreen, borderRadius: BorderRadius.circular(6)),
            child: const Text('NÄCHSTER', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          );
        } else if (isRunning) {
          trailing = Text('läuft', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.bold));
        } else if (_engine.played.contains(i)) {
          trailing = Icon(Icons.check, color: scheme.outline);
        }
        return ListTile(
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
          subtitle: _subtitle(c),
          trailing: trailing,
          onTap: () => _engine.select(i),
        );
      },
    );
  }

  Widget? _subtitle(ResolvedCue c) {
    final parts = [
      if (c.missing) 'Datei fehlt – wird übersprungen',
      if (c.settings.startAt > Duration.zero) 'ab ${formatTime(c.settings.startAt)}',
      if (c.settings.note.isNotEmpty) c.settings.note,
    ];
    return parts.isEmpty ? null : Text(parts.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis);
  }

  Widget _controls() {
    final s = _state.settings;
    final canGo = _engine.nextIndex != null;
    const bigText = TextStyle(fontSize: 20, fontWeight: FontWeight.bold);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: 120,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            OutlinedButton(
              onPressed: () => _engine.fadeAll(s.fadeShort),
              child: Text('Fade ${formatSeconds(s.fadeShort)}', style: bigText),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: () => _engine.fadeAll(s.fadeLong),
              child: Text('Fade ${formatSeconds(s.fadeLong)}', style: bigText),
            ),
            const SizedBox(width: 12),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _stopRed, foregroundColor: Colors.white),
              onPressed: _engine.stopAll,
              child: const Text('STOP ALL', style: bigText),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _goGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: canGo ? _engine.go : null,
                child: const Text('GO', style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _RunningRow extends StatelessWidget {
  const _RunningRow({super.key, required this.engine, required this.cue});
  final ShowEngine engine;
  final RunningCue cue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('running-row'),
      color: scheme.primaryContainer.withValues(alpha: cue.fadingOut ? 0.15 : 0.35),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: StreamBuilder<Duration>(
        stream: cue.voice.positionStream,
        initialData: cue.position,
        builder: (context, snap) {
          final pos = snap.data ?? Duration.zero;
          final dur = cue.duration;
          return Row(children: [
            Icon(cue.fadingOut ? Icons.trending_down : Icons.play_arrow),
            const SizedBox(width: 8),
            SizedBox(
              width: 260,
              child: Text('${cue.showIndex + 1}  ${cue.cue.artist} – ${cue.cue.fileName}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SeekBar(
                key: const ValueKey('seekbar'),
                position: pos,
                duration: dur,
                onSeek: (d) => engine.seek(cue, d),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 150,
              child: Text(
                dur == null ? formatTime(pos) : '${formatTime(pos)} / ${formatTime(dur)}\n−${formatTime(dur - pos)}',
                textAlign: TextAlign.right,
                style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ),
            IconButton(
              tooltip: 'Von Anfang',
              iconSize: 32,
              icon: const Icon(Icons.replay),
              onPressed: () => engine.restart(cue),
            ),
          ]);
        },
      ),
    );
  }
}

/// Progress bar that seeks only on a horizontal drag; plain taps are ignored
/// so a stray touch during the show cannot jump.
class _SeekBar extends StatefulWidget {
  const _SeekBar({super.key, required this.position, required this.duration, required this.onSeek});
  final Duration position;
  final Duration? duration;
  final ValueChanged<Duration> onSeek;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  /// A drag must move at least this far before it counts as a seek.
  static const _minMove = 12.0;
  double? _drag;
  double _startX = 0;
  bool _moved = false;

  double _fraction(Offset local, double width) => (local.dx / width).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final dur = widget.duration;
    final scheme = Theme.of(context).colorScheme;
    final progress = dur == null || dur == Duration.zero
        ? 0.0
        : (widget.position.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
    final shown = _drag ?? progress;
    return LayoutBuilder(builder: (context, c) {
      final width = c.maxWidth;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: dur == null
            ? null
            : (d) {
                _startX = d.localPosition.dx;
                _moved = false;
              },
        onHorizontalDragUpdate: dur == null
            ? null
            : (d) {
                if (!_moved && (d.localPosition.dx - _startX).abs() < _minMove) return;
                _moved = true;
                setState(() => _drag = _fraction(d.localPosition, width));
              },
        onHorizontalDragEnd: dur == null
            ? null
            : (_) {
                final f = _drag;
                setState(() => _drag = null);
                if (_moved && f != null) widget.onSeek(Duration(milliseconds: (dur.inMilliseconds * f).round()));
                _moved = false;
              },
        onHorizontalDragCancel: () => setState(() => _drag = null),
        child: SizedBox(
          height: 48,
          child: Stack(alignment: Alignment.centerLeft, children: [
            Container(height: 10, decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(5))),
            FractionallySizedBox(
              widthFactor: shown,
              child: Container(height: 10, decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(5))),
            ),
            Positioned(
              left: (width - 24) * shown,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: _drag != null ? scheme.tertiary : scheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            if (_drag != null && dur != null)
              Positioned(
                left: ((width - 60) * shown).clamp(0, width),
                top: 0,
                child: Text(formatTime(Duration(milliseconds: (dur.inMilliseconds * _drag!).round())),
                    style: TextStyle(color: scheme.tertiary, fontWeight: FontWeight.bold)),
              ),
          ]),
        ),
      );
    });
  }
}
