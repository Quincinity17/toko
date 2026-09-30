import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';

/// Kurva berbasis simulasi pegas, meniru animasi `spring` di iOS/SwiftUI.
///
/// [dampingRatio] < 1 memberi sedikit pantulan; 1 = critically damped.
class SpringCurve extends Curve {
  SpringCurve({this.dampingRatio = 0.82, this.stiffness = 180})
    : _simulation = SpringSimulation(
        SpringDescription.withDampingRatio(
          mass: 1,
          stiffness: stiffness,
          ratio: dampingRatio,
        ),
        0,
        1,
        0,
      ),
      _duration = _settleTime(dampingRatio, stiffness);

  final double dampingRatio;
  final double stiffness;
  final SpringSimulation _simulation;
  final double _duration;

  /// Kurva standar untuk transisi halaman dan sheet.
  static final smooth = SpringCurve();

  /// Sedikit memantul, untuk item masuk keranjang dan elemen kecil.
  static final bouncy = SpringCurve(dampingRatio: 0.62, stiffness: 260);

  static double _settleTime(double ratio, double stiffness) {
    final sim = SpringSimulation(
      SpringDescription.withDampingRatio(
        mass: 1,
        stiffness: stiffness,
        ratio: ratio,
      ),
      0,
      1,
      0,
      tolerance: const Tolerance(distance: 0.001, velocity: 0.001),
    );
    var t = 0.0;
    while (!sim.isDone(t) && t < 5) {
      t += 1 / 120;
    }
    return t;
  }

  @override
  double transformInternal(double t) => _simulation.x(t * _duration);
}
