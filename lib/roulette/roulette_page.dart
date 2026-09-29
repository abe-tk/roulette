import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart';
import 'package:roulette/nickname/nickname_master.dart';
import 'package:roulette/roulette/roulette_stage.dart';
import 'package:roulette/roulette/wheel_texture.dart';

/// ニックネームマスタを読み込み、ルーレットを表示する画面。
class RoulettePage extends StatefulWidget {
  /// 画面を作る。
  const new({super.key});

  @override
  State<RoulettePage> createState() => _RoulettePageState();
}

class _RoulettePageState extends State<RoulettePage> {
  RouletteStage? _stage;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final names = await loadNicknames();
      final wheelImage = await paintWheelImage(names);
      final backdropImage = await paintBackdropImage();
      final glowImage = await paintGlowImage();
      await Scene.initializeStaticResources();
      final wheelTexture = await Texture2D.fromImage(wheelImage);
      final backdropTexture = await Texture2D.fromImage(backdropImage);
      final glowTexture = await Texture2D.fromImage(glowImage);
      wheelImage.dispose();
      backdropImage.dispose();
      glowImage.dispose();
      if (!mounted) return;
      setState(
        () => _stage = RouletteStage(
          names: names,
          wheelTexture: wheelTexture,
          backdropTexture: backdropTexture,
          glowTexture: glowTexture,
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _stage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stage = _stage;
    return Scaffold(
      body: switch ((stage, _error)) {
        (_, final Object error) => _ErrorView(error: error),
        (null, _) => const Center(child: CircularProgressIndicator()),
        (final RouletteStage stage, _) => _RouletteView(stage: stage),
      },
    );
  }
}

class _RouletteView extends StatelessWidget {
  const new({required this.stage});

  final RouletteStage stage;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): stage.spin,
        const SingleActivator(LogicalKeyboardKey.enter): stage.spin,
      },
      child: Focus(
        autofocus: true,
        child: Stack(
          children: [
            Positioned.fill(
              child: SceneView(
                stage.scene,
                cameraBuilder: (_) => stage.camera,
                onTick: (_, deltaSeconds) => stage.tick(deltaSeconds),
              ),
            ),
            Positioned(
              left: 24,
              top: 20,
              child: Text(
                '${stage.names.length}名',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 32,
              child: _ResultPanel(stage: stage),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const new({required this.stage});

  final RouletteStage stage;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        stage.phase,
        stage.pointedIndex,
        stage.winnerIndex,
      ]),
      builder: (context, _) {
        final winner = stage.winnerIndex.value;
        final child = switch (stage.phase.value) {
          StagePhase.idle => const _StartHint(),
          StagePhase.windup => const SizedBox.shrink(),
          StagePhase.celebrate when winner != null => _WinnerCard(
            key: ValueKey(Object.hash(winner, stage.names.length)),
            name: stage.names[winner],
          ),
          final phase => _Ticker(
            name: stage.names[stage.pointedIndex.value],
            tense: phase == StagePhase.creep,
          ),
        };
        return Center(child: child);
      },
    );
  }
}

/// 待機中に出すスタートの案内。ゆっくり明滅する。
class _StartHint extends StatefulWidget {
  const new();

  @override
  State<_StartHint> createState() => _StartHintState();
}

class _StartHintState extends State<_StartHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(_controller),
      child: Text(
        'SPACE でスタート',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: const Color(0xFFFFE08A),
          letterSpacing: 4,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// スピン中にポインタが指している名前。粘りの間は赤く大きくする。
class _Ticker extends StatelessWidget {
  const new({required this.name, required this.tense});

  final String name;
  final bool tense;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      padding: EdgeInsets.symmetric(
        horizontal: tense ? 40 : 32,
        vertical: tense ? 16 : 12,
      ),
      decoration: BoxDecoration(
        color: const Color(0xB3000000),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: tense ? const Color(0xFFFF3040) : const Color(0x55FFFFFF),
          width: tense ? 3 : 1,
        ),
        boxShadow: [
          if (tense)
            const BoxShadow(
              color: Color(0x99FF2030),
              blurRadius: 32,
              spreadRadius: 2,
            ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tense ? 'まもなく決定…！' : '抽選中…', style: textTheme.labelLarge),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 400),
            style: (tense ? textTheme.displayMedium : textTheme.displaySmall)!
                .copyWith(fontWeight: FontWeight.bold, color: Colors.white),
            child: Text(name),
          ),
        ],
      ),
    );
  }
}

/// 当選者の発表。弾むように現れ、金色の光がゆっくり脈打つ。
class _WinnerCard extends StatefulWidget {
  const new({required this.name, super.key});

  final String name;

  @override
  State<_WinnerCard> createState() => _WinnerCardState();
}

class _WinnerCardState extends State<_WinnerCard>
    with TickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _enter.dispose();
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scale = CurvedAnimation(parent: _enter, curve: Curves.elasticOut);
    return ScaleTransition(
      scale: Tween<double>(begin: 0.2, end: 1).animate(scale),
      child: AnimatedBuilder(
        animation: _glow,
        builder: (context, child) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFF1B8), Color(0xFFE0A526), Color(0xFFB8740B)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFFFF6D8), width: 3),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFC23A)
                    .withValues(alpha: 0.45 + 0.4 * _glow.value),
                blurRadius: 30 + 30 * _glow.value,
                spreadRadius: 4 + 6 * _glow.value,
              ),
            ],
          ),
          child: child,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '当選おめでとうございます！',
              style: textTheme.titleMedium?.copyWith(
                color: const Color(0xFF5A2E00),
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            Text(
              widget.name,
              style: textTheme.displayLarge?.copyWith(
                color: const Color(0xFF3A1600),
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const new({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final message = error is FormatException
        ? (error as FormatException).message
        : error.toString();
    return Center(
      child: Text('読み込みに失敗しました\n$message', textAlign: TextAlign.center),
    );
  }
}
