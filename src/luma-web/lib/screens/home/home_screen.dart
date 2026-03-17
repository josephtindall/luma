import 'package:flutter/material.dart';

import '../../services/api_client.dart';

class HomeScreen extends StatelessWidget {
  // ApiClient kept in signature to avoid router changes; unused for now.
  final ApiClient api;

  const HomeScreen({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_outlined, size: 48),
            SizedBox(height: 16),
            Text(
              'Select a vault from the sidebar to get started.',
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
