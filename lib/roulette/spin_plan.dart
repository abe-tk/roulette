import 'dart:math' as math;

/// ホイールの回転角と区画の対応。
///
/// 区画 i はホイール上の角度 `[i * sectorAngle, (i + 1) * sectorAngle)` を
/// 占める。ホイールを回転角 wheelAngle だけ回したとき、ポインタの真下には
/// ホイール上の角度 `wheelAngle + pointerAngle` が来る。
const double pointerAngle = math.pi / 2;

/// 1区画あたりの角度。
double sectorAngle(int count) => 2 * math.pi / count;

/// 回転角 [wheelAngle] のときポインタが指している区画。
int indexAtPointer(double wheelAngle, int count) {
  final angle = (wheelAngle + pointerAngle) % (2 * math.pi);
  return (angle / sectorAngle(count)).floor() % count;
}

/// スピン中の演出の段階。
enum SpinPhase {
  /// 開始直後にホイールを少し逆回しして溜める。
  windup,

  /// 放たれて高速で回る。
  rush,

  /// 減速していく。
  slowdown,

  /// 止まりかけのまま、当選区画までゆっくり進む。
  creep,
}

/// 1回のスピン。
///
/// 逆回しの溜め（[windupDuration]）→ 高速回転から減速 → 止まりかけのまま
/// [creepAngle] だけゆっくり進む（[creepDuration]）、の順に動き、
/// [duration] 経過時に [endAngle] で止まる。
class SpinPlan {
  /// 当選区画と開始・終了角、所要時間を指定して作る。
  const new({
    required this.winnerIndex,
    required this.startAngle,
    required this.endAngle,
    required this.duration,
    required this.creepAngle,
    this.windupAngle = 0.25,
    this.windupDuration = const Duration(milliseconds: 900),
    this.creepDuration = const Duration(milliseconds: 2800),
  });

  /// 当選した区画。
  final int winnerIndex;

  /// 開始時の回転角（ラジアン）。
  final double startAngle;

  /// 停止時の回転角（ラジアン）。
  final double endAngle;

  /// 開始から停止までの時間。
  final Duration duration;

  /// 溜めで逆回しする角度。
  final double windupAngle;

  /// 溜めの時間。
  final Duration windupDuration;

  /// 最後にゆっくり進む角度。
  final double creepAngle;

  /// 最後にゆっくり進む時間。
  final Duration creepDuration;

  double get _durationSeconds => _seconds(duration);
  double get _windupSeconds => _seconds(windupDuration);
  double get _creepSeconds => _seconds(creepDuration);
  double get _mainSeconds => _durationSeconds - _windupSeconds - _creepSeconds;

  /// 減速の終わり（粘りの始まり）の角度と速度（ラジアン毎秒）。
  double get _creepStartAngle => endAngle - creepAngle;
  double get _creepStartSpeed => 2 * creepAngle / _creepSeconds;

  /// 経過秒数に対する進捗（0〜1）。
  double progressAt(double elapsedSeconds) =>
      (elapsedSeconds / _durationSeconds).clamp(0.0, 1.0);

  /// 経過秒数に対する段階。
  SpinPhase phaseAt(double elapsedSeconds) {
    if (elapsedSeconds < _windupSeconds) return SpinPhase.windup;
    final creepStart = _durationSeconds - _creepSeconds;
    if (elapsedSeconds >= creepStart) return SpinPhase.creep;
    final mainProgress = (elapsedSeconds - _windupSeconds) / _mainSeconds;
    return mainProgress < 0.3 ? SpinPhase.rush : SpinPhase.slowdown;
  }

  /// 経過秒数に対する回転角。
  double angleAt(double elapsedSeconds) {
    final t = elapsedSeconds.clamp(0.0, _durationSeconds);

    // 溜め: sin² で逆回しし、終端で速度0になる。
    if (t < _windupSeconds) {
      final s = math.sin(math.pi / 2 * t / _windupSeconds);
      return startAngle - windupAngle * s * s;
    }

    // 粘り: 一定の減速度で速度0まで落とす。
    final creepStart = _durationSeconds - _creepSeconds;
    if (t >= creepStart) {
      final u = t - creepStart;
      final v0 = _creepStartSpeed;
      return _creepStartAngle + v0 * u - v0 / (2 * _creepSeconds) * u * u;
    }

    // 本体: easeOutQuart に線形成分を混ぜ、終端の速度を粘りの初速に合わせる。
    final from = startAngle - windupAngle;
    final distance = _creepStartAngle - from;
    final u = (t - _windupSeconds) / _mainSeconds;
    final k = _creepStartSpeed * _mainSeconds / distance;
    final eased = (1 - k) * (1 - math.pow(1 - u, 4)) + k * u;
    return from + distance * eased;
  }

  /// 経過秒数に対する角速度（ラジアン毎秒）。
  double speedAt(double elapsedSeconds) {
    const h = 1 / 240;
    return (angleAt(elapsedSeconds + h) - angleAt(elapsedSeconds - h)) /
        (2 * h);
  }

  /// 経過秒数の時点で停止しているか。
  bool isFinishedAt(double elapsedSeconds) =>
      elapsedSeconds >= _durationSeconds;
}

double _seconds(Duration d) =>
    d.inMicroseconds / Duration.microsecondsPerSecond;

/// 当選者を先に決め、その区画でポインタが止まるスピンを作る。
///
/// 区画の中央ちょうどに止まらないよう、区画幅の ±35% の範囲でずらす。
/// 最後の粘りは区画数に応じて1.5〜2.5区画ぶん（最大30°）進む。
SpinPlan planSpin({
  required double currentAngle,
  required int count,
  required math.Random random,
  int minTurns = 10,
  int extraTurns = 2,
  Duration duration = const Duration(seconds: 14),
}) {
  final winnerIndex = random.nextInt(count);
  final sector = sectorAngle(count);
  final jitter = (random.nextDouble() - 0.5) * 0.7 * sector;
  final targetOnWheel = (winnerIndex + 0.5) * sector + jitter;

  // ポインタの下に targetOnWheel が来る回転角を、現在角から minTurns 周以上
  // 先の位置で求める。
  final baseAngle = targetOnWheel - pointerAngle;
  final minEnd = currentAngle + minTurns * 2 * math.pi;
  final turnsToMin = ((minEnd - baseAngle) / (2 * math.pi)).ceil();
  final turns = turnsToMin + random.nextInt(extraTurns + 1);
  final endAngle = baseAngle + turns * 2 * math.pi;

  final creepAngle = math.min(
    (1.5 + random.nextDouble()) * sector,
    math.pi / 6,
  );

  return SpinPlan(
    winnerIndex: winnerIndex,
    startAngle: currentAngle,
    endAngle: endAngle,
    duration: duration,
    creepAngle: creepAngle,
  );
}
