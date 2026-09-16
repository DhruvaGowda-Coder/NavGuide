import 'package:flutter_test/flutter_test.dart';
import 'package:navguardian_ai/device/fusion/ekf_matrix.dart';

void main() {
  group('EkfMatrix Tests', () {
    test('Identity and matrix multiplication', () {
      final I = EkfMatrix.identity(3);
      final A = EkfMatrix.fromRows([
        [1.0, 2.0, 3.0],
        [4.0, 5.0, 6.0],
        [7.0, 8.0, 9.0],
      ]);

      final product = A.multiply(I);
      for (var r = 0; r < 3; r++) {
        for (var c = 0; c < 3; c++) {
          expect(product.get(r, c), closeTo(A.get(r, c), 1e-6));
        }
      }
    });

    test('Matrix inversion of 2x2 invertible matrix', () {
      final M = EkfMatrix.fromRows([
        [4.0, 7.0],
        [2.0, 6.0],
      ]);

      final inv = M.inverse();
      final identity = M.multiply(inv);

      expect(identity.get(0, 0), closeTo(1.0, 1e-4));
      expect(identity.get(0, 1), closeTo(0.0, 1e-4));
      expect(identity.get(1, 0), closeTo(0.0, 1e-4));
      expect(identity.get(1, 1), closeTo(1.0, 1e-4));
    });

    test('Matrix vector multiplication', () {
      final M = EkfMatrix.fromRows([
        [1.0, 2.0],
        [3.0, 4.0],
      ]);
      final v = [2.0, 3.0];
      final res = M.multiplyVector(v);
      expect(res[0], equals(8.0));
      expect(res[1], equals(18.0));
    });

    test('Transpose symmetry', () {
      final M = EkfMatrix.fromRows([
        [1.0, 2.0],
        [3.0, 4.0],
      ]);
      final sym = M.makeSymmetric();
      expect(sym.get(0, 1), equals(sym.get(1, 0)));
      expect(sym.get(0, 1), equals(2.5));
    });
  });
}
