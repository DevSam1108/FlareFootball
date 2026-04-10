import 'package:flutter/material.dart';
import 'package:tensorflow_demo/services/navigation_service.dart';
import 'package:tensorflow_demo/values/app_routes.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flare Football'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.sports_soccer,
                size: 80,
                color: Colors.red,
              ),
              const SizedBox(height: 24),
              Text(
                'Soccer Ball Detection',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                'Real-time YOLO11n on-device detection',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
              const SizedBox(height: 48),
              FilledButton.icon(
                onPressed: () => NavigationService.instance.pushNamed(
                  AppRoutes.cameraScreen,
                ),
                icon: const Icon(Icons.videocam),
                label: const Text('Start Detection'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
