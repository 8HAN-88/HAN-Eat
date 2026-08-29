import '../../../services/flex_subscription_service.dart';

List<FlexFeature> flexFeaturesAtLevel(List<FlexFeature> all, int level) {
  final out = [
    for (final feature in all)
      if (feature.assignedLevel == level) feature,
  ];
  out.sort((a, b) => a.title.compareTo(b.title));
  return out;
}

List<FlexFeature> flexFeaturesUnlockedBy(List<FlexFeature> all, int level) {
  final out = [
    for (final feature in all)
      if (feature.assignedLevel <= level) feature,
  ];
  out.sort((a, b) {
    final byLevel = a.assignedLevel.compareTo(b.assignedLevel);
    if (byLevel != 0) return byLevel;
    return a.title.compareTo(b.title);
  });
  return out;
}
