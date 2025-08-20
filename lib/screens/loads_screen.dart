import 'package:flutter/material.dart';

class LoadsScreen extends StatelessWidget {
  const LoadsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('Loads — board, assign, statuses, filters'),
      ),
    );
  }
}
