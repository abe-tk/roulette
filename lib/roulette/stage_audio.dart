import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/audio.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_soloud/flutter_scene_soloud.dart';
import 'package:roulette/roulette/roulette_stage.dart';

/// 効果音ごとの音量。1.0 が素材そのままの大きさ。
///
/// 会場のスピーカーに合わせて、ここの値だけを書き換えて調整する。
abstract final class SoundLevels {
  /// 全体の音量。すべての音に掛かる。
  static const double master = 1;

  /// 区画をまたぐカチッ（高速回転〜減速中）。速いほどここから下げる。
  static const double tick = 0.5;

  /// 区画をまたぐカチッ（粘り中）。1回ずつはっきり鳴らす。
  static const double creepTick = 1;

  /// ドラムロール（回転速度が最大のとき）。
  static const double drumroll = 0.6;

  /// 粘り中の心音。
  static const double heartbeat = 1;

  /// 溜めのライザー。
  static const double windup = 0.7;

  /// 当選のファンファーレ。
  static const double fanfare = 0.9;

  /// 当選の歓声。
  static const double cheer = 0.7;

  /// 花火の破裂音。
  static const double firework = 0.6;
}

/// 効果音の素材。`assets/sounds/` に置く。
enum _Sound {
  tick('tick.wav'),
  drumroll('drumroll_loop.wav'),
  heartbeat('heartbeat.wav'),
  windup('windup.wav'),
  fanfare('fanfare.wav'),
  cheer('cheer.wav'),
  firework('firework.wav');

  new(this.file);

  final String file;

  String get asset => 'assets/sounds/$file';
}

/// 高速回転中にカチッを鳴らす最短間隔（秒）。これより速い区画またぎは間引く。
const _minTickInterval = 0.04;

/// ドラムロールが最大音量になる回転速度（ラジアン毎秒）。
const _drumrollFullSpeed = 8.0;

/// 心音の周期（Hz）。粘り中の電飾の鼓動と揃える。
const _heartbeatHz = 1.2;

/// 演出の段階と出来事に合わせて効果音を鳴らす。
///
/// 素材が見つからない音は警告を出して鳴らさない。
class StageAudio {
  final SoloudAudioEngine _engine = SoloudAudioEngine();
  final Map<_Sound, AudioClip> _clips = {};
  final math.Random _random = math.Random();

  AudioVoice? _drumroll;
  double _drumrollVolume = 0;
  double _sinceTick = double.infinity;
  double _lastBeat = 0;
  bool _disposed = false;

  /// [scene] に音声エンジンを取り付け、素材を読み込み始める。
  void attach(Scene scene) {
    scene.root.addComponent(_engine);
    _engine.masterVolume = SoundLevels.master;
    for (final sound in _Sound.values) {
      unawaited(_load(sound));
    }
  }

  Future<void> _load(_Sound sound) async {
    try {
      final clip = await _engine.loadClip(sound.asset);
      if (_disposed) return;
      _clips[sound] = clip;
    } on Object catch (error) {
      debugPrint('効果音 ${sound.asset} を読み込めませんでした: $error');
    }
  }

  AudioVoice? _play(_Sound sound, {required double volume, double pitch = 1}) {
    final clip = _clips[sound];
    if (clip == null || _disposed) return null;
    return _engine.playOneShot(clip, volume: volume, pitch: pitch);
  }

  /// ±[amount] の範囲でばらつかせた 1.0 前後の値。
  double _jitter(double amount) => 1 + (_random.nextDouble() * 2 - 1) * amount;

  /// 段階が [phase] に変わったときに呼ぶ。
  void onPhase(StagePhase phase) {
    switch (phase) {
      case StagePhase.windup:
        _play(_Sound.windup, volume: SoundLevels.windup);
      case StagePhase.rush:
        _startDrumroll();
      case StagePhase.celebrate:
        _stopDrumroll();
        _play(_Sound.fanfare, volume: SoundLevels.fanfare);
        _play(_Sound.cheer, volume: SoundLevels.cheer);
      case StagePhase.idle || StagePhase.slowdown || StagePhase.creep:
        break;
    }
  }

  /// ポインタが区画をまたいだときに呼ぶ。[speed] は回転速度（ラジアン毎秒）。
  void onCrossing(StagePhase phase, double speed) {
    switch (phase) {
      case StagePhase.creep:
        _play(
          _Sound.tick,
          volume: SoundLevels.creepTick,
          pitch: 0.8 * _jitter(0.03),
        );
        _sinceTick = 0;
      case StagePhase.rush || StagePhase.slowdown:
        if (_sinceTick < _minTickInterval) return;
        // 速いほど小さくし、連続した回転音はドラムロールに任せる。
        final quiet = (speed / _drumrollFullSpeed).clamp(0.0, 1.0);
        _play(
          _Sound.tick,
          volume: SoundLevels.tick * (1 - quiet * 0.7),
          pitch: _jitter(0.04),
        );
        _sinceTick = 0;
      case StagePhase.idle || StagePhase.windup || StagePhase.celebrate:
        break;
    }
  }

  /// 花火を打ち上げたときに呼ぶ。
  void onFirework() {
    _play(
      _Sound.firework,
      volume: SoundLevels.firework * _jitter(0.2),
      pitch: _jitter(0.15),
    );
  }

  /// 毎フレーム呼ぶ。[time] は演出の経過秒数、[speed] は回転速度（ラジアン毎秒）。
  void update(double dt, double time, StagePhase phase, double speed) {
    _sinceTick += dt;
    _updateDrumroll(dt, phase, speed);
    // 電飾の鼓動 sin(2π・1.2・time) の山（周期の 1/4）で鳴らす。
    final beat = (time * _heartbeatHz - 0.25).floorToDouble();
    if (phase == StagePhase.creep && beat != _lastBeat) {
      _play(_Sound.heartbeat, volume: SoundLevels.heartbeat);
    }
    _lastBeat = beat;
  }

  void _startDrumroll() {
    _stopDrumroll();
    final clip = _clips[_Sound.drumroll];
    if (clip == null || _disposed) return;
    _drumrollVolume = 0;
    _drumroll = _engine.createVoice(clip)
      ..looping = true
      ..volume = 0
      ..start();
  }

  void _updateDrumroll(double dt, StagePhase phase, double speed) {
    final voice = _drumroll;
    if (voice == null) return;
    final spinning = phase == StagePhase.rush || phase == StagePhase.slowdown;
    final loudness = spinning
        ? math.pow((speed / _drumrollFullSpeed).clamp(0.0, 1.0), 0.7)
        : 0.0;
    // 急に切れないよう、目標の音量へ滑らかに寄せる。
    _drumrollVolume += (loudness - _drumrollVolume) * (1 - math.exp(-dt * 6));
    voice
      ..volume = SoundLevels.drumroll * _drumrollVolume
      ..pitch = 0.85 + 0.3 * _drumrollVolume;
    if (!spinning && _drumrollVolume < 0.01) _stopDrumroll();
  }

  void _stopDrumroll() {
    _drumroll?.stop();
    _drumroll = null;
  }

  /// 鳴っている音を止め、以後は鳴らさない。
  void dispose() {
    _disposed = true;
    _stopDrumroll();
  }
}
