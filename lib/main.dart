import 'package:flame/flame.dart';
import 'package:flutter/material.dart';

import 'app.dart';

export 'app.dart';

void main() {
  Flame.images.prefix = '';
  runApp(const BattleGameApp());
}
