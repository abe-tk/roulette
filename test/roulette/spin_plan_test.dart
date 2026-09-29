import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:roulette/roulette/spin_plan.dart';

void main() {
  group('indexAtPointer', () {
    test('回転角0では pointerAngle を含む区画を指す', () {
      expect(indexAtPointer(0, 4), 1);
    });

    test('負の角度や複数周でも 0..count-1 に収まる', () {
      for (final angle in [-100.0, -0.001, 0.0, 12.3, 1000.0]) {
        final index = indexAtPointer(angle, 500);
        expect(index, inInclusiveRange(0, 499));
      }
    });
  });

  group('planSpin', () {
    for (final count in [1, 2, 7, 500]) {
      test('$count件: 停止位置で当選区画を指し、最低周回数以上回る', () {
        final random = math.Random(count);
        var angle = 0.0;
        for (var i = 0; i < 200; i++) {
          final plan = planSpin(
            currentAngle: angle,
            count: count,
            random: random,
          );
          expect(plan.startAngle, angle);
          expect(
            plan.endAngle - plan.startAngle,
            greaterThan(10 * 2 * math.pi),
          );
          expect(indexAtPointer(plan.endAngle, count), plan.winnerIndex);
          angle = plan.endAngle % (2 * math.pi);
        }
      });
    }

    test('開始時と終了時の角度、終了判定', () {
      final plan = planSpin(currentAngle: 1, count: 10, random: math.Random(1));
      expect(plan.angleAt(0), plan.startAngle);
      expect(plan.angleAt(14), closeTo(plan.endAngle, 1e-9));
      expect(plan.isFinishedAt(13.99), isFalse);
      expect(plan.isFinishedAt(14), isTrue);
    });

    for (final count in [1, 7, 500]) {
      test('$count件: 溜めで逆回しした後は止まるまで逆戻りしない', () {
        final plan = planSpin(
          currentAngle: 0.5,
          count: count,
          random: math.Random(count),
        );
        const step = 1 / 120;
        var previous = plan.angleAt(0);
        var minAngle = previous;
        var t = step;
        for (; t < 0.9; t += step) {
          final angle = plan.angleAt(t);
          expect(angle, lessThanOrEqualTo(previous + 1e-12));
          minAngle = math.min(minAngle, angle);
          previous = angle;
        }
        expect(minAngle, lessThan(plan.startAngle));
        for (; t <= 14; t += step) {
          final angle = plan.angleAt(t);
          expect(angle, greaterThanOrEqualTo(previous - 1e-9));
          previous = angle;
        }
      });

      test('$count件: 区間の境目で角度がつながり、粘りへは速度もつながる', () {
        final plan = planSpin(
          currentAngle: 0,
          count: count,
          random: math.Random(count),
        );
        // 溜めから放つ瞬間は急発進させるため、速度は角度だけ確かめる。
        for (final boundary in [0.9, 14 - 2.8]) {
          expect(
            plan.angleAt(boundary + 1e-6) - plan.angleAt(boundary - 1e-6),
            closeTo(0, 1e-3),
          );
        }
        const creepStart = 14 - 2.8;
        expect(
          plan.speedAt(creepStart + 0.01),
          closeTo(plan.speedAt(creepStart - 0.01), 0.05),
        );
        expect(plan.speedAt(14 - 1e-3), closeTo(0, 1e-2));
      });
    }

    test('段階は溜め→高速→減速→粘りの順に進む', () {
      final plan = planSpin(currentAngle: 0, count: 50, random: math.Random(3));
      final phases = [for (var t = 0.0; t < 14; t += 0.05) plan.phaseAt(t)];
      final order = <SpinPhase>[];
      for (final phase in phases) {
        if (order.isEmpty || order.last != phase) order.add(phase);
      }
      expect(order, SpinPhase.values);
    });

    test('粘りの角度は区画数によらず30°以下', () {
      for (final count in [1, 2, 7, 500]) {
        final plan = planSpin(
          currentAngle: 0,
          count: count,
          random: math.Random(count),
        );
        expect(plan.creepAngle, lessThanOrEqualTo(math.pi / 6));
        expect(plan.creepAngle, greaterThan(0));
      }
    });

    test('全区画が当選しうる', () {
      final random = math.Random(42);
      final winners = {
        for (var i = 0; i < 2000; i++)
          planSpin(currentAngle: 0, count: 20, random: random).winnerIndex,
      };
      expect(winners, hasLength(20));
    });
  });
}
