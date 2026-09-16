import 'dart:math' as math;

/// Lightweight, self-contained Matrix class for Kalman Filter linear algebra.
///
/// Designed for small matrices (e.g. 6x6, 6x5, 5x5) with zero external dependencies.
class EkfMatrix {
  EkfMatrix(this.rows, this.cols, [List<double>? data])
      : data = data ?? List<double>.filled(rows * cols, 0.0);

  final int rows;
  final int cols;
  final List<double> data;

  factory EkfMatrix.zeros(int rows, int cols) =>
      EkfMatrix(rows, cols, List<double>.filled(rows * cols, 0.0));

  factory EkfMatrix.identity(int size) {
    final m = EkfMatrix.zeros(size, size);
    for (var i = 0; i < size; i++) {
      m.set(i, i, 1.0);
    }
    return m;
  }

  factory EkfMatrix.diagonal(List<double> diag) {
    final size = diag.length;
    final m = EkfMatrix.zeros(size, size);
    for (var i = 0; i < size; i++) {
      m.set(i, i, diag[i]);
    }
    return m;
  }

  factory EkfMatrix.fromRows(List<List<double>> rowData) {
    final r = rowData.length;
    final c = rowData.isEmpty ? 0 : rowData[0].length;
    final flat = <double>[];
    for (final row in rowData) {
      assert(row.length == c, 'All rows must have same number of columns');
      flat.addAll(row);
    }
    return EkfMatrix(r, c, flat);
  }

  double get(int r, int c) => data[r * cols + c];

  void set(int r, int c, double value) {
    data[r * cols + c] = value;
  }

  EkfMatrix clone() => EkfMatrix(rows, cols, List<double>.from(data));

  EkfMatrix transpose() {
    final result = EkfMatrix.zeros(cols, rows);
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        result.set(c, r, get(r, c));
      }
    }
    return result;
  }

  EkfMatrix add(EkfMatrix other) {
    assert(rows == other.rows && cols == other.cols, 'Matrix dimensions must match for addition');
    final result = List<double>.filled(data.length, 0.0);
    for (var i = 0; i < data.length; i++) {
      result[i] = data[i] + other.data[i];
    }
    return EkfMatrix(rows, cols, result);
  }

  EkfMatrix subtract(EkfMatrix other) {
    assert(rows == other.rows && cols == other.cols, 'Matrix dimensions must match for subtraction');
    final result = List<double>.filled(data.length, 0.0);
    for (var i = 0; i < data.length; i++) {
      result[i] = data[i] - other.data[i];
    }
    return EkfMatrix(rows, cols, result);
  }

  EkfMatrix multiply(EkfMatrix other) {
    assert(cols == other.rows, 'Matrix cols must match other rows for multiplication');
    final result = EkfMatrix.zeros(rows, other.cols);
    for (var r = 0; r < rows; r++) {
      for (var k = 0; k < cols; k++) {
        final a = get(r, k);
        if (a == 0.0) continue;
        for (var c = 0; c < other.cols; c++) {
          final current = result.get(r, c);
          result.set(r, c, current + a * other.get(k, c));
        }
      }
    }
    return result;
  }

  List<double> multiplyVector(List<double> vec) {
    assert(cols == vec.length, 'Matrix cols must match vector length');
    final result = List<double>.filled(rows, 0.0);
    for (var r = 0; r < rows; r++) {
      var sum = 0.0;
      for (var c = 0; c < cols; c++) {
        sum += get(r, c) * vec[c];
      }
      result[r] = sum;
    }
    return result;
  }

  EkfMatrix scale(double s) {
    final result = List<double>.filled(data.length, 0.0);
    for (var i = 0; i < data.length; i++) {
      result[i] = data[i] * s;
    }
    return EkfMatrix(rows, cols, result);
  }

  /// Inverts a square matrix using Gauss-Jordan elimination with partial pivoting.
  /// If the matrix is ill-conditioned or singular, Tikhonov regularization is added
  /// to ensure numerical stability and prevent NaN crashes.
  EkfMatrix inverse({double regularization = 1e-9}) {
    assert(rows == cols, 'Matrix must be square to invert');
    final n = rows;

    // Create augmented matrix [A | I]
    final aug = List.generate(n, (r) {
      final row = List<double>.filled(2 * n, 0.0);
      for (var c = 0; c < n; c++) {
        var val = get(r, c);
        if (r == c) val += regularization; // Tikhonov regularization
        row[c] = val;
      }
      row[n + r] = 1.0;
      return row;
    });

    // Gauss-Jordan elimination
    for (var i = 0; i < n; i++) {
      // Find pivot
      var maxRow = i;
      var maxVal = aug[i][i].abs();
      for (var r = i + 1; r < n; r++) {
        if (aug[r][i].abs() > maxVal) {
          maxVal = aug[r][i].abs();
          maxRow = r;
        }
      }

      // Swap rows
      if (maxRow != i) {
        final temp = aug[i];
        aug[i] = aug[maxRow];
        aug[maxRow] = temp;
      }

      final pivot = aug[i][i];
      if (pivot.abs() < 1e-12) {
        // Degenerate pivot: fallback to diagonal approximation
        return _diagonalInverseFallback();
      }

      // Normalize pivot row
      final invPivot = 1.0 / pivot;
      for (var c = i; c < 2 * n; c++) {
        aug[i][c] *= invPivot;
      }

      // Eliminate other rows
      for (var r = 0; r < n; r++) {
        if (r != i) {
          final factor = aug[r][i];
          if (factor.abs() > 1e-15) {
            for (var c = i; c < 2 * n; c++) {
              aug[r][c] -= factor * aug[i][c];
            }
          }
        }
      }
    }

    // Extract right side
    final inv = EkfMatrix.zeros(n, n);
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        final val = aug[r][n + c];
        inv.set(r, c, val.isNaN || val.isInfinite ? 0.0 : val);
      }
    }
    return inv;
  }

  EkfMatrix _diagonalInverseFallback() {
    final n = rows;
    final fallback = EkfMatrix.zeros(n, n);
    for (var i = 0; i < n; i++) {
      final diag = get(i, i);
      fallback.set(i, i, diag.abs() > 1e-6 ? 1.0 / diag : 1.0);
    }
    return fallback;
  }

  /// Ensures matrix remains symmetric by averaging A with A^T
  EkfMatrix makeSymmetric() {
    assert(rows == cols);
    final res = EkfMatrix.zeros(rows, cols);
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (r == c) {
          res.set(r, c, get(r, c));
        } else {
          final avg = (get(r, c) + get(c, r)) * 0.5;
          res.set(r, c, avg);
        }
      }
    }
    return res;
  }

  @override
  String toString() {
    final sb = StringBuffer();
    sb.writeln('EkfMatrix ($rows x $cols):');
    for (var r = 0; r < rows; r++) {
      sb.write(' [');
      for (var c = 0; c < cols; c++) {
        sb.write(get(r, c).toStringAsFixed(4).padLeft(8));
        if (c < cols - 1) sb.write(', ');
      }
      sb.writeln(']');
    }
    return sb.toString();
  }
}
