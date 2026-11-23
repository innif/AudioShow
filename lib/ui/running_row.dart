import 'package:material_ui/material_ui.dart';

import '../playback/show_engine.dart';
import 'format.dart';

class RunningRow extends StatelessWidget {
  const RunningRow({super.key, required this.engine, required this.cue});
  final ShowEngine engine;
  final RunningCue cue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('running-row'),
      color: scheme.primaryContainer.withValues(alpha: cue.fadingOut ? 0.15 : 0.35),
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: StreamBuilder<Duration>(
        stream: cue.voice.positionStream,
        initialData: cue.position,
        builder: (context, snap) {
          final pos = snap.data ?? Duration.zero;
          final dur = cue.duration;
          const time = TextStyle(fontSize: 16, fontFeatures: [FontFeature.tabularFigures()]);
          return Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Icon(cue.fadingOut ? Icons.trending_down : Icons.play_arrow),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${cue.cue.artist} – ${cue.cue.fileName}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18)),
              ),
              Text(dur == null ? formatTime(pos) : '${formatTime(pos)} / ${formatTime(dur)}', style: time),
              if (dur != null) ...[
                const SizedBox(width: 12),
                Text('−${formatTime(dur - pos)}', style: time.copyWith(fontWeight: FontWeight.bold)),
              ],
              const SizedBox(width: 12),
              _JumpButton(label: '−10 s', tooltip: '10 s zurück', onPressed: () => engine.skip(cue, const Duration(seconds: -10))),
              const SizedBox(width: 6),
              _JumpButton(label: '+10 s', tooltip: '10 s vor', onPressed: () => engine.skip(cue, const Duration(seconds: 10))),
              IconButton(
                tooltip: 'Von Anfang',
                iconSize: 30,
                icon: const Icon(Icons.replay),
                onPressed: () => engine.restart(cue),
              ),
            ]),
            SeekBar(
              key: const ValueKey('seekbar'),
              position: pos,
              duration: dur,
              onSeek: (d) => engine.seek(cue, d),
            ),
          ]);
        },
      ),
    );
  }
}

class _JumpButton extends StatelessWidget {
  const _JumpButton({required this.label, required this.tooltip, required this.onPressed});
  final String label;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(64, 40),
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          onPressed: onPressed,
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      );
}

/// Progress bar that seeks only on a horizontal drag; plain taps are ignored
/// so a stray touch during the show cannot jump.
class SeekBar extends StatefulWidget {
  const SeekBar({super.key, required this.position, required this.duration, required this.onSeek});
  final Duration position;
  final Duration? duration;
  final ValueChanged<Duration> onSeek;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
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
