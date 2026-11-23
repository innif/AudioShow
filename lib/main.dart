import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'playback/just_audio_backend.dart';
import 'playback/show_keepalive.dart';
import 'ui/home_screen.dart';
import 'ui/show_editor_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureAudioSession();
  ShowKeepAlive.init();
  final state = AppState(backend: JustAudioBackend());
  state.init();
  runApp(ChangeNotifierProvider.value(value: state, child: const AudioShowApp()));
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF3FA34D), brightness: Brightness.dark);
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF101211),
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
  );
}

class AudioShowApp extends StatelessWidget {
  const AudioShowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AudioShow',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const HomeScreen(),
      onGenerateRoute: (settings) => switch (settings.name) {
        showEditorRoute => MaterialPageRoute(
            settings: settings, builder: (_) => ShowEditorScreen(showName: settings.arguments as String)),
        _ => null,
      },
    );
  }
}
