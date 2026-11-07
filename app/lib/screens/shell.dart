import 'package:flutter/material.dart';

import '../services/app_version.dart';
import '../widgets/tour.dart';
import '../widgets/update_sheet.dart';

import '../theme.dart';
import '../util/i18n.dart';
import 'assistant_screen.dart';
import 'cinemas_screen.dart';
import 'explore_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

typedef _Tab = ({String label, IconData icon, IconData activeIcon});

/// The four tabs, with the assistant's button in the middle, under a floating glass bar that pages scroll behind. Tabs
/// keep their state (scroll position…) when you switch away.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  /// Explore's search box; Home's search bar lands you in it, keyboard up.
  final _exploreSearch = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) await showTourOnce(context);
      _offerUpdate();
    });
  }

  /// A newer APK on GitHub: say so once, with a download button.
  Future<void> _offerUpdate() async {
    final update = await checkForUpdate();
    if (update == null || !mounted) return;
    showUpdatePrompt(context, update);
  }

  @override
  void dispose() {
    _exploreSearch.dispose();
    super.dispose();
  }

  void _search() {
    setState(() => _tab = 1);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _exploreSearch.requestFocus(),
    );
  }

  static List<_Tab> get _tabs => [
    (
      label: tr('الرئيسية', 'Home'),
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
    ),
    (
      label: tr('استكشف', 'Explore'),
      icon: Icons.search,
      activeIcon: Icons.search,
    ),
    (
      label: tr('السينمات', 'Cinemas'),
      icon: Icons.place_outlined,
      activeIcon: Icons.place,
    ),
    (
      label: tr('الإعدادات', 'Settings'),
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Pages run under the bar, so it frosts whatever scrolls past.
      extendBody: true,
      body: IndexedStack(
        index: _tab,
        children: [
          HomeScreen(onSearch: _search),
          ExploreScreen(searchFocus: _exploreSearch),
          const CinemasScreen(),
          SettingsScreen(onExplore: () => setState(() => _tab = 1)),
        ],
      ),
      bottomNavigationBar: _GlassTabBar(
        tabs: _tabs,
        current: _tab,
        onSelect: (i) => setState(() => _tab = i),
        onAssistant: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AssistantScreen()),
        ),
      ),
    );
  }
}

class _GlassTabBar extends StatelessWidget {
  const _GlassTabBar({
    required this.tabs,
    required this.current,
    required this.onSelect,
    required this.onAssistant,
  });

  final List<_Tab> tabs;
  final int current;
  final ValueChanged<int> onSelect;
  final VoidCallback onAssistant;

  Widget _item(int i) => Expanded(
    child: _TabItem(
      tab: tabs[i],
      active: i == current,
      onTap: () => onSelect(i),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Glass(
          radius: 30,
          child: SizedBox(
            height: 64,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Row(
                // Two tabs each side of the assistant's gold button.
                children: [
                  for (var i = 0; i < 2; i++) _item(i),
                  _AssistantButton(onTap: onAssistant),
                  for (var i = 2; i < tabs.length; i++) _item(i),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The tap-only assistant (assistant_screen.dart), in the middle of the bar.
class _AssistantButton extends StatelessWidget {
  const _AssistantButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Semantics(
      button: true,
      label: tr('اسأل عالشباك', 'Ask 3al Shebbak'),
      child: Tooltip(
        message: tr('اسأل عالشباك', 'Ask 3al Shebbak'),
        child: Material(
          color: AppColors.gold,
          shape: const CircleBorder(),
          elevation: 4,
          shadowColor: AppColors.gold.withValues(alpha: 0.5),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(
              dimension: 52,
              child: Icon(
                Icons.forum_outlined,
                size: 24,
                color: AppColors.onGold,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.tab,
    required this.active,
    required this.onTap,
  });

  final _Tab tab;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.gold : AppColors.muted;
    return Semantics(
      selected: active,
      button: true,
      label: tab.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ExcludeSemantics(
          // The current tab sits in a lit capsule, like iOS's.
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: active
                  ? AppColors.gold.withValues(
                      alpha: AppColors.isDark ? 0.16 : 0.12,
                    )
                  : Colors.transparent,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  active ? tab.activeIcon : tab.icon,
                  color: color,
                  size: 23,
                  shadows: active
                      ? [
                          Shadow(
                            color: AppColors.gold.withValues(alpha: 0.6),
                            blurRadius: 12,
                          ),
                        ]
                      : null,
                ),
                const SizedBox(height: 2),
                Text(
                  tab.label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: AppText.body(
                    10.5,
                    color: color,
                    weight: active ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
