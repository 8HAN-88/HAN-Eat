import 'package:flutter/material.dart';
import '../../../services/api_service.dart';
import '../../../widgets/highlighted_text.dart';
import '../../../widgets/stars_pay_helper.dart';
import '../../subscription/creator_upsell.dart';
import '../data/donation_models.dart';

/// Экран отправки доната
class DonationScreen extends StatefulWidget {
  const DonationScreen({
    super.key,
    required this.recipientId,
    required this.recipientName,
    this.channelId,
    this.postId,
    this.channelName,
  });

  final int recipientId;
  final String recipientName;
  final int? channelId;
  final int? postId;
  final String? channelName;

  @override
  State<DonationScreen> createState() => _DonationScreenState();
}

class _DonationScreenState extends State<DonationScreen> {
  final _messageController = TextEditingController();
  int _selectedAmount = 100;
  bool _isSending = false;

  final List<int> _quickAmounts = [50, 100, 250, 500, 1000, 2500];

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendDonation() async {
    setState(() => _isSending = true);

    try {
      final request = DonationCreateRequest(
        recipientId: widget.recipientId,
        channelId: widget.channelId,
        postId: widget.postId,
        amountStars: _selectedAmount,
        message: _messageController.text.trim().isEmpty
            ? null
            : _messageController.text.trim(),
      );

      await ApiService.createDonation(request);

      if (!mounted) return;

      Navigator.of(context).pop(true); // true = успешно отправлено

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Спасибо! Донат $_selectedAmount ★ отправлен'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (mounted) {
        if (offerFlexIfRequired(context, e)) return;
        if (offerPackStoreIfRequired(context, e)) return;
        await showStarsRequiredSnack(context, e, fallback: 'Не удалось отправить донат');
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Поддержать автора'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Получатель
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 24,
                      child: Icon(Icons.person),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          HighlightedText(
                            text: widget.recipientName,
                            style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ) ??
                                const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (widget.channelName != null)
                            HighlightedText(
                              text: widget.channelName!,
                              style: theme.textTheme.bodySmall ??
                                  const TextStyle(fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            Text('Сумма доната (★)', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),

            // Быстрые суммы
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _quickAmounts.map((amount) {
                final isSelected = amount == _selectedAmount;
                return ChoiceChip(
                  label: Text('$amount ★'),
                  selected: isSelected,
                  onSelected: (_) => setState(() => _selectedAmount = amount),
                  selectedColor: theme.colorScheme.primaryContainer,
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // Кастомная сумма
            TextField(
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Другая сумма',
                suffixText: '★',
              ),
              onChanged: (value) {
                final parsed = int.tryParse(value);
                if (parsed != null && parsed > 0) {
                  setState(() => _selectedAmount = parsed);
                }
              },
            ),

            const SizedBox(height: 24),

            Text('Сообщение (опционально)', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),

            TextField(
              controller: _messageController,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                hintText: 'Спасибо за контент!',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isSending ? null : _sendDonation,
                icon: _isSending
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.favorite),
                label: Text(_isSending ? 'Отправка...' : 'Отправить $_selectedAmount ★'),
              ),
            ),

            const SizedBox(height: 8),

            Text(
              'Донат будет списан с вашего баланса Stars',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
