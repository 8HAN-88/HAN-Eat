/// Те же доли, что `backend/app/core/revenue_share.py`.
class RevenueSharePolicy {
  const RevenueSharePolicy._();

  static const int netFactorBps = 7000;
  static const int referrerOfNetBps = 2500;
  static const int userAdOfNetBps = 5000;
  static const int referralDays = 365;
  static const int holdDays = 14;
  static const int kopecksPerStar = 80;
  static const int minCardPayoutKopecks = 50000;

  static int convertibleStars(int availableKopecks) {
    if (availableKopecks <= 0) return 0;
    return availableKopecks ~/ kopecksPerStar;
  }

  static RevenueShareSplit splitKopecks({
    required int gross,
    required String source,
    required bool extraAds,
    required bool hasReferrer,
  }) {
    if (gross <= 0) {
      return const RevenueShareSplit();
    }
    final net = gross * netFactorBps ~/ 10000;
    var user = 0;
    if (source == 'ads' && extraAds) {
      user = net * userAdOfNetBps ~/ 10000;
    }
    var referrer = hasReferrer ? net * referrerOfNetBps ~/ 10000 : 0;
    if (user + referrer > net) {
      referrer = (net - user).clamp(0, net);
    }
    final company = (net - user - referrer).clamp(0, net);
    return RevenueShareSplit(
      gross: gross,
      net: net,
      user: user,
      referrer: referrer,
      company: company,
    );
  }
}

class RevenueShareSplit {
  const RevenueShareSplit({
    this.gross = 0,
    this.net = 0,
    this.user = 0,
    this.referrer = 0,
    this.company = 0,
  });

  final int gross;
  final int net;
  final int user;
  final int referrer;
  final int company;
}
