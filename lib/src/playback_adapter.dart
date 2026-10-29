import 'package:flutter/foundation.dart';

/// The only thing the timeline needs from a video player.
///
/// Implement it on top of `video_player`, `media_kit` or anything else.
/// Example for `video_player` (not a dependency of this package):
///
/// ```dart
/// class VideoPlayerAdapter implements TrimPlaybackAdapter {
///   VideoPlayerAdapter(this.c) {
///     c.addListener(() {
///       position.value = c.value.position;
///       isPlaying.value = c.value.isPlaying;
///     });
///   }
///   final VideoPlayerController c;
///   @override final position = ValueNotifier(Duration.zero);
///   @override final isPlaying = ValueNotifier(false);
///   @override Future<void> seekTo(Duration p) => c.seekTo(p);
///   @override Future<void> play() => c.play();
///   @override Future<void> pause() => c.pause();
/// }
/// ```
abstract interface class TrimPlaybackAdapter {
  /// Current playback position.
  ValueListenable<Duration> get position;

  /// Whether the video is playing.
  ValueListenable<bool> get isPlaying;

  /// Seeks to [position].
  Future<void> seekTo(Duration position);

  /// Starts playback.
  Future<void> play();

  /// Pauses playback.
  Future<void> pause();
}

/// An in-memory adapter that plays on a manual clock.
///
/// Useful for tests, demos and screens that show a trim UI before a player
/// exists. Call [advance] to move time forward while playing.
class SimulatedPlaybackAdapter implements TrimPlaybackAdapter {
  @override
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);

  @override
  final ValueNotifier<bool> isPlaying = ValueNotifier(false);

  /// Every position passed to [seekTo], in order.
  final List<Duration> seeks = [];

  /// Moves the position forward by [delta] when playing.
  void advance(Duration delta) {
    if (isPlaying.value) position.value += delta;
  }

  @override
  Future<void> seekTo(Duration position) async {
    seeks.add(position);
    this.position.value = position;
  }

  @override
  Future<void> play() async => isPlaying.value = true;

  @override
  Future<void> pause() async => isPlaying.value = false;

  /// Releases the notifiers.
  void dispose() {
    position.dispose();
    isPlaying.dispose();
  }
}
