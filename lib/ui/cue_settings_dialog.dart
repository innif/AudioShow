import 'package:material_ui/material_ui.dart';

import '../library/library.dart';
import '../model/cue_settings.dart';
import 'format.dart';
import 'settings_screen.dart' show goBehaviorLabel;

/// Edits the settings of one file. Returns null on cancel.
Future<CueSettings?> showCueSettingsDialog(BuildContext context, AudioFileRef ref, CueSettings current) =>
    showDialog<CueSettings>(context: context, builder: (_) => _CueSettingsDialog(ref, current));

class _CueSettingsDialog extends StatefulWidget {
  const _CueSettingsDialog(this.ref, this.initial);
  final AudioFileRef ref;
  final CueSettings initial;

  @override
  State<_CueSettingsDialog> createState() => _CueSettingsDialogState();
}

class _CueSettingsDialogState extends State<_CueSettingsDialog> {
  late final _startAt = TextEditingController(text: _fmt(widget.initial.startAt, zeroEmpty: true));
  late final _endAt = TextEditingController(text: _fmt(widget.initial.endAt));
  late final _fadeIn = TextEditingController(text: _fmt(widget.initial.fadeIn, zeroEmpty: true));
  late final _goFade = TextEditingController(text: _fmt(widget.initial.goFade));
  late final _note = TextEditingController(text: widget.initial.note);
  late double _volume = widget.initial.volume.toDouble();
  late GoBehavior? _go = widget.initial.goBehavior;

  static String _fmt(Duration? d, {bool zeroEmpty = false}) {
    if (d == null || (zeroEmpty && d == Duration.zero)) return '';
    final ms = d.inMilliseconds % 1000;
    final base = formatTime(d);
    return ms == 0 ? base : '$base,${(ms ~/ 100)}';
  }

  /// Empty → null (= not set); invalid → error.
  ({Duration? value, bool ok}) _parse(TextEditingController c) {
    if (c.text.trim().isEmpty) return (value: null, ok: true);
    final d = parseTime(c.text);
    return (value: d, ok: d != null);
  }

  bool get _endBeforeStart {
    final end = _parse(_endAt).value;
    return end != null && end <= (_parse(_startAt).value ?? Duration.zero);
  }

  bool get _valid => [_startAt, _endAt, _fadeIn, _goFade].every((c) => _parse(c).ok) && !_endBeforeStart;

  Widget _timeField(String label, TextEditingController c, String key, {String hint = 'm:ss', String? extraError}) {
    final ok = _parse(c).ok;
    return TextField(
      key: Key(key),
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, hintText: hint, errorText: ok ? extraError : 'Ungültige Zeit'),
      onChanged: (_) => setState(() {}),
    );
  }

  void _save() {
    final s = widget.initial.copyWith(
      startAt: _parse(_startAt).value ?? Duration.zero,
      endAt: _parse(_endAt).value,
      clearEndAt: _parse(_endAt).value == null,
      volume: _volume.round(),
      fadeIn: _parse(_fadeIn).value ?? Duration.zero,
      goBehavior: _go,
      clearGoBehavior: _go == null,
      goFade: _parse(_goFade).value,
      clearGoFade: _parse(_goFade).value == null,
      note: _note.text.trim(),
    );
    Navigator.of(context).pop(s);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.ref.artist} – ${widget.ref.fileName}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: _timeField('Start bei', _startAt, 'startAt', hint: '0:00')),
              const SizedBox(width: 16),
              Expanded(child: _timeField('Ende bei (optional)', _endAt, 'endAt',
                  hint: 'bis Dateiende', extraError: _endBeforeStart ? 'Ende muss nach dem Start liegen' : null)),
            ]),
            const SizedBox(height: 16),
            Text('Lautstärke: ${_volume.round()} %'),
            Slider(
              key: const Key('volume'),
              value: _volume,
              min: 0,
              max: 100,
              divisions: 20,
              label: '${_volume.round()} %',
              onChanged: (v) => setState(() => _volume = v),
            ),
            _timeField('Fade-in (Sekunden)', _fadeIn, 'fadeIn', hint: '0'),
            const SizedBox(height: 16),
            Row(children: [
              const Text('Bei nächstem GO: '),
              const SizedBox(width: 8),
              DropdownButton<GoBehavior?>(
                key: const Key('goBehavior'),
                value: _go,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Standard')),
                  for (final b in GoBehavior.values) DropdownMenuItem(value: b, child: Text(goBehaviorLabel(b))),
                ],
                onChanged: (v) => setState(() => _go = v),
              ),
            ]),
            _timeField('Ausblendzeit bei GO (optional)', _goFade, 'goFade', hint: 'Standard'),
            const SizedBox(height: 8),
            TextField(
              key: const Key('note'),
              controller: _note,
              decoration: const InputDecoration(labelText: 'Notiz'),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
        FilledButton(onPressed: _valid ? _save : null, child: const Text('Speichern')),
      ],
    );
  }
}
