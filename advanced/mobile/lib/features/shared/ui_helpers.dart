import 'package:flutter/material.dart';

const watchStatuses = <String, String>{
  'plan_to_watch': 'قصد دارم تماشا کنم',
  'watching': 'در حال تماشا',
  'completed': 'مشاهده‌شده',
  'paused': 'متوقف‌شده',
  'dropped': 'رهاشده',
};

const libraryStatuses = <String, String>{
  ...watchStatuses,
  'favorite': 'موردعلاقه',
};

String watchStatusLabel(String? value) => watchStatuses[value] ?? 'بدون وضعیت';

String firstCharacter(String value, {String fallback = '؟'}) {
  final normalized = value.trim();
  if (normalized.isEmpty) return fallback;
  return String.fromCharCode(normalized.runes.first);
}

String mediaTypeLabel(String value) => value == 'series' ? 'سریال' : 'فیلم';

String releaseStatusLabel(String? value) => switch (value) {
      'ongoing' => 'در حال پخش',
      'ended' => 'پایان‌یافته',
      'released' => 'منتشرشده',
      'upcoming' => 'به‌زودی',
      _ => value?.isNotEmpty == true ? value! : 'نامشخص',
    };

String activityLabel(String kind) => switch (kind) {
      'watch_status' => 'وضعیت تماشا',
      'favorite' => 'علاقه‌مندی',
      'rating' => 'امتیاز',
      'comment' => 'نظر',
      'episode' => 'قسمت مشاهده‌شده',
      'custom_list' => 'فهرست شخصی',
      _ => kind,
    };

String formatDate(DateTime? value) {
  if (value == null) return '—';
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

Color colorFromHex(String value, {Color fallback = const Color(0xFF212121)}) {
  final normalized = value.replaceAll('#', '').trim();
  if (normalized.length != 6 && normalized.length != 8) return fallback;
  final withAlpha = normalized.length == 6 ? 'FF$normalized' : normalized;
  return Color(int.tryParse(withAlpha, radix: 16) ?? fallback.toARGB32());
}

String minutesLabel(int? minutes) {
  if (minutes == null || minutes <= 0) return '—';
  final hours = minutes ~/ 60;
  final remaining = minutes % 60;
  if (hours == 0) return '$remaining دقیقه';
  if (remaining == 0) return '$hours ساعت';
  return '$hours ساعت و $remaining دقیقه';
}
