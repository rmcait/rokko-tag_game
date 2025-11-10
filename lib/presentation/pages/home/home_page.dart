import 'package:flutter/material.dart';

import '../../../core/utils/logger.dart';
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
    final message =
        _viewModel.welcomeMessage?.message ?? '読み込み中...';

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
              const SizedBox(height: 24),
              CustomButton(
                label: _viewModel.isLoading ? 'Loading...' : 'Reload data',
                onPressed: _viewModel.isLoading
                    ? null
                    : () {
                        AppLogger.info('Reload tapped');
                        _viewModel.load();
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
