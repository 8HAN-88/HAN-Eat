import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/main_shell.dart';

class OnboardingPage extends StatefulWidget {
  final SharedPreferences prefs;
  const OnboardingPage({required this.prefs, Key? key}) : super(key: key);

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pc = PageController();
  int _page = 0;

  void _complete() {
    widget.prefs.setBool('seenOnboarding', true);
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (_) => const MainShell()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pc,
                onPageChanged: (p) => setState(() => _page = p),
                children: [
                  _buildSlide(
                    icon: Icons.restaurant_menu,
                    title: 'Discover Recipes',
                    text: 'Find delicious recipes tailored to your taste.',
                  ),
                  _buildSlide(
                    icon: Icons.favorite,
                    title: 'Save Favorites',
                    text:
                        'Keep your favorite recipes for quick access anytime.',
                  ),
                  _buildSlide(
                    icon: Icons.group,
                    title: 'Join Community',
                    text: 'Share videos and comment with other home cooks.',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Row(
                    children: List.generate(
                        3,
                        (i) => AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: _page == i ? 24 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _page == i
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.primary
                                        .withOpacity(0.3),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            )),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _page == 2
                        ? _complete
                        : () => _pc.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.ease),
                    child: Text(_page == 2 ? 'Get started' : 'Next'),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildSlide(
      {required IconData icon, required String title, required String text}) {
    return Padding(
      padding: const EdgeInsets.all(36),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(radius: 56, child: Icon(icon, size: 56)),
          const SizedBox(height: 24),
          Text(title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(text,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
