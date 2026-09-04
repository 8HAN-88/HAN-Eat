import 'package:flutter/material.dart';

Widget buildWebHtmlReelVideo({
  required String url,
  required bool muted,
  required bool playing,
  VoidCallback? onError,
}) {
  onError?.call();
  return const SizedBox.shrink();
}
