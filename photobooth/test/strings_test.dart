import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/camera/filters.dart';
import 'package:photobooth/ui/strings.dart';

void main() {
  test('every language names every filter and has the guest strings', () {
    for (final l in Lang.values) {
      final t = T.of(l);
      for (final f in BoothFilter.values) {
        expect(t.filterNames[f.name], isNotNull, reason: '${l.name} ${f.name}');
      }
      for (final s in [t.start, t.chooseFrame, t.getReady, t.pickBest(4), t.allDone, t.scanToGet, t.printScanHint, t.done]) {
        expect(s.trim(), isNotEmpty, reason: l.name);
      }
    }
  });
}
