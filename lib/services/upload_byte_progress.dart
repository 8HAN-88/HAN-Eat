/// Доля полосы загрузки по байтам, которые уже ушли в сеть.
///
/// Полностью отправленное тело — это 95%. Оставшиеся проценты — ответ
/// сервера, который сохраняет файл. Раньше 100% локального буфера
/// рисовались как 88%, и кружок стоял на этой отметке всю отправку.
double mediaUploadFraction(int sentBytes, int totalBytes) {
  final safeTotal = totalBytes <= 0 ? 1 : totalBytes;
  final ratio = (sentBytes / safeTotal).clamp(0.0, 1.0).toDouble();
  return 0.05 + ratio * 0.90;
}
