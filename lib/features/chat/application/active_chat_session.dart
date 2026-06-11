/// Текущий открытый чат — для подавления foreground push в активном диалоге.
class ActiveChatSession {
  ActiveChatSession._();

  static final ActiveChatSession instance = ActiveChatSession._();

  int? _conversationId;

  int? get conversationId => _conversationId;

  void setOpen(int conversationId) {
    _conversationId = conversationId;
  }

  void clearIfOpen(int conversationId) {
    if (_conversationId == conversationId) {
      _conversationId = null;
    }
  }

  bool isOpen(int conversationId) => _conversationId == conversationId;
}
