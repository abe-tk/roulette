import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// パーティクルの発生数をフレームごとに制御する。
///
/// [ParticleSystem] は発生レートでしか外から数を指示できないため、
/// [burst] で溜めた数を次のフレームのレートに上乗せして一度に出す。
class ParticleEmitter {
  /// [system] を描画するコンポーネントを [node] に付けて作る。
  new(this.node, this.system, Component component) {
    node.addComponent(component);
  }

  /// エミッタを置いたノード。パーティクルはこのノードのローカル空間で動く。
  final Node node;

  /// 発生と挙動を持つシミュレーション。
  final ParticleSystem system;

  /// 毎秒の発生数。
  double rate = 0;

  int _pending = 0;

  /// 次のフレームで [count] 個を一度に出す。
  void burst(int count) => _pending += count;

  /// 毎フレーム呼び、このフレームの発生レートを決める。
  void apply(double deltaSeconds) {
    final burstRate = _pending / math.max(deltaSeconds, 1 / 240);
    system.spawner.rate = rate + burstRate;
    _pending = 0;
  }
}

vm.Vector4 _rgba(double r, double g, double b, [double a = 1]) =>
    vm.Vector4(r, g, b, a);

/// ホイールのまわりを漂う金粉。
ParticleEmitter buildDustEmitter(TextureSource glow) {
  final system = ParticleSystem(
    maxParticles: 600,
    shape: BoxEmitterShape(
      halfExtents: vm.Vector3(7, 4.5, 1.5),
      direction: vm.Vector3(0, 1, 0),
    ),
    spawner: Spawner(),
    lifetime: const UniformFloat(4, 8),
    startSpeed: const UniformFloat(0.05, 0.25),
    startSize: const UniformFloat(0.02, 0.06),
    startColor: UniformColor(_rgba(3, 2, 0.8), _rgba(2.4, 1.2, 0.4)),
    modules: [
      TurbulenceModule(strength: 0.4, frequency: 0.6),
      SizeOverLifeModule(
        CurveFloat(
          ParticleCurve(const [
            ParticleKeyframe(0, 0),
            ParticleKeyframe(0.2, 1),
            ParticleKeyframe(0.8, 1),
            ParticleKeyframe(1, 0),
          ]),
        ),
      ),
    ],
    prewarm: 6,
    seed: 11,
  );
  final material = SpriteMaterial(colorTexture: glow)
    ..blendMode = SpriteBlendMode.additive;
  final node = Node(name: 'dust')..position = vm.Vector3(0, 0, 0.8);
  return ParticleEmitter(
    node,
    system,
    ParticleEmitterComponent(system: system, material: material),
  )..rate = 40;
}

/// ポインタの先から飛び散る火花。
ParticleEmitter buildSparkEmitter(vm.Vector3 position, TextureSource glow) {
  final system = ParticleSystem(
    maxParticles: 800,
    shape: const ConeEmitterShape(angle: 0.9),
    spawner: Spawner(),
    lifetime: const UniformFloat(0.25, 0.7),
    startSpeed: const UniformFloat(1.5, 4.5),
    startSize: const UniformFloat(0.012, 0.03),
    startColor: UniformColor(_rgba(8, 5, 1.6), _rgba(6, 1.8, 0.3)),
    gravity: vm.Vector3(0, -7, 0),
    modules: [
      LinearDragModule(1.5),
      SizeOverLifeModule(CurveFloat(ParticleCurve.linear(from: 1, to: 0))),
    ],
    seed: 23,
  );
  final material = SpriteMaterial(colorTexture: glow)
    ..blendMode = SpriteBlendMode.additive;
  final component = ParticleEmitterComponent(system: system, material: material)
    ..facing = BillboardFacing.velocityStretched
    ..velocityStretch = 0.035;
  final node = Node(name: 'sparks')..position = position;
  return ParticleEmitter(node, system, component);
}

/// 当選時に打ち上げる花火。色は打ち上げごとに startColor で変える。
ParticleEmitter buildFireworkEmitter(int seed, TextureSource glow) {
  final system = ParticleSystem(
    maxParticles: 500,
    shape: const SphereEmitterShape(radius: 0.05, surfaceOnly: true),
    spawner: Spawner(),
    lifetime: const UniformFloat(1.1, 1.8),
    startSpeed: const UniformFloat(2.2, 3.2),
    startSize: const UniformFloat(0.03, 0.06),
    gravity: vm.Vector3(0, -1.6, 0),
    modules: [
      LinearDragModule(1.4),
      SizeOverLifeModule(
        CurveFloat(
          ParticleCurve(const [
            ParticleKeyframe(0, 1),
            ParticleKeyframe(0.7, 0.8),
            ParticleKeyframe(1, 0),
          ]),
        ),
      ),
    ],
    seed: seed,
  );
  final material = SpriteMaterial(colorTexture: glow)
    ..blendMode = SpriteBlendMode.additive;
  final component = ParticleEmitterComponent(system: system, material: material)
    ..facing = BillboardFacing.velocityStretched
    ..velocityStretch = 0.05;
  return ParticleEmitter(Node(name: 'firework$seed'), system, component);
}

/// 紙吹雪の出どころ。
enum ConfettiMode {
  /// 画面の左右下から中央上へ撃ち出す。
  cannon,

  /// 画面の上から降らせる。
  rain,
}

/// 紙吹雪の発生位置と向き。[mode] は全色のエミッタで共有して切り替える。
class ConfettiShape extends EmitterShape {
  /// 撃ち出しで作る。
  new();

  /// 発生のしかた。
  ConfettiMode mode = ConfettiMode.cannon;

  @override
  void sample(ParticleStorage storage, int index) {
    final a = storage.randomFor(index, 41);
    final b = storage.randomFor(index, 42);
    final c = storage.randomFor(index, 43);
    switch (mode) {
      case ConfettiMode.cannon:
        // a で左右を振り分け、内側上方へ ±0.35rad の幅で撃つ。
        final side = a < 0.5 ? -1.0 : 1.0;
        final spread = (b - 0.5) * 0.7;
        final angle = math.pi / 2 - side * (0.42 + spread);
        storage
          ..posX[index] = -side * 4.8
          ..posY[index] = -3.6
          ..posZ[index] = (c - 0.5) * 1.5
          ..velX[index] = math.cos(angle)
          ..velY[index] = math.sin(angle)
          ..velZ[index] = (c - 0.5) * 0.3;
      case ConfettiMode.rain:
        storage
          ..posX[index] = (a - 0.5) * 12
          ..posY[index] = 4.5
          ..posZ[index] = (b - 0.5) * 3
          ..velX[index] = 0
          ..velY[index] = -1
          ..velZ[index] = 0;
    }
  }
}

/// 紙吹雪の色。金銀は金属質にしてきらめかせる。
final List<({vm.Vector4 color, double metallic})> confettiColors = [
  (color: vm.Vector4(1, 0.76, 0.2, 1), metallic: 1),
  (color: vm.Vector4(0.9, 0.9, 0.95, 1), metallic: 1),
  (color: vm.Vector4(0.9, 0.1, 0.2, 1), metallic: 0.2),
  (color: vm.Vector4(0.1, 0.5, 1, 1), metallic: 0.2),
  (color: vm.Vector4(0.2, 0.85, 0.35, 1), metallic: 0.2),
  (color: vm.Vector4(1, 0.35, 0.75, 1), metallic: 0.2),
];

/// 1色ぶんの紙吹雪。メッシュのパーティクルは個別に色を持てないため色ごとに作る。
ParticleEmitter buildConfettiEmitter(
  ConfettiShape shape,
  ({vm.Vector4 color, double metallic}) spec,
  int seed,
) {
  final system = ParticleSystem(
    maxParticles: 500,
    shape: shape,
    spawner: Spawner(),
    lifetime: const UniformFloat(4, 6.5),
    startSpeed: const UniformFloat(7, 11.5),
    startSize: const UniformFloat(0.8, 1.2),
    startAngularVelocity: const UniformFloat(-9, 9),
    gravity: vm.Vector3(0, -3.2, 0),
    modules: [
      LinearDragModule(1.1),
      TurbulenceModule(strength: 1.6, frequency: 0.5, seed: seed),
      const RotationModule(),
    ],
    seed: seed,
  );
  final material = PhysicallyBasedMaterial()
    ..baseColorFactor = spec.color
    ..emissiveFactor = spec.color
    ..emissiveStrength = 0.25
    ..metallicFactor = spec.metallic
    ..roughnessFactor = 0.35;
  final component = MeshParticleEmitterComponent(
    system: system,
    geometries: [
      CuboidGeometry(vm.Vector3(0.09, 0.004, 0.13)),
      CuboidGeometry(vm.Vector3(0.05, 0.004, 0.16)),
    ],
    material: material,
  );
  return ParticleEmitter(Node(name: 'confetti$seed'), system, component);
}
