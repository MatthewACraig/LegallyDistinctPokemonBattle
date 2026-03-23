import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SpriteSheetActor extends StatefulWidget {
  const SpriteSheetActor({
    super.key,
    required this.assetPath,
    this.animationKey,
    this.width,
    this.height,
    this.flipX = false,
    this.stepTime = 0.09,
    this.loop = true,
    this.playing = true,
  });

  final String assetPath;
  final Object? animationKey;
  final double? width;
  final double? height;
  final bool flipX;
  final double stepTime;
  final bool loop;
  final bool playing;

  @override
  State<SpriteSheetActor> createState() => _SpriteSheetActorState();
}

class _SpriteSheetActorState extends State<SpriteSheetActor> {
  static final Map<String, _SpriteSheetMeta> _cache = <String, _SpriteSheetMeta>{};

  _SpriteSheetMeta? _meta;
  SpriteAnimationData? _animationData;

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  @override
  void didUpdateWidget(covariant SpriteSheetActor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetPath != widget.assetPath) {
      _meta = null;
      _animationData = null;
      _loadMeta();
      return;
    }

    if (oldWidget.stepTime != widget.stepTime || oldWidget.loop != widget.loop) {
      _rebuildAnimationData();
    }
  }

  void _rebuildAnimationData() {
    final meta = _meta;
    if (meta == null || meta.frameCount <= 1) {
      _animationData = null;
      return;
    }

    _animationData = SpriteAnimationData.sequenced(
      amount: meta.frameCount,
      stepTime: widget.stepTime,
      textureSize: Vector2(meta.frameWidth, meta.frameHeight),
      loop: widget.loop,
    );
  }

  Future<void> _loadMeta() async {
    final cached = _cache[widget.assetPath];
    if (cached != null) {
      setState(() {
        _meta = cached;
      });
      return;
    }

    final ByteData data = await rootBundle.load(widget.assetPath);
    final Uint8List bytes = data.buffer.asUint8List();
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image image = frame.image;

    final int width = image.width;
    final int height = image.height;
    final int frameCount = max(1, (width / height).floor());
    final double frameWidth = width / frameCount;

    final meta = _SpriteSheetMeta(
      frameCount: frameCount,
      frameWidth: frameWidth,
      frameHeight: height.toDouble(),
    );

    _cache[widget.assetPath] = meta;
    if (!mounted) {
      return;
    }
    setState(() {
      _meta = meta;
    });
  }

  @override
  Widget build(BuildContext context) {
    final meta = _meta;

    Widget sprite;
    if (meta == null || meta.frameCount <= 1) {
      sprite = Image.asset(widget.assetPath, fit: BoxFit.contain);
    } else {
      _animationData ??= SpriteAnimationData.sequenced(
        amount: meta.frameCount,
        stepTime: widget.stepTime,
        textureSize: Vector2(meta.frameWidth, meta.frameHeight),
        loop: widget.loop,
      );

      sprite = SpriteAnimationWidget.asset(
        key: ValueKey<Object>('${widget.assetPath}:${widget.animationKey ?? ''}:${widget.loop}:${widget.stepTime}'),
        path: widget.assetPath,
        data: _animationData!,
        playing: widget.playing,
      );
    }

    final sized = SizedBox(
      width: widget.width,
      height: widget.height,
      child: sprite,
    );

    if (!widget.flipX) {
      return sized;
    }

    return Transform.flip(
      flipX: true,
      child: sized,
    );
  }
}

class _SpriteSheetMeta {
  const _SpriteSheetMeta({
    required this.frameCount,
    required this.frameWidth,
    required this.frameHeight,
  });

  final int frameCount;
  final double frameWidth;
  final double frameHeight;
}
