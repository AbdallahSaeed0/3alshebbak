import 'package:flutter/material.dart';

import '../theme.dart';
import 'cinemas_screen.dart';
import 'explore_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

/// The four tabs. Tabs keep their state (scroll position…) when you switch away.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  static const _tabs = [
    (label: 'الرئيسية', icon: Icons.home_outlined),
    (label: 'استكشف', icon: Icons.search),
    (label: 'السينمات', icon: Icons.place_outlined),
    (label: 'الإعدادات', icon: Icons.settings_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          HomeScreen(onSearch: () => setState(() => _tab = 1)),
          const ExploreScreen(),
          const CinemasScreen(),
          SettingsScreen(onExplore: () => setState(() => _tab = 1)),
        ],
      ),
      bottomNavigationBar: _TabBar(
        current: _tab,
        onSelect: (i) => setState(() => _tab = i),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.current, required this.onSelect});

  final int current;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFF110F0C),
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (var i = 0; i < _ShellState._tabs.length; i++)
                Expanded(
                  child: _TabItem(
                    tab: _ShellState._tabs[i],
                    active: i == current,
                    onTap: () => onSelect(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.tab,
    required this.active,
    required this.onTap,
  });

  final ({String label, IconData icon}) tab;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.gold : AppColors.muted;
    return Semantics(
      selected: active,
      button: true,
      label: tab.label,
      child: InkResponse(
        onTap: onTap,
        child: ExcludeSemantics(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // The lit bulb over the current tab.
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? AppColors.gold : Colors.transparent,
                  boxShadow: active
                      ? const [BoxShadow(color: AppColors.gold, blurRadius: 8)]
                      : null,
                ),
              ),
              const SizedBox(height: 3),
              Icon(tab.icon, color: color, size: 24),
              const SizedBox(height: 2),
              Text(
                tab.label,
                style: AppText.body(11, color: color, weight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
