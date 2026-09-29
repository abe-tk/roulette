import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';
import 'package:roulette/roulette/spin_plan.dart';
import 'package:roulette/roulette/stage_audio.dart';
import 'package:roulette/roulette/stage_effects.dart';
import 'package:vector_math/vector_math.dart' as vm;

const _wheelRadius = 2.0;
const _bulbCount = 48;

/// ポインタの先端（ホイールの上端付近）。火花とライトの基準点。
final _pointerTip = vm.Vector3(0, _wheelRadius - 0.1, -0.35);

/// 演出の段階。
enum StagePhase {
  /// スピン前。電飾がゆっくり流れ、ホイールもゆっくり回る。
  idle,

  /// 溜め。
  windup,

  /// 高速回転。
  rush,

  /// 減速。
  slowdown,

  /// 止まりかけの粘り。
  creep,

  /// 当選の祝福。
  celebrate,
}

/// 段階ごとの照明とポストエフェクトの目標値。現在値はここへ滑らかに寄せる。
typedef _Mood = ({
  double environment,
  double spot,
  double backdrop,
  double vignette,
  double saturation,
});

const _moods = <StagePhase, _Mood>{
  StagePhase.idle: (
    environment: 0.35,
    spot: 90,
    backdrop: 0.55,
    vignette: 0.45,
    saturation: 1.05,
  ),
  StagePhase.windup: (
    environment: 0.3,
    spot: 110,
    backdrop: 0.45,
    vignette: 0.55,
    saturation: 1.05,
  ),
  StagePhase.rush: (
    environment: 0.45,
    spot: 110,
    backdrop: 0.9,
    vignette: 0.4,
    saturation: 1.15,
  ),
  StagePhase.slowdown: (
    environment: 0.25,
    spot: 100,
    backdrop: 0.35,
    vignette: 0.6,
    saturation: 0.95,
  ),
  StagePhase.creep: (
    environment: 0.12,
    spot: 70,
    backdrop: 0.08,
    vignette: 0.85,
    saturation: 0.75,
  ),
  StagePhase.celebrate: (
    environment: 0.55,
    spot: 120,
    backdrop: 1.3,
    vignette: 0.3,
    saturation: 1.25,
  ),
};

/// 花火の色（HDR）。
final _fireworkColors = [
  vm.Vector4(8, 5, 1.2, 1),
  vm.Vector4(8, 1.2, 1.5, 1),
  vm.Vector4(1.5, 3.5, 9, 1),
  vm.Vector4(2, 7, 2.5, 1),
  vm.Vector4(7, 2, 7, 1),
  vm.Vector4(7, 7, 7, 1),
];

/// ルーレットの 3D シーンとスピンの状態を持つ。
///
/// [Scene.initializeStaticResources] の完了後に生成すること。
class RouletteStage {
  /// [wheelTexture] を面に貼ったホイールと、[backdropTexture] を貼った背景で
  /// シーンを組む。[glowTexture] は光の粒の形。[audio] を渡すと効果音を鳴らす。
  new({
    required this.names,
    required TextureSource wheelTexture,
    required TextureSource backdropTexture,
    required TextureSource glowTexture,
    StageAudio? audio,
  }) : _audio = audio {
    _build(wheelTexture, backdropTexture, glowTexture);
    audio?.attach(scene);
  }

  /// ホイールに並ぶニックネーム。区画の順。
  final List<String> names;

  /// 描画対象のシーン。
  final Scene scene = Scene();
  final math.Random _random = math.Random.secure();
  final math.Random _fxRandom = math.Random();
  final StageAudio? _audio;

  late final Node _spinner;
  late final Node _pointer;
  late final Node _backdrop;
  late final PhysicallyBasedMaterial _pointerMaterial;
  late final UnlitMaterial _backdropMaterial;
  late final SpotLight _spotLight;
  late final PointLight _pointerLight;
  final List<PhysicallyBasedMaterial> _bulbs = [];

  late final ParticleEmitter _dust;
  late final ParticleEmitter _sparks;
  final List<ParticleEmitter> _fireworks = [];
  final List<ParticleEmitter> _confetti = [];
  final ConfettiShape _confettiShape = ConfettiShape();

  double _wheelAngle = 0;
  SpinPlan? _plan;
  double _spinElapsed = 0;
  double _time = 0;
  double _phaseTime = 0;
  double _speed = 0;
  double _pointerKick = 0;
  double _crossFlash = 0;
  double _flash = 0;
  double _shake = 0;
  double _chase = 0;
  double _backdropAngle = 0;
  double _nextFirework = 0;
  int _fireworkIndex = 0;

  double _zoom = 0;
  double _fov = 45;
  late _Mood _mood = _moods[StagePhase.idle]!;

  /// 演出の段階。
  final ValueNotifier<StagePhase> phase = ValueNotifier(StagePhase.idle);

  /// ポインタが今指している区画。スピン中は毎フレーム更新される。
  late final ValueNotifier<int> pointedIndex = ValueNotifier(
    indexAtPointer(_wheelAngle, names.length),
  );

  /// スピン中かどうか。
  final ValueNotifier<bool> spinning = ValueNotifier(false);

  /// 直近のスピンの当選区画。未抽選なら null。
  final ValueNotifier<int?> winnerIndex = ValueNotifier(null);

  void _build(
    TextureSource wheelTexture,
    TextureSource backdropTexture,
    TextureSource glowTexture,
  ) {
    scene
      ..directionalLight = DirectionalLight(
        direction: vm.Vector3(0.3, -0.6, 1),
        intensity: 1.2,
      )
      ..environmentSettings = EnvironmentSettings(
        toneMapping: ToneMappingMode.aces,
        environmentIntensity: _mood.environment,
        colorGradingEnabled: true,
        saturation: _mood.saturation,
        contrast: 1.1,
        bloomEnabled: true,
        bloomIntensity: 0.22,
        bloomScatter: 0.75,
        lensFlareEnabled: true,
        lensFlareIntensity: 0.35,
        lensFlareHaloIntensity: 0.25,
        vignetteEnabled: true,
        vignetteIntensity: _mood.vignette,
        chromaticAberrationEnabled: true,
        chromaticAberrationIntensity: 0,
      );

    final gold = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1, 0.78, 0.34, 1)
      ..metallicFactor = 1
      ..roughnessFactor = 0.25;

    // ホイールは XZ 平面のジオメトリで組み、X 軸まわりに -90° 倒して
    // 面（+Y）をカメラ側（-Z）へ向ける。
    final faceDown = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -math.pi / 2);
    final wheel = Node(name: 'wheel')..rotation = faceDown;

    final faceMaterial = PhysicallyBasedMaterial(baseColorTexture: wheelTexture)
      ..roughnessFactor = 0.85;
    final body = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.12, 0.08, 0.06, 1)
      ..roughnessFactor = 0.6;
    _spinner = Node(name: 'spinner')
      ..add(
        Node(
          name: 'face',
          mesh: Mesh(
            DiscGeometry(radius: _wheelRadius, segments: 256),
            faceMaterial,
          ),
        )..position = vm.Vector3(0, 0.101, 0),
      )
      ..add(
        Node(
          name: 'body',
          mesh: Mesh(
            CylinderGeometry(
              bottomRadius: _wheelRadius,
              topRadius: _wheelRadius,
              height: 0.2,
              radialSegments: 128,
            ),
            body,
          ),
        ),
      )
      ..add(
        Node(
          name: 'hub',
          mesh: Mesh(
            CylinderGeometry(
              bottomRadius: 0.42,
              topRadius: 0.32,
              height: 0.24,
              radialSegments: 64,
            ),
            gold,
          ),
        )..position = vm.Vector3(0, 0.22, 0),
      );

    wheel
      ..add(_spinner)
      ..add(
        Node(
          name: 'rim',
          mesh: Mesh(
            TorusGeometry(
              radius: _wheelRadius + 0.06,
              tubeRadius: 0.1,
              radialSegments: 192,
            ),
            gold,
          ),
        )..position = vm.Vector3(0, 0.1, 0),
      )
      ..add(
        Node(
          name: 'bulbRing',
          mesh: Mesh(
            TorusGeometry(
              radius: _wheelRadius + 0.3,
              tubeRadius: 0.06,
              radialSegments: 192,
            ),
            gold,
          ),
        )..position = vm.Vector3(0, 0.02, 0),
      );

    // 外周の電飾。1球ずつマテリアルを持たせ、発光を個別に変える。
    final bulbGeometry = SphereGeometry(radius: 0.075);
    for (var i = 0; i < _bulbCount; i++) {
      final angle = 2 * math.pi * i / _bulbCount;
      final material = PhysicallyBasedMaterial()
        ..baseColorFactor = vm.Vector4(0.25, 0.2, 0.15, 1)
        ..roughnessFactor = 0.2
        ..emissiveFactor = vm.Vector4(1, 0.7, 0.35, 1);
      _bulbs.add(material);
      wheel.add(
        Node(name: 'bulb$i', mesh: Mesh(bulbGeometry, material))
          ..position = vm.Vector3(
            (_wheelRadius + 0.3) * math.cos(angle),
            0.1,
            (_wheelRadius + 0.3) * math.sin(angle),
          ),
      );
    }

    // ポインタは上端で下向きの円錐。_pointer を支点に振り子のように揺らす。
    _pointerMaterial = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.85, 0.05, 0.1, 1)
      ..emissiveFactor = vm.Vector4(1, 0.05, 0.08, 1)
      ..emissiveStrength = 0
      ..metallicFactor = 0.3
      ..roughnessFactor = 0.25;
    _pointer = Node(name: 'pointer')
      ..position = vm.Vector3(0, _wheelRadius + 0.35, -0.3)
      ..add(
        Node(
            name: 'pointerCone',
            mesh: Mesh(
              CylinderGeometry(bottomRadius: 0.16, topRadius: 0, height: 0.55),
              _pointerMaterial,
            ),
          )
          ..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi)
          ..position = vm.Vector3(0, -0.2, 0),
      )
      ..add(
        Node(name: 'pointerPin', mesh: Mesh(SphereGeometry(radius: 0.1), gold)),
      );

    // 背景の放射状の円盤。照明に左右されないよう Unlit で明るさを直接操る。
    _backdropMaterial = UnlitMaterial(colorTexture: backdropTexture);
    _backdrop = Node(
      name: 'backdrop',
      mesh: Mesh(DiscGeometry(radius: 10, segments: 128), _backdropMaterial),
    )..position = vm.Vector3(0, 0, 1.5);

    _spotLight = SpotLight(
      color: vm.Vector3(1, 0.92, 0.8),
      intensity: _mood.spot,
      direction: vm.Vector3(0, -4.7, 5)..normalize(),
      innerConeAngle: 0.25,
      outerConeAngle: 0.5,
    );
    _pointerLight = PointLight(
      color: vm.Vector3(1, 0.35, 0.1),
      intensity: 0,
      range: 3,
    );

    _dust = buildDustEmitter(glowTexture);
    _sparks = buildSparkEmitter(_pointerTip, glowTexture);
    for (var i = 0; i < 4; i++) {
      _fireworks.add(buildFireworkEmitter(100 + i, glowTexture));
    }
    for (var i = 0; i < confettiColors.length; i++) {
      _confetti.add(
        buildConfettiEmitter(_confettiShape, confettiColors[i], 200 + i),
      );
    }

    scene
      ..add(_backdrop)
      ..add(wheel)
      ..add(_pointer)
      ..add(
        Node(name: 'spot')
          ..position = vm.Vector3(0, 5, -5)
          ..addComponent(SpotLightComponent(_spotLight)),
      )
      ..add(
        Node(name: 'pointerLight')
          ..position = _pointerTip + vm.Vector3(0, 0.1, -0.4)
          ..addComponent(PointLightComponent(_pointerLight)),
      )
      ..add(_dust.node)
      ..add(_sparks.node);
    for (final emitter in [..._fireworks, ..._confetti]) {
      scene.add(emitter.node);
    }
    _applyWheelAngle();
    _updateBackdrop(0);
  }

  /// スピンを開始する。スピン中は何もしない。
  void spin() {
    if (spinning.value) return;
    _plan = planSpin(
      currentAngle: _wheelAngle % (2 * math.pi),
      count: names.length,
      random: _random,
    );
    _wheelAngle = _plan!.startAngle;
    _spinElapsed = 0;
    winnerIndex.value = null;
    spinning.value = true;
    for (final confetti in _confetti) {
      confetti.rate = 0;
    }
    _setPhase(StagePhase.windup);
  }

  void _setPhase(StagePhase value) {
    if (phase.value == value) return;
    phase.value = value;
    _phaseTime = 0;
    _audio?.onPhase(value);
  }

  /// 毎フレーム呼ぶ。
  void tick(double deltaSeconds) {
    final dt = deltaSeconds;
    _time += dt;
    _phaseTime += dt;

    final plan = _plan;
    if (plan != null) {
      _spinElapsed += dt;
      _wheelAngle = plan.angleAt(_spinElapsed);
      _speed = plan.speedAt(_spinElapsed).abs();
      _setPhase(switch (plan.phaseAt(_spinElapsed)) {
        SpinPhase.windup => StagePhase.windup,
        SpinPhase.rush => StagePhase.rush,
        SpinPhase.slowdown => StagePhase.slowdown,
        SpinPhase.creep => StagePhase.creep,
      });
      if (plan.isFinishedAt(_spinElapsed)) {
        _plan = null;
        _speed = 0;
        spinning.value = false;
        winnerIndex.value = plan.winnerIndex;
        _celebrate();
      }
    } else if (phase.value == StagePhase.idle) {
      _speed = 0.15;
      _wheelAngle += _speed * dt;
    }
    _applyWheelAngle();

    final index = indexAtPointer(_wheelAngle, names.length);
    if (index != pointedIndex.value) {
      pointedIndex.value = index;
      _onCrossing();
    }

    _pointerKick *= math.exp(-dt * 14);
    _pointer.rotation = vm.Quaternion.axisAngle(
      vm.Vector3(0, 0, 1),
      _pointerKick * 0.3,
    );
    _crossFlash *= math.exp(-dt * 7);
    _flash *= math.exp(-dt * 3.5);
    _shake *= math.exp(-dt * 5);

    _audio?.update(dt, _time, phase.value, _speed);
    _updateParticles(dt);
    _updateMood(dt);
    _updateBulbs(dt);
    _updateBackdrop(dt);
    _updateCamera(dt);
  }

  void _onCrossing() {
    _pointerKick = 1;
    _crossFlash = 1;
    _audio?.onCrossing(phase.value, _speed);
    switch (phase.value) {
      case StagePhase.creep:
        _sparks.burst(45);
        _shake = math.max(_shake, 0.5);
      case StagePhase.slowdown when _speed < 3:
        _sparks.burst(15);
      case _:
        break;
    }
  }

  void _celebrate() {
    _setPhase(StagePhase.celebrate);
    _flash = 1;
    _shake = 1;
    _nextFirework = 0.25;
    _sparks.burst(250);
    _confettiShape.mode = ConfettiMode.cannon;
    for (final confetti in _confetti) {
      confetti.system.startSpeed = const UniformFloat(7, 11.5);
      confetti.burst(80);
    }
  }

  void _updateParticles(double dt) {
    final spinningNow = _plan != null;
    _sparks.rate = spinningNow ? math.min(_speed * 14, 320) : 0;
    _dust.rate = phase.value == StagePhase.celebrate ? 90 : 40;

    if (phase.value == StagePhase.celebrate) {
      // 撃ち出した直後から、上から降らせる紙吹雪に切り替える。
      if (_phaseTime > 0.3 && _confettiShape.mode == ConfettiMode.cannon) {
        _confettiShape.mode = ConfettiMode.rain;
        for (final confetti in _confetti) {
          confetti
            ..system.startSpeed = const UniformFloat(0.3, 1.2)
            ..rate = 9;
        }
      }
      if (_phaseTime > 7) {
        for (final confetti in _confetti) {
          confetti.rate = 0;
        }
      }
      if (_phaseTime >= _nextFirework && _phaseTime < 12) {
        _launchFirework();
        _nextFirework += _phaseTime < 3 ? 0.45 : 1.4;
      }
    }

    for (final emitter in [_dust, _sparks, ..._fireworks, ..._confetti]) {
      emitter.apply(dt);
    }
  }

  void _launchFirework() {
    final emitter = _fireworks[_fireworkIndex % _fireworks.length];
    _fireworkIndex++;
    // ホイールに隠れないよう、左右の外側か上方に打ち上げる。
    final side = _fxRandom.nextBool() ? -1.0 : 1.0;
    final high = _fxRandom.nextDouble() < 0.3;
    emitter.node.position = high
        ? vm.Vector3(
            (_fxRandom.nextDouble() - 0.5) * 4,
            3.2 + _fxRandom.nextDouble() * 0.6,
            0.4,
          )
        : vm.Vector3(
            side * (3.4 + _fxRandom.nextDouble() * 2.2),
            -1 + _fxRandom.nextDouble() * 4,
            0.4,
          );
    emitter.system.startColor = ConstantColor(
      _fireworkColors[_fxRandom.nextInt(_fireworkColors.length)],
    );
    emitter.burst(170);
    _audio?.onFirework();
  }

  void _updateMood(double dt) {
    final target = _moods[phase.value]!;
    final k = 1 - math.exp(-dt * 2.5);
    double lerp(double a, double b) => a + (b - a) * k;
    _mood = (
      environment: lerp(_mood.environment, target.environment),
      spot: lerp(_mood.spot, target.spot),
      backdrop: lerp(_mood.backdrop, target.backdrop),
      vignette: lerp(_mood.vignette, target.vignette),
      saturation: lerp(_mood.saturation, target.saturation),
    );

    final speedNorm = (_speed / 20).clamp(0.0, 1.0);
    final creep = phase.value == StagePhase.creep;
    scene
      ..environmentIntensity = _mood.environment
      ..exposure = 1 + _flash * 0.6;
    scene.postProcess
      ..colorGrading.saturation = _mood.saturation
      ..vignette.intensity = _mood.vignette
      ..chromaticAberration.intensity =
          speedNorm * 0.7 + _flash * 0.5 + (creep ? _crossFlash * 0.25 : 0)
      ..bloom.intensity = 0.22 + speedNorm * 0.12 + _flash * 0.2;
    _spotLight.intensity = _mood.spot * (creep ? 0.85 + _crossFlash * 0.3 : 1);

    // ポインタは粘りの間だけ赤く脈打ち、当選後は光り続ける。
    final pulse = 0.5 + 0.5 * math.sin(_time * 2 * math.pi * 1.4);
    final pointerGlow = switch (phase.value) {
      StagePhase.creep => 0.8 + pulse * 1.2 + _crossFlash * 1.5,
      StagePhase.celebrate => 1.5 + pulse,
      _ => _crossFlash * speedNorm * 1.5,
    };
    _pointerMaterial.emissiveStrength = pointerGlow;
    _pointerLight.intensity = pointerGlow * 0.12;
  }

  void _updateBulbs(double dt) {
    final p = phase.value;
    final chaseSpeed = switch (p) {
      StagePhase.idle => 0.5,
      StagePhase.windup => 2.0,
      StagePhase.rush || StagePhase.slowdown => 0.4 + _speed * 0.35,
      StagePhase.creep => 0.0,
      StagePhase.celebrate => 1.2,
    };
    _chase += dt * chaseSpeed;

    for (var i = 0; i < _bulbCount; i++) {
      final u = i / _bulbCount;
      // 4組の光の帯が外周を流れる。
      final wave = math.pow(
        0.5 + 0.5 * math.cos(2 * math.pi * (u * 4 - _chase)),
        6,
      );
      var r = 1.0;
      var g = 0.7;
      var b = 0.35;
      double level;
      switch (p) {
        case StagePhase.idle:
          level = 0.04 + wave * 0.96;
        case StagePhase.windup:
          final blink = (_phaseTime * 12).floor().isEven == i.isEven;
          level = blink ? 1 : 0.2;
        case StagePhase.rush:
        case StagePhase.slowdown:
          level = 0.08 + wave * 0.92;
        case StagePhase.creep:
          // 全体は暗い赤の鼓動。区画をまたぐたびに一瞬全灯する。
          final beat = math.pow(
            0.5 + 0.5 * math.sin(_time * 2 * math.pi * 1.2),
            8,
          );
          r = 1;
          g = 0.12 + _crossFlash * 0.6;
          b = 0.08 + _crossFlash * 0.3;
          level = 0.1 + beat * 0.3 + _crossFlash * 0.5;
        case StagePhase.celebrate:
          if (_phaseTime < 2.5) {
            final blink = (_phaseTime * 8).floor().isEven == i.isEven;
            level = blink ? 1.2 : 0.15;
          } else {
            final hue = (u + _chase * 0.25) % 1;
            (r, g, b) = _hueToRgb(hue);
            level = 0.5 + wave * 0.7;
          }
      }
      final strength = level * 3.5;
      _bulbs[i]
        ..emissiveFactor = vm.Vector4(r, g, b, 1)
        ..emissiveStrength = strength;
    }
  }

  void _updateBackdrop(double dt) {
    final spinSpeed = switch (phase.value) {
      StagePhase.celebrate => 0.6,
      StagePhase.creep => 0.02,
      _ => 0.06 + _speed * 0.02,
    };
    _backdropAngle += dt * spinSpeed;
    // 背景は奥に置き、面をカメラへ向けたまま中心まわりに回す。
    _backdrop.rotation =
        vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), _backdropAngle) *
        vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -math.pi / 2);
    final level = _mood.backdrop + _flash * 0.6;
    _backdropMaterial.baseColorFactor = vm.Vector4(level, level, level, 1);
  }

  void _updateCamera(double dt) {
    final plan = _plan;
    final targetZoom = switch (phase.value) {
      StagePhase.idle => 0.0,
      StagePhase.windup => 0.1,
      StagePhase.rush => 0.0,
      StagePhase.slowdown => _smoothstep(
        0.45,
        0.8,
        plan?.progressAt(_spinElapsed) ?? 1,
      ),
      // 粘りの間はさらにじわじわ寄る。
      StagePhase.creep => 1.0 + 0.12 * _smoothstep(0, 2.8, _phaseTime),
      // 当選直後は寄ったまま、少しして引いて紙吹雪ごと見せる。
      StagePhase.celebrate => _phaseTime < 1.4 ? 1.0 : 0.3,
    };
    final zoomRate = phase.value == StagePhase.celebrate ? 1.6 : 3.0;
    _zoom += (targetZoom - _zoom) * (1 - math.exp(-dt * zoomRate));

    final speedNorm = (_speed / 20).clamp(0.0, 1.0);
    final targetFov =
        45 + speedNorm * 9 + (phase.value == StagePhase.creep ? -3 : 0);
    _fov += (targetFov - _fov) * (1 - math.exp(-dt * 3));
  }

  /// 現在のズーム量に応じたカメラ。
  Camera get camera {
    final wide = (
      // ホイール下端（y ≈ -2.4）からポインタ上端（y ≈ 2.45）までの中心を
      // 画面中央に置き、上下の余白を揃える。
      position: vm.Vector3(0, 0.05, -7.6),
      target: vm.Vector3(0, 0.05, 0),
    );
    // ポインタは盤面より手前にあるため、カメラを左右にずらすと視差で
    // 指している区画がずれて見える。寄っているときは x を 0 に固定する。
    final close = (
      position: vm.Vector3(0, _wheelRadius - 0.6, -1.7),
      target: vm.Vector3(0, _wheelRadius - 0.3, 0),
    );
    final t = _zoom;
    final position = wide.position + (close.position - wide.position) * t;
    final target = wide.target + (close.target - wide.target) * t;

    // 待機中だけゆっくり左右に揺らす。
    final sway = phase.value == StagePhase.idle ? (1 - t).clamp(0.0, 1.0) : 0.0;
    position
      ..x += math.sin(_time * 0.35) * 0.6 * sway
      ..y += math.sin(_time * 0.27) * 0.15 * sway;

    // 揺れは視差を生まないよう上下と前後だけに入れる。
    final speedNorm = (_speed / 20).clamp(0.0, 1.0);
    final shake = _shake * 0.05 + speedNorm * 0.025;
    final dy = (math.sin(_time * 53) + math.sin(_time * 31.7)) * 0.5 * shake;
    final dz = math.sin(_time * 41.3) * shake;
    position
      ..y += dy
      ..z += dz;
    target.y += dy;

    return PerspectiveCamera(
      fovRadiansY: _fov * vm.degrees2Radians,
      position: position,
      target: target,
    );
  }

  void _applyWheelAngle() {
    _spinner.rotation = vm.Quaternion.axisAngle(
      vm.Vector3(0, 1, 0),
      _wheelAngle,
    );
  }

  /// 効果音を止め、通知用の [ValueNotifier] を破棄する。
  void dispose() {
    _audio?.dispose();
    phase.dispose();
    pointedIndex.dispose();
    spinning.dispose();
    winnerIndex.dispose();
  }
}

double _smoothstep(double edge0, double edge1, double x) {
  final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

(double, double, double) _hueToRgb(double hue) {
  double channel(double offset) =>
      (math.cos(2 * math.pi * (hue - offset)) * 0.5 + 0.5).clamp(0.0, 1.0);
  return (channel(0), channel(1 / 3), channel(2 / 3));
}
