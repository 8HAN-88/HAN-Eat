// Экран поддержки для создания обращений
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../services/support_service.dart';
import '../../../../services/subscription_service.dart';

class SupportScreen extends ConsumerStatefulWidget {
  const SupportScreen({Key? key}) : super(key: key);
  
  @override
  ConsumerState<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends ConsumerState<SupportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  String _selectedType = 'other';
  bool _isSubmitting = false;
  
  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }
  
  Future<void> _submitTicket() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isSubmitting = true);
    
    try {
      final response = await SupportService.createTicket(
        type: _selectedType,
        subject: _subjectController.text.trim(),
        message: _messageController.text.trim(),
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.message),
            backgroundColor: Colors.green,
          ),
        );
        
        // Очищаем форму
        _subjectController.clear();
        _messageController.clear();
        setState(() => _selectedType = 'other');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
  
  Future<void> _requestCancelSubscription() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отменить подписку?'),
        content: const Text(
          'Ваш запрос на отмену подписки будет отправлен в поддержку. '
          'Подписка останется активной до даты истечения после обработки запроса.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Отправить запрос'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    setState(() => _isSubmitting = true);
    
    try {
      final response = await SubscriptionService.requestCancelSubscription();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.message),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Поддержка'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Быстрое действие: отмена подписки
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Быстрые действия',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _isSubmitting ? null : _requestCancelSubscription,
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('Запросить отмену подписки'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Форма обращения
              const Text(
                'Создать обращение',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              // Тип обращения
              DropdownButtonFormField<String>(
                value: _selectedType,
                decoration: const InputDecoration(
                  labelText: 'Тип обращения',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'cancel_subscription',
                    child: Text('Отмена подписки'),
                  ),
                  DropdownMenuItem(
                    value: 'technical_issue',
                    child: Text('Техническая проблема'),
                  ),
                  DropdownMenuItem(
                    value: 'billing',
                    child: Text('Вопрос по оплате'),
                  ),
                  DropdownMenuItem(
                    value: 'other',
                    child: Text('Другое'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedType = value);
                  }
                },
              ),
              const SizedBox(height: 16),
              // Тема
              TextFormField(
                controller: _subjectController,
                decoration: const InputDecoration(
                  labelText: 'Тема',
                  hintText: 'Краткое описание проблемы',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Пожалуйста, укажите тему';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Сообщение
              TextFormField(
                controller: _messageController,
                decoration: const InputDecoration(
                  labelText: 'Сообщение',
                  hintText: 'Опишите проблему подробно...',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 6,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Пожалуйста, опишите проблему';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              // Кнопка отправки
              FilledButton(
                onPressed: _isSubmitting ? null : _submitTicket,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Отправить обращение'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

