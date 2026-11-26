import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/camera/filters.dart';
import 'package:photobooth/camera/grade.dart';

void main() {
  const grey = [0.5, 0.5, 0.5];
  List<double> on(PhotoGrade g, [List<double> c = grey]) => g.apply(c[0], c[1], c[2]);

  test('neutral grade changes nothing, and the LUT stays the filter\'s own', () {
    for (final c in [grey, const [0.1, 0.4, 0.9], const [1.0, 0.0, 0.3]]) {
      final out = on(PhotoGrade.none, c);
      for (var i = 0; i < 3; i++) {
        expect(out[i], closeTo(c[i], 1e-9));
      }
    }
    final f = BoothFilter.values.first;
    expect(buildLut(f, grade: PhotoGrade.none).rgb, buildLut(f).rgb);
    expect(buildLut(f, grade: const PhotoGrade(vignette: 0.5, corner: 30)).rgb, buildLut(f).rgb,
        reason: 'vignette and corners are not colours');
  });

  test('each slider moves the picture the way its name says', () {
    expect(on(const PhotoGrade(exposure: 0.5))[1], greaterThan(0.6));
    expect(on(const PhotoGrade(exposure: -0.5))[1], lessThan(0.4));
    expect(on(const PhotoGrade(brightness: 0.5))[1], greaterThan(0.55));
    // Brightness keeps black and white.
    expect(on(const PhotoGrade(brightness: 1), const [0, 0, 0]), [0, 0, 0]);
    expect(on(const PhotoGrade(brightness: 1), const [1, 1, 1]), [1, 1, 1]);
    // Contrast: darks darker, lights lighter.
    expect(on(const PhotoGrade(contrast: 0.8), const [0.3, 0.3, 0.3])[0], lessThan(0.3));
    expect(on(const PhotoGrade(contrast: 0.8), const [0.7, 0.7, 0.7])[0], greaterThan(0.7));
    // Highlights move the bright tones, not the dark ones (and shadows the other way round).
    expect(on(const PhotoGrade(highlights: -1), const [0.9, 0.9, 0.9])[0], lessThan(0.85));
    expect(on(const PhotoGrade(highlights: -1), const [0.1, 0.1, 0.1])[0], closeTo(0.1, 0.005));
    expect(on(const PhotoGrade(shadows: 1), const [0.1, 0.1, 0.1])[0], greaterThan(0.2));
    expect(on(const PhotoGrade(shadows: 1), const [0.95, 0.95, 0.95])[0], closeTo(0.95, 0.005));
    // Warm: red above blue; cool: the other way.
    final warm = on(const PhotoGrade(temperature: 0.8));
    expect(warm[0], greaterThan(warm[2] + 0.1));
    final cool = on(const PhotoGrade(temperature: -0.8));
    expect(cool[2], greaterThan(cool[0] + 0.1));
    // Tint +: magenta (green down); −: green.
    final pink = on(const PhotoGrade(tint: 1));
    expect(pink[1], lessThan(pink[0]));
    // Saturation −1: grey.
    final mono = on(const PhotoGrade(saturation: -1), const [0.8, 0.3, 0.2]);
    expect(mono[0], closeTo(mono[2], 1e-6));
    // Vibrance boosts a muted colour more than a strong one.
    double spread(List<double> c) => c.reduce((a, b) => a > b ? a : b) - c.reduce((a, b) => a < b ? a : b);
    const muted = [0.55, 0.5, 0.45], strong = [0.9, 0.2, 0.1];
    final gainMuted = spread(on(const PhotoGrade(vibrance: 1), muted)) / spread(muted);
    final gainStrong = spread(on(const PhotoGrade(vibrance: 1), strong)) / spread(strong);
    expect(gainMuted, greaterThan(gainStrong));
  });

  test('saved as JSON, clamped when read back, vignette reaches the clip look', () {
    const g = PhotoGrade(exposure: 0.2, temperature: -0.4, vignette: 0.3, corner: 40);
    expect(PhotoGrade.decode(g.encode()), g);
    expect(PhotoGrade.decode(null), PhotoGrade.none);
    expect(PhotoGrade.decode('nonsense'), PhotoGrade.none);
    expect(PhotoGrade.decode('{"exposure": 9, "corner": 500}'), const PhotoGrade(exposure: 1, corner: PhotoGrade.maxCorner));
    final f = BoothFilter.values.first;
    expect(f.look(grade: g).vignette, closeTo(f.recipe.vignette + 0.3, 1e-9));
    // A warm grade warms every filter's LUT (mid grey entry).
    final plain = buildLut(f, size: 3).rgb, warm = buildLut(f, size: 3, grade: const PhotoGrade(temperature: 1)).rgb;
    const mid = (1 + 1 * 3 + 1 * 9) * 3;
    expect(warm[mid] - warm[mid + 2], greaterThan(plain[mid] - plain[mid + 2] + 0.05));
  });
}
