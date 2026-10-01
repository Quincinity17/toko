/// Nominal uang tunai yang mungkin diberikan pelanggan untuk [total],
/// misalnya total 15.680 → 16.000, 20.000, 50.000, 100.000.
List<int> cashSuggestions(int total, {int max = 4}) {
  if (total <= 0) return const [];
  const denominations = [1000, 2000, 5000, 10000, 20000, 50000, 100000];
  final result = <int>{};
  for (final d in denominations) {
    final rounded = (total + d - 1) ~/ d * d;
    if (rounded > total) result.add(rounded);
  }
  // Jika total di atas 100 ribu, tawarkan kelipatan 100 ribu berikutnya juga.
  final next100k = ((total ~/ 100000) + 1) * 100000;
  result.add(next100k);
  return (result.toList()..sort()).take(max).toList();
}
