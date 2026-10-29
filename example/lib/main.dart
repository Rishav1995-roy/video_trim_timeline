import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:video_trim_timeline/video_trim_timeline.dart';

import 'synthetic_video.dart';

void main() => runApp(const ExampleApp());

/// Example app. The "video" is synthetic; see synthetic_video.dart. Replace
/// [SyntheticThumbnails] with your frame extractor and the simulated adapter
/// with one wrapping your player (snippet in the README).
class ExampleApp extends StatefulWidget {
  const ExampleApp({
    super.key,
    this.dark = false,
    this.initialTab = 0,
    this.thumbnailCache,
    this.initialShape = TrimHandleShape.rounded,
    this.initialAccent = const Color(0xFFFFC107),
  });

  final bool dark;
  final int initialTab;

  /// Supply a pre-filled cache (used to render the demo GIF in tests).
  final ThumbnailCache? thumbnailCache;
  final TrimHandleShape initialShape;
  final Color initialAccent;

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  late bool _dark = widget.dark;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'video_trim_timeline',
      debugShowCheckedModeBanner: false,
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: HomePage(
        initialTab: widget.initialTab,
        thumbnailCache: widget.thumbnailCache,
        initialShape: widget.initialShape,
        initialAccent: widget.initialAccent,
        dark: _dark,
        onDark: (v) => setState(() => _dark = v),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.dark,
    required this.onDark,
    this.initialTab = 0,
    this.thumbnailDelay = const Duration(milliseconds: 120),
    this.thumbnailCache,
    this.initialShape = TrimHandleShape.rounded,
    this.initialAccent = const Color(0xFFFFC107),
  });

  final ThumbnailCache? thumbnailCache;
  final TrimHandleShape initialShape;
  final Color initialAccent;

  final bool dark;
  final ValueChanged<bool> onDark;
  final int initialTab;
  final Duration thumbnailDelay;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  static const video = SyntheticVideo();
  late final controller = TrimController(
    totalDuration: video.duration,
    minDuration: const Duration(seconds: 2),
    maxDuration: const Duration(seconds: 30),
    initialStart: const Duration(seconds: 6),
    initialEnd: const Duration(seconds: 26),
    haptics: TrimHaptics.system(),
  );
  final adapter = SimulatedPlaybackAdapter();
  late final ThumbnailCache cache = widget.thumbnailCache ??
      ThumbnailCache(SyntheticThumbnails(video, delay: widget.thumbnailDelay));
  late final Ticker ticker;
  Duration _last = Duration.zero;
  late int tab = widget.initialTab;

  // customization state
  TrimHandleShape shape = TrimHandleShape.rounded;
  Color accent = const Color(0xFFFFC107);
  double height = 64;
  bool rtl = false;
  bool hapticsOn = true;

  @override
  void initState() {
    super.initState();
    shape = widget.initialShape;
    accent = widget.initialAccent;
    controller.attachPlayback(adapter);
    ticker = createTicker((elapsed) {
      adapter.advance(elapsed - _last);
      _last = elapsed;
    })
      ..start();
  }

  @override
  void dispose() {
    ticker.dispose();
    controller.dispose();
    adapter.dispose();
    super.dispose();
  }

  TrimTimelineStyle _style(BuildContext context) =>
      TrimTimelineStyle.fromColorScheme(Theme.of(context).colorScheme).copyWith(
        height: height,
        handleShape: shape,
        handleColor: accent,
        handleActiveColor: Color.lerp(accent, Colors.white, 0.4),
        borderColor: accent,
        handleGripColor: Colors.black87,
      );

  @override
  Widget build(BuildContext context) {
    final style = _style(context);
    final pages = [_trimPage(style), _coverPage(style), _stylePage()];
    return Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('video_trim_timeline'),
          actions: [
            IconButton(
              tooltip: 'Dark mode',
              icon: Icon(widget.dark ? Icons.light_mode : Icons.dark_mode),
              onPressed: () => widget.onDark(!widget.dark),
            ),
          ],
        ),
        body: SafeArea(child: pages[tab]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.content_cut), label: 'Trim'),
            NavigationDestination(icon: Icon(Icons.image), label: 'Cover'),
            NavigationDestination(icon: Icon(Icons.palette), label: 'Style'),
          ],
        ),
      ),
    );
  }

  Widget _preview(Duration at) => AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CustomPaint(painter: FramePainter(video, at)),
        ),
      );

  Widget _trimPage(TrimTimelineStyle style) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) => _preview(controller.playhead),
        ),
        const SizedBox(height: 12),
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) => Row(
            children: [
              IconButton.filled(
                tooltip: controller.isPlaying ? 'Pause' : 'Play',
                onPressed: controller.togglePlay,
                icon: Icon(
                  controller.isPlaying ? Icons.pause : Icons.play_arrow,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${formatTrimDuration(controller.playhead, tenths: true)}  /  '
                '${formatTrimDuration(controller.selectedDuration, tenths: true)} kept',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Zoom out',
                onPressed: () => controller.zoomBy(0.5),
                icon: const Icon(Icons.zoom_out),
              ),
              IconButton(
                tooltip: 'Zoom in',
                onPressed: () => controller.zoomBy(2),
                icon: const Icon(Icons.zoom_in),
              ),
              IconButton(
                tooltip: 'Fit selection',
                onPressed: controller.zoomToSelection,
                icon: const Icon(Icons.fit_screen),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        TrimTimeline(controller: controller, thumbnails: cache, style: style),
        const SizedBox(height: 16),
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final sel = controller.selection;
            final args = sel.toFfmpegArguments(
              input: 'input.mp4',
              output: 'out.mp4',
            );
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TrimSelection',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      '${sel.start.inMilliseconds} ms to ${sel.end.inMilliseconds} ms',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Pass it to your engine, e.g. FFmpeg:',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    SelectableText(
                      'ffmpeg ${args.join(' ')}',
                      style: const TextStyle(
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const Text(
          'Drag the yellow handles, tap or drag the strip to move the playhead, '
          'pinch (or Ctrl + scroll) to zoom.',
        ),
      ],
    );
  }

  Widget _coverPage(TrimTimelineStyle style) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        CoverPicker(controller: controller, thumbnails: cache, style: style),
        const SizedBox(height: 12),
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) => Text(
            controller.cover == null
                ? 'No cover picked yet: tap or drag on the strip.'
                : 'Cover at ${formatTrimDuration(controller.cover!, tenths: true)}',
          ),
        ),
      ],
    );
  }

  Widget _stylePage() {
    Widget chip(Color c) => GestureDetector(
          onTap: () => setState(() => accent = c),
          child: Container(
            width: 36,
            height: 36,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              border: Border.all(
                width: 3,
                color: accent == c
                    ? Theme.of(context).colorScheme.onSurface
                    : Colors.transparent,
              ),
            ),
          ),
        );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TrimTimeline(
          controller: controller,
          thumbnails: cache,
          style: _style(context),
        ),
        const SizedBox(height: 24),
        const Text('Handle shape'),
        Wrap(
          spacing: 8,
          children: [
            for (final s in TrimHandleShape.values)
              ChoiceChip(
                label: Text(s.name),
                selected: shape == s,
                onSelected: (_) => setState(() => shape = s),
              ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Accent'),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final c in const [
              Color(0xFFFFC107),
              Color(0xFFFF5252),
              Color(0xFF69F0AE),
              Color(0xFF40C4FF),
              Color(0xFFE040FB),
            ])
              chip(c),
          ],
        ),
        const SizedBox(height: 16),
        Text('Strip height ${height.round()}'),
        Slider(
          value: height,
          min: 40,
          max: 96,
          onChanged: (v) => setState(() => height = v),
        ),
        SwitchListTile(
          title: const Text('Right-to-left'),
          value: rtl,
          onChanged: (v) => setState(() => rtl = v),
        ),
        SwitchListTile(
          title: const Text('Haptics (HapticFeedback.selectionClick)'),
          value: hapticsOn,
          onChanged: (v) => setState(() {
            hapticsOn = v;
            controller.haptics = v ? TrimHaptics.system() : const TrimHaptics();
          }),
        ),
        const Text(
          'Custom handles: TrimTimelineStyle.handleBuilder. Haptics: TrimController(haptics: TrimHaptics(...)).',
        ),
      ],
    );
  }
}
