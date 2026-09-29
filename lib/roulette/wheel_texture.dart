import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:roulette/roulette/spin_plan.dart';

const _sectorColors = [
  Color(0xFFE53935),
  Color(0xFFFB8C00),
  Color(0xFFFDD835),
  Color(0xFF43A047),
  Color(0xFF1E88E5),
  Color(0xFF8E24AA),
];

/// 区画 [index] の色。隣り合う区画（末尾と先頭を含む）が同じ色にならない。
Color sectorColor(int index, int count) {
  final length = _sectorColors.length;
  if (count > 1 && index == count - 1 && index % length == 0) {
    return _sectorColors[1];
  }
  return _sectorColors[index % length];
}

/// ホイール面のテクスチャを描く。
///
/// 画像の中心がホイールの中心で、区画 i は画像上の角度
/// `[i * sectorAngle, (i + 1) * sectorAngle)`（x 軸から y 軸方向）を占める。
/// DiscGeometry の UV（u = 0.5 + 0.5cosθ, v = 0.5 + 0.5sinθ）と一致する。
Future<ui.Image> paintWheelImage(List<String> names, {int size = 4096}) {
  final count = names.length;
  final center = size / 2;
  final radius = size / 2;
  final sector = sectorAngle(count);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..translate(center, center);

  final wedgeRect = Rect.fromCircle(center: Offset.zero, radius: radius);
  for (var i = 0; i < count; i++) {
    canvas.drawArc(
      wedgeRect,
      i * sector,
      sector,
      true,
      Paint()..color = sectorColor(i, count),
    );
  }

  // 名前は外周側に寄せて放射状に描き、文字サイズは外周側の区画幅から決める。
  final textOuter = radius * 0.96;
  final textInner = radius * 0.22;
  final fontSize = math.min(sector * textOuter * 0.62, radius * 0.08);
  for (var i = 0; i < count; i++) {
    final painter = TextPainter(
      text: TextSpan(
        text: names[i],
        style: TextStyle(
          color: const Color(0xFFFFFFFF),
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          shadows: const [Shadow(color: Color(0x99000000), blurRadius: 2)],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: textOuter - textInner);
    // DiscGeometry の UV をこのシーンの向きで見ると鏡像になるため、文字だけ
    // 放射線に対して反転して描き、画面上で正しく読めるようにする。
    canvas
      ..save()
      ..rotate((i + 0.5) * sector)
      ..scale(1, -1);
    painter
      ..paint(canvas, Offset(textOuter - painter.width, -painter.height / 2))
      ..dispose();
    canvas.restore();
  }

  return recorder.endRecording().toImage(size, size);
}

/// ホイールの背後に置く放射状の背景のテクスチャを描く。
///
/// 中心から外へ暗くなる、深紅と金の縞。
Future<ui.Image> paintBackdropImage({int size = 2048, int rays = 24}) {
  final center = size / 2;
  final radius = size / 2;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..translate(center, center);
  final rect = Rect.fromCircle(center: Offset.zero, radius: radius);

  final sweep = 2 * math.pi / rays;
  for (var i = 0; i < rays; i++) {
    canvas.drawArc(
      rect,
      i * sweep,
      sweep,
      true,
      Paint()
        ..color = i.isEven ? const Color(0xFF5A0A14) : const Color(0xFF8A5A12),
    );
  }
  canvas.drawCircle(
    Offset.zero,
    radius,
    Paint()
      ..shader = ui.Gradient.radial(
        Offset.zero,
        radius,
        const [Color(0x00000000), Color(0x99000000), Color(0xFF000000)],
        const [0.15, 0.55, 1],
      ),
  );

  return recorder.endRecording().toImage(size, size);
}

/// パーティクル用の、中心が明るく縁へ消える丸いテクスチャを描く。
Future<ui.Image> paintGlowImage({int size = 64}) {
  final radius = size / 2;
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawCircle(
    Offset(radius, radius),
    radius,
    Paint()
      ..shader = ui.Gradient.radial(
        Offset(radius, radius),
        radius,
        const [Color(0xFFFFFFFF), Color(0x66FFFFFF), Color(0x00FFFFFF)],
        const [0, 0.35, 1],
      ),
  );
  return recorder.endRecording().toImage(size, size);
}
