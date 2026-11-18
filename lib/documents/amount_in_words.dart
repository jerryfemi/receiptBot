/// Spells out an amount the way a handwritten receipt pad does:
/// 1800000 with "₦" -> "One million, eight hundred thousand naira only".
String amountInWords(double amount, String currencySymbol) {
  final whole = amount.floor();
  final cents = ((amount - whole) * 100).round();
  final unit = _currencyWord(currencySymbol);

  final buffer = StringBuffer(_capitalise(_spell(whole)));
  if (unit != null) buffer.write(' $unit');
  if (cents > 0) {
    final minor = _minorWord(currencySymbol);
    buffer.write(minor != null ? ', ${_spell(cents)} $minor' : ' and $cents/100');
  }
  buffer.write(' only');
  return buffer.toString();
}

const _ones = [
  'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', //
  'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen',
  'sixteen', 'seventeen', 'eighteen', 'nineteen',
];
const _tens = [
  '', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', //
  'eighty', 'ninety',
];
const _scales = ['', 'thousand', 'million', 'billion', 'trillion'];

String _spell(int n) {
  if (n == 0) return 'zero';
  final groups = <String>[];
  var scale = 0;
  while (n > 0 && scale < _scales.length) {
    final chunk = n % 1000;
    if (chunk > 0) {
      final words = _belowThousand(chunk);
      groups.insert(0, _scales[scale].isEmpty ? words : '$words ${_scales[scale]}');
    }
    n ~/= 1000;
    scale++;
  }
  return groups.join(', ');
}

String _belowThousand(int n) {
  final parts = <String>[];
  if (n >= 100) {
    parts.add('${_ones[n ~/ 100]} hundred');
    n %= 100;
    if (n > 0) parts.add('and');
  }
  if (n >= 20) {
    final rest = n % 10;
    parts.add(rest == 0 ? _tens[n ~/ 10] : '${_tens[n ~/ 10]}-${_ones[rest]}');
  } else if (n > 0) {
    parts.add(_ones[n]);
  }
  return parts.join(' ');
}

String _capitalise(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

String? _currencyWord(String symbol) {
  switch (symbol.trim()) {
    case '₦':
      return 'naira';
    case r'$':
      return 'dollars';
    case '£':
      return 'pounds';
    case '€':
      return 'euros';
    case '₵':
    case 'GH₵':
      return 'cedis';
    case 'KSh':
      return 'shillings';
    case 'R':
      return 'rand';
    default:
      return null;
  }
}

String? _minorWord(String symbol) {
  switch (symbol.trim()) {
    case '₦':
      return 'kobo';
    case r'$':
    case '€':
      return 'cents';
    case '£':
      return 'pence';
    case '₵':
    case 'GH₵':
      return 'pesewas';
    default:
      return null;
  }
}
