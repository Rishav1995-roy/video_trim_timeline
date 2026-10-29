/// Engine-agnostic video trimming UI for Flutter.
///
/// The package draws the timeline, handles, playhead and cover picker. It
/// never decodes or exports video: you plug in a [ThumbnailProvider] and a
/// [TrimPlaybackAdapter], and pass the resulting [TrimSelection] to any engine.
library;

export 'src/cover_picker.dart';
export 'src/playback_adapter.dart';
export 'src/thumbnail_provider.dart';
export 'src/trim_controller.dart';
export 'src/trim_selection.dart';
export 'src/trim_style.dart';
export 'src/trim_timeline.dart';
