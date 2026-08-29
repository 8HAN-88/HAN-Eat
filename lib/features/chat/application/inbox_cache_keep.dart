/// Не стирать инбокс, если сеть вернула пусто (таймаут / обрыв).
bool keepStaleInboxOnEmptyFetch({
  required bool hasLocalInbox,
  required bool fetchReturnedItems,
}) {
  return hasLocalInbox && !fetchReturnedItems;
}
