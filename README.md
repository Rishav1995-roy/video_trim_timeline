# video_trim_timeline

[![pub version](https://img.shields.io/pub/v/video_trim_timeline.svg)](https://pub.dev/packages/video_trim_timeline)
[![pub points](https://img.shields.io/pub/points/video_trim_timeline)](https://pub.dev/packages/video_trim_timeline/score)
[![likes](https://img.shields.io/pub/likes/video_trim_timeline)](https://pub.dev/packages/video_trim_timeline)
[![popularity](https://img.shields.io/pub/popularity/video_trim_timeline)](https://pub.dev/packages/video_trim_timeline)
[![CI](https://github.com/Rishav1995-roy/video_trim_timeline/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/Rishav1995-roy/video_trim_timeline/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Platforms](https://img.shields.io/badge/platforms-android%20%7C%20ios%20%7C%20web%20%7C%20macos%20%7C%20windows%20%7C%20linux-informational)

A video trim UI for Flutter that does **not** come with a video engine: thumbnail timeline, draggable trim handles, playhead, cover-frame picker and zoom. You plug in your own player and frame extractor, and get back a plain `TrimSelection` to pass to FFmpeg, a native editor or a server.

![Demo](https://raw.githubusercontent.com/Rishav1995-roy/video_trim_timeline/main/doc/demo.gif)

<p>
  <img src="https://raw.githubusercontent.com/Rishav1995-roy/video_trim_timeline/main/doc/screenshot_light.png" width="260" alt="Light mode">
  <img src="https://raw.githubusercontent.com/Rishav1995-roy/video_trim_timeline/main/doc/screenshot_dark.png" width="260" alt="Dark mode with custom handles">
</p>

> The demo and screenshots use a synthetic, generated "video" (gradients and a bouncing ball), rendered deterministically in a Flutter test. They are not a device capture and no real footage is involved.

## Why this package

Trimming UIs in the Flutter ecosystem were built around one engine. When that engine was discontinued, the UI went with it. This package is only the UI, with the engine left to you.

| | `video_editor` | `video_trimmer` | `video_trim_timeline` |
|---|---|---|---|
| Bundled video engine | FFmpeg Kit based (the plugin was discontinued) | FFmpeg Kit based | None, engine-agnostic |
| Thumbnails | Fixed plugin (`video_thumbnail`, see [#201](https://github.com/LeGoffMael/video_editor/issues/201), [#203](https://github.com/LeGoffMael/video_editor/issues/203)) | Fixed plugin | Your own `ThumbnailProvider`, lazy, cached, de-duplicated |
| Missing or failed frame | Crash reported: [#209](https://github.com/LeGoffMael/video_editor/issues/209) | n/a | Placeholder, never throws |
| Handle touch target | Hard to grab: [#207](https://github.com/LeGoffMael/video_editor/issues/207) | n/a | 44 px target that extends outward, tested at the minimum selection |
| Empty / zero duration | `RangeError`, `Infinity or NaN toInt`: [#160](https://github.com/LeGoffMael/video_editor/issues/160), [#165](https://github.com/LeGoffMael/video_editor/issues/165) | n/a | Every setter clamps; duration may arrive late |
| Player stays inside the trim | Playback problems when trimming from the middle: [#202](https://github.com/LeGoffMael/video_editor/issues/202) | n/a | Controller seeks into range, loops or pauses at the out-point |
| Live preview while dragging | Requested: [#110](https://github.com/LeGoffMael/video_editor/issues/110) | n/a | `seekTo` the handle position while dragging (throttled) |
| Zoomable timeline | Requested: [#114](https://github.com/LeGoffMael/video_editor/issues/114) | No | Pinch, Ctrl + scroll, buttons |
| Theming | Limited | Limited | Handle shapes/builder, colors, overlay, playhead, placeholders |
| RTL, semantics, keyboard | No | No | Yes |
| Export | Built in (FFmpeg) | Built in | Out of scope by design; see [export](#export) |

Use `video_editor` if you still want an all-in-one editor with crop and export and accept its dependencies. Use this package when you own the player and the export step and just need a good trim timeline.

## Features

- Thumbnail strip fed by a pluggable `ThumbnailProvider` (lazy per tile, LRU cache, de-duplicated, debounced while zooming)
- Start / end handles with `minDuration` and `maxDuration`
- Playhead synced through a tiny `TrimPlaybackAdapter` interface
- `CoverPicker` with large preview
- Zoom and pan for long videos (pinch, Ctrl/Cmd + scroll, buttons, edge auto-scroll while dragging)
- Haptics hooks (`TrimHaptics`, plus `TrimHaptics.system()`)
- Theming: four handle shapes or a custom `handleBuilder`, colors, overlay of the trimmed area, borders, playhead, placeholders, strip height
- RTL mirroring, screen reader slider actions (increase / decrease), keyboard arrows on handles
- Pure Dart, depends only on Flutter, runs on every platform

## Installation

```sh
flutter pub add video_trim_timeline
```

Requires Dart `^3.6.0` and Flutter `>=3.27.0`. Tested on Flutter 3.27 and the latest stable.

## Quick start

```dart
final controller = TrimController(
  totalDuration: const Duration(seconds: 90),
  minDuration: const Duration(seconds: 2),
  maxDuration: const Duration(seconds: 30),
);
final thumbnails = ThumbnailCache(MyThumbnailProvider()); // your frames
controller.attachPlayback(MyPlayerAdapter(player));       // optional

TrimTimeline(controller: controller, thumbnails: thumbnails)
```

When the player reports its length later, call `controller.setTotalDuration(d)`. When the user taps "Done":

```dart
final TrimSelection selection = controller.selection; // start, end, cover
```

### Thumbnails

```dart
class MyThumbnailProvider implements ThumbnailProvider {
  @override
  Future<ImageProvider?> thumbnailAt(Duration position, Size targetSize) async {
    final bytes = await myExtractor.frameAt(position, width: targetSize.width.toInt());
    return bytes == null ? null : MemoryImage(bytes); // null = placeholder
  }
}
```

### Playback (video_player example, not a dependency)

```dart
class VideoPlayerAdapter implements TrimPlaybackAdapter {
  VideoPlayerAdapter(this.c) {
    c.addListener(() {
      position.value = c.value.position;
      isPlaying.value = c.value.isPlaying;
    });
  }
  final VideoPlayerController c;
  @override final position = ValueNotifier(Duration.zero);
  @override final isPlaying = ValueNotifier(false);
  @override Future<void> seekTo(Duration p) => c.seekTo(p);
  @override Future<void> play() => c.play();
  @override Future<void> pause() => c.pause();
}
```

For `media_kit` map `player.stream.position` / `playing` the same way.

### Export

`TrimSelection` is plain data. With FFmpeg:

```dart
final args = selection.toFfmpegArguments(input: inPath, output: outPath);
// run: ffmpeg ${args.join(' ')}     (any FFmpeg build you ship)
final coverArgs = selection.toCoverFfmpegArguments(input: inPath, output: 'cover.jpg');
```

`copyStreams: true` is fast but snaps to key frames; the default re-encodes for frame-accurate cuts. For native editors pass `selection.start` and `selection.end` (as `Duration` or `toJson()` microseconds) to AVAssetExportSession (`timeRange`) on iOS or Media3 Transformer (`ClippingConfiguration`) on Android through your own platform channel.

## API

| Class | Purpose |
|---|---|
| `TrimController` | State: `totalDuration`, `start`, `end`, `playhead`, `cover`, `zoom`, `viewStart`; `setStart`, `setEnd`, `setSelection`, `moveSelectionBy`, `seek`, `setCover`, `setZoom`, `zoomBy`, `scrollBy`, `zoomToSelection`, `attachPlayback`, `play`, `pause`, `selection` |
| `TrimTimeline` | The timeline widget |
| `CoverPicker` | Cover frame strip and preview |
| `TrimSelection` | `start`, `end`, `cover`, `duration`, FFmpeg helpers, JSON |
| `ThumbnailProvider`, `ThumbnailCache`, `FunctionThumbnailProvider` | Frame source and cache |
| `TrimPlaybackAdapter`, `SimulatedPlaybackAdapter` | Player bridge (and a manual-clock stand-in) |
| `TrimTimelineStyle` | All visuals |
| `TrimHaptics` | Feedback hooks |

`TrimController` options: `totalDuration`, `minDuration` (1 s), `maxDuration`, `maxZoom` (32), `initialStart`, `initialEnd`, `haptics`; fields `loop` (loop inside the selection, default true) and `previewInterval`.

`TrimTimeline` options: `controller`, `thumbnails`, `style`, `mirrorInRtl`, `showCoverMarker`, `enableZoomGestures`, `keyboardStep`, and the three semantic labels.

`TrimTimelineStyle`: `height`, `borderRadius`, `handleWidth`, `handleHitWidth`, `handleShape` (`bar`, `rounded`, `pill`, `chevron`), `handleBuilder`, `handleColor`, `handleActiveColor`, `handleGripColor`, `overlayColor`, `borderColor`, `borderWidth`, `playheadColor`, `playheadWidth`, `playheadHeadSize`, `showPlayhead`, `coverColor`, `placeholderColor`, `placeholderBuilder`, `thumbnailAspectRatio`, `backgroundColor`; `TrimTimelineStyle.fromColorScheme(scheme)`.

## Customization

```dart
TrimTimeline(
  controller: controller,
  thumbnails: thumbnails,
  style: TrimTimelineStyle.fromColorScheme(Theme.of(context).colorScheme).copyWith(
    height: 80,
    handleShape: TrimHandleShape.chevron,
    overlayColor: Colors.black87,
    handleBuilder: (context, side, active, size) => MyHandle(side: side, active: active),
  ),
)

TrimController(haptics: TrimHaptics.system()); // or your own callbacks
```

## Platform support

| Android | iOS | Web | macOS | Windows | Linux |
|---|---|---|---|---|---|
| Yes | Yes | Yes | Yes | Yes | Yes |

No native code and no plugins. Actually decoding frames and exporting video is up to the engine you choose, and that choice decides which platforms your app can ship the editor on.

## FAQ

**Does it play or export video?** No. That is the point; see the adapter and export sections.

**Why 44 px handles when the handle looks 14 px wide?** The visual and the touch target are separate. The target extends mostly outward from the selection so both handles stay grabbable even at the minimum duration.

**Can I use a sprite sheet for thumbnails?** Yes, return a cropped `ImageProvider` from your `ThumbnailProvider`.

**Does it work in RTL?** Yes, the timeline mirrors by default (`mirrorInRtl`).

## Contributing

Issues and PRs are welcome at [github.com/Rishav1995-roy/video_trim_timeline](https://github.com/Rishav1995-roy/video_trim_timeline). Run `flutter analyze` and `flutter test` before opening a PR. To regenerate the demo media see `tool/make_demo_test.dart` and `tool/make_gif.sh`.

## License

MIT, see [LICENSE](LICENSE).
