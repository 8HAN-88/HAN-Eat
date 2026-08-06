/// One-shot notice when a legacy kitchen deep link redirects to feed.
class KitchenRemovedNotice {
  KitchenRemovedNotice._();

  static bool pending = false;

  static void markPending() => pending = true;

  static bool take() {
    if (!pending) return false;
    pending = false;
    return true;
  }
}
