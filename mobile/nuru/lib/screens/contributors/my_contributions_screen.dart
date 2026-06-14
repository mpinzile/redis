import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nuru_subpage_app_bar.dart';
import '../../core/l10n/l10n_helper.dart';
import 'widgets/my_contribution_payments_tab.dart';

/// Top-level My Contributions screen - mirrors the web `/my-contributions`
/// page so this important workflow is reachable from the drawer instead of
/// being buried as a sub-tab inside Contributors.
class MyContributionsScreen extends StatelessWidget {
  const MyContributionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: NuruSubPageAppBar(title: context.tr('my_contributions')),
      body: const MyContributionPaymentsTab(),
    );
  }
}
