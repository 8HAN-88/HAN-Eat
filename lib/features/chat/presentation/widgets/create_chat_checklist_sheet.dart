import 'package:flutter/material.dart';

import '../../../subscription/creator_upsell.dart';
import '../../../../models/chat_models.dart';

class ChatChecklistFormPanel extends StatefulWidget {
  const ChatChecklistFormPanel({
    super.key,
    this.scrollController,
    this.onValidityChanged,
  });

  static const maxItems = 20;

  final ScrollController? scrollController;
  final ValueChanged<bool>? onValidityChanged;

  @override
  ChatChecklistFormPanelState createState() => ChatChecklistFormPanelState();
}

class ChatChecklistFormPanelState extends State<ChatChecklistFormPanel> {
  final _titleController = TextEditingController();
  final _itemControllers = <TextEditingController>[
    TextEditingController(),
    TextEditingController(),
  ];

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_notifyValidity);
    for (final c in _itemControllers) {
      c.addListener(_notifyValidity);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    for (final c in _itemControllers) {
      c.dispose();
    }
    super.dispose();
  }

  bool get canSend {
    if (_titleController.text.trim().isEmpty) return false;
    return _itemControllers.where((c) => c.text.trim().isNotEmpty).length >= 1;
  }

  void _notifyValidity() => widget.onValidityChanged?.call(canSend);

  void _addItem() {
    if (_itemControllers.length >= ChatChecklistFormPanel.maxItems) return;
    setState(() {
      final next = TextEditingController();
      next.addListener(_notifyValidity);
      _itemControllers.add(next);
    });
  }

  void _removeItem(int index) {
    if (_itemControllers.length <= 1) return;
    setState(() {
      _itemControllers.removeAt(index).dispose();
    });
    _notifyValidity();
  }

  ChatChecklistDraft? buildDraft() {
    if (!canSend) return null;
    if (!hasFlexFeature('checklist')) {
      showCreatorUpsell(context);
      return null;
    }
    return ChatChecklistDraft(
      title: _titleController.text.trim(),
      items: _itemControllers
          .map((c) => c.text.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        TextField(
          controller: _titleController,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Название',
            hintText: 'Что нужно сделать',
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Пункты',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < _itemControllers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              controller: _itemControllers[i],
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Пункт ${i + 1}',
                suffixIcon: _itemControllers.length > 1
                    ? IconButton(
                        onPressed: () => _removeItem(i),
                        icon: const Icon(Icons.close),
                      )
                    : null,
              ),
            ),
          ),
        if (_itemControllers.length < ChatChecklistFormPanel.maxItems)
          TextButton.icon(
            onPressed: _addItem,
            icon: const Icon(Icons.add),
            label: const Text('Добавить пункт'),
          ),
      ],
    );
  }
}

class CreateChatChecklistSheet extends StatefulWidget {
  const CreateChatChecklistSheet({super.key});

  static Future<ChatChecklistDraft?> show(BuildContext context) {
    if (!hasFlexFeature('checklist')) {
      showCreatorUpsell(context);
      return Future<ChatChecklistDraft?>.value();
    }
    return showModalBottomSheet<ChatChecklistDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const CreateChatChecklistSheet(),
    );
  }

  @override
  State<CreateChatChecklistSheet> createState() =>
      _CreateChatChecklistSheetState();
}

class _CreateChatChecklistSheetState extends State<CreateChatChecklistSheet> {
  final _formKey = GlobalKey<ChatChecklistFormPanelState>();
  bool _canSend = false;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Отмена'),
                  ),
                  const Expanded(
                    child: Text(
                      'Чеклист',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    onPressed: _canSend
                        ? () {
                            final draft = _formKey.currentState?.buildDraft();
                            if (draft != null) Navigator.pop(context, draft);
                          }
                        : null,
                    child: const Text('Отправить'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ChatChecklistFormPanel(
                key: _formKey,
                onValidityChanged: (v) {
                  if (_canSend != v) setState(() => _canSend = v);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
