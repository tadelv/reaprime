class MovingAverage {
  final int windowSize;
  final List<double> _values = [];

  MovingAverage(this.windowSize) {
    if (windowSize <= 0) {
      throw ArgumentError('Window size must be greater than 0');
    }
  }

  void add(double value) {
    _values.add(value);
    if (_values.length > windowSize) {
      _values.removeAt(0);
    }
  }

  double get average {
    if (_values.isEmpty) return 0.0;
    return _values.reduce((a, b) => a + b) / _values.length;
  }
}
