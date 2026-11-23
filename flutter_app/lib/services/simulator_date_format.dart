/// Presentation and input parsing for simulator dates.
///
/// This formatter never participates in payload construction: API values remain
/// ISO 8601 strings produced from the original DateTime objects.
class SimulatorDateFormat {
  const SimulatorDateFormat._();

  static String format(DateTime value) {
    final date = '${value.day.toString().padLeft(2, '0')}/'
        '${value.month.toString().padLeft(2, '0')}/'
        '${(value.year % 100).toString().padLeft(2, '0')}';
    if (value.hour == 0 && value.minute == 0 && value.second == 0) {
      return date;
    }
    return '$date ${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }

  static DateTime? parse(String input) {
    final text = input.trim();
    final brazilian = RegExp(
      r'^(\d{1,2})/(\d{1,2})/(\d{2}|\d{4})(?:\s+(\d{1,2}):(\d{2}))?$',
    ).firstMatch(text);
    if (brazilian != null) {
      final day = int.parse(brazilian.group(1)!);
      final month = int.parse(brazilian.group(2)!);
      final rawYear = int.parse(brazilian.group(3)!);
      final year = rawYear < 100 ? 2000 + rawYear : rawYear;
      final hour = int.tryParse(brazilian.group(4) ?? '0') ?? 0;
      final minute = int.tryParse(brazilian.group(5) ?? '0') ?? 0;
      final date = DateTime(year, month, day, hour, minute);
      if (date.year != year ||
          date.month != month ||
          date.day != day ||
          date.hour != hour ||
          date.minute != minute) {
        return null;
      }
      return date;
    }
    return DateTime.tryParse(text.replaceFirst(' ', 'T'));
  }
}
