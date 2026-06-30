import 'package:flutter/material.dart';

import '../../posts/presentation/create_post_screen.dart';

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
