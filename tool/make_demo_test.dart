// Renders doc/demo.gif frames and screenshots deterministically (no device).
//
//   flutter test tool/make_demo_test.dart --tags demo
//   tool/make_gif.sh        # assembles doc/demo.gif with ffmpeg
//
// The "video" is synthetic (see example/lib/synthetic_video.dart).
// ignore_for_file: avoid_relative_lib_imports
@Tags(['demo'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_trim_timeline/video_trim_timeline.dart';

import '../example/lib/main.dart';
import '../example/lib/synthetic_video.dart';

const _size = Size(420, 800);
final _key = GlobalKey();
final _frames = Directory('build/demo_frames');

Future<void> _loadFonts() async {
  Future<ByteData> bytes(String f) async =>
      ByteData.sublistView(await File('tool/fonts/$f').readAsBytes());
  final roboto = FontLoader('Roboto')
    ..addFont(bytes('Roboto-Regular.ttf'))
    ..addFont(bytes('Roboto-Medium.ttf'))
    ..addFont(bytes('Roboto-Bold.ttf'));
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(bytes('MaterialIcons-Regular.otf'));
  await icons.load();
}

Future<ThumbnailCache> _warm(WidgetTester tester) async {
  final provider = SyntheticThumbnails(const SyntheticVideo());
  PaintingBinding.instance.imageCache
    ..maximumSize = 5000
    ..maximumSizeBytes = 1 << 30;
  final cache = ThumbnailCache(provider, capacity: 2000);
  await tester.runAsync(() async {
    for (var ms = 0; ms <= 48000; ms += 100) {
      final img =
          await cache.load(Duration(milliseconds: ms), const Size(250, 140));
      if (img != null) {
        await precacheImage(img, tester.element(find.byType(Scaffold)));
      }
    }
  });
  return cache;
}

Future<void> _shot(WidgetTester tester, String path, {double ratio = 1}) async {
  await tester.runAsync(() async {
    final boundary =
        _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: ratio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File(path).writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Future<void> _mount(WidgetTester tester, Widget app) async {
  tester.view
    ..physicalSize = _size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(RepaintBoundary(key: _key, child: app));
  await tester.pump();
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('screenshots', timeout: const Timeout(Duration(minutes: 5)),
      (tester) async {
    Directory('doc').createSync(recursive: true);
    // Warm with a throwaway mount so precacheImage has a context.
    await _mount(tester, const ExampleApp());
    final cache = await _warm(tester);
    await _mount(tester, ExampleApp(thumbnailCache: cache));
    await tester.pump(const Duration(milliseconds: 300));
    await _shot(tester, 'doc/screenshot_light.png', ratio: 1.5);

    await _mount(
      tester,
      ExampleApp(
        dark: true,
        initialTab: 2,
        thumbnailCache: cache,
        initialShape: TrimHandleShape.chevron,
        initialAccent: const Color(0xFFE040FB),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await _shot(tester, 'doc/screenshot_dark.png', ratio: 1.5);
  });

  testWidgets('gif frames', timeout: const Timeout(Duration(minutes: 5)),
      (tester) async {
    if (_frames.existsSync()) _frames.deleteSync(recursive: true);
    _frames.createSync(recursive: true);
    await _mount(tester, const ExampleApp());
    final cache = await _warm(tester);
    await _mount(tester, ExampleApp(thumbnailCache: cache));
    await tester.pump(const Duration(milliseconds: 100));

    var n = 0;
    Future<void> frame([int ms = 66]) async {
      await tester.pump(Duration(milliseconds: ms));
      await _shot(
          tester, '${_frames.path}/f${(n++).toString().padLeft(4, '0')}.png');
    }

    Rect tl() => tester.getRect(find.byType(TrimTimeline));
    final pad = 44 * 0.8;
    double xAt(double sec) =>
        tl().left + pad + (tl().width - pad * 2) * sec / 48;
    final y = tl().center.dy;

    for (var i = 0; i < 4; i++) {
      await frame();
    }
    // play
    await tester.tap(find.byIcon(Icons.play_arrow));
    for (var i = 0; i < 14; i++) {
      await frame();
    }
    // drag the end handle left (26s -> 18s)
    var g = await tester.startGesture(Offset(xAt(26) + 12, y));
    for (var i = 0; i < 12; i++) {
      await g.moveBy(Offset(-(xAt(26) - xAt(18)) / 12, 0));
      await frame();
    }
    await g.up();
    // drag the start handle right (6s -> 10s)
    g = await tester.startGesture(Offset(xAt(6) - 12, y));
    for (var i = 0; i < 10; i++) {
      await g.moveBy(Offset((xAt(10) - xAt(6)) / 10, 0));
      await frame();
    }
    await g.up();
    for (var i = 0; i < 8; i++) {
      await frame();
    }
    // scrub the playhead with a finger
    g = await tester.startGesture(Offset(xAt(12.5), y));
    for (var i = 0; i < 12; i++) {
      await g.moveBy(Offset((xAt(17.5) - xAt(12.5)) / 12, 0));
      await frame();
    }
    await g.up();
    await frame();
    // cover tab
    await tester.tap(find.text('Cover'));
    for (var i = 0; i < 3; i++) {
      await frame();
    }
    final strip = tester.getRect(find.byType(CoverPicker));
    final stripY = strip.bottom - 36;
    g = await tester
        .startGesture(Offset(strip.left + strip.width * 0.15, stripY));
    for (var i = 0; i < 14; i++) {
      await g.moveBy(Offset(strip.width * 0.6 / 14, 0));
      await frame();
    }
    await g.up();
    for (var i = 0; i < 8; i++) {
      await frame();
    }
    // ignore: avoid_print
    print('frames: $n');
  });
}
