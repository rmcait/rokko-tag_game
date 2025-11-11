import 'package:flutter/material.dart';

import '../../../core/utils/logger.dart';
import '../../routes.dart';
import '../../widgets/custom_button.dart';
import 'home_viewmodel.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final HomeViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = HomeViewModel()..addListener(_onVmChanged);
    _viewModel.load();
  }

  void _onVmChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _viewModel
      ..removeListener(_onVmChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = _viewModel.user;
    final isLoading = _viewModel.isLoading;
    final updatedAt = user?.updatedAt;
    final message = user == null
        ? (isLoading ? '読み込み中...' : 'ユーザーデータが見つかりません')
        : '${user.displayName}\nstatus: ${user.status}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tag Game'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                message,
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              if (updatedAt != null) ...[
                const SizedBox(height: 8),
                Text(
                  'updatedAt: $updatedAt',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 24),
              CustomButton(
                label: isLoading ? 'Loading...' : 'Reload data',
                onPressed: isLoading
                    ? null
                    : () {
                        AppLogger.info('Reload tapped');
                        _viewModel.load();
                      },
              ),
              const SizedBox(height: 12),
              CustomButton(
                label: '地図を開く',
                onPressed: () {
                  Navigator.of(context).pushNamed(AppRoutes.map);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
