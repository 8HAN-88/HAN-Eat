import 'package:flutter/material.dart';

import 'package:han_eat/features/posts/presentation/create_post_screen.dart';

class CreateRecipeScreen extends StatelessWidget {
  const CreateRecipeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const CreatePostScreen(
      initialType: 'recipe',
      recipeOnly: true,
    );
  }
}
