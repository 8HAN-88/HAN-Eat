import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/referral/revenue_share_policy.dart';

void main() {
  test('extra ads + referrer split 35 / 17.5 / 17.5 of pre-expense 100', () {
    final split = RevenueSharePolicy.splitKopecks(
      gross: 10000,
      source: 'ads',
      extraAds: true,
      hasReferrer: true,
    );
    expect(split.net, 7000);
    expect(split.user, 3500);
    expect(split.referrer, 1750);
    expect(split.company, 1750);
  });

  test('without extra ads referrer keeps the same 17.5 points', () {
    final split = RevenueSharePolicy.splitKopecks(
      gross: 10000,
      source: 'ads',
      extraAds: false,
      hasReferrer: true,
    );
    expect(split.user, 0);
    expect(split.referrer, 1750);
    expect(split.company, 5250);
  });

  test('subscription never pays the subscriber', () {
    final split = RevenueSharePolicy.splitKopecks(
      gross: 10000,
      source: 'subscription',
      extraAds: true,
      hasReferrer: true,
    );
    expect(split.user, 0);
    expect(split.referrer, 1750);
  });

  test('convertible stars use 80 kopecks per star', () {
    expect(RevenueSharePolicy.kopecksPerStar, 80);
    expect(RevenueSharePolicy.minCardPayoutKopecks, 50000);
    expect(RevenueSharePolicy.convertibleStars(79), 0);
    expect(RevenueSharePolicy.convertibleStars(80), 1);
    expect(RevenueSharePolicy.convertibleStars(1750), 21);
  });
}
