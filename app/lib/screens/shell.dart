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

  /// Scrolling down tucks the bar's labels away; scrolling up brings them
  /// back. A notifier only the bar listens to: the pages under it never
  /// rebuild, so a scroll keeps its momentum.
  final _compact = ValueNotifier(false);

  bool _onScroll(ScrollUpdateNotification n) {
    if (n.metrics.axis != Axis.vertical || n.depth > 1) return false;
    final delta = n.scrollDelta ?? 0;
    if (n.metrics.pixels <= n.metrics.minScrollExtent + 8) {
      _compact.value = false;
    } else if (delta > 2) {
      _compact.value = true;
    } else if (delta < -2) {
      _compact.value = false;
    }
    return false;
  }

  /// Explore's search box; Home's search bar lands you in it, keyboard up.
  final _exploreSearch = FocusNode();

  @override
  void initState() {
    super.initState();
    // The tour points at Home's buttons: show Home, with the bar's labels.
    TourTargets.showHome = () {
      if (mounted) {
        setState(() {
          _tab = 0;
        });
        _compact.value = false;
      }
    };
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
    _compact.dispose();
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
      // The keyboard doesn't shrink the pages: shrinking them laid out all
      // four tabs on every frame of the keyboard sliding, and the bar crawled
      // back up after a search. Pages with a text field leave room for the
      // keyboard themselves (KeyboardSpace).
      resizeToAvoidBottomInset: false,
      body: NotificationListener<ScrollUpdateNotification>(
        onNotification: _onScroll,
        child: IndexedStack(
          index: _tab,
          children: [
            HomeScreen(onSearch: _search),
            ExploreScreen(searchFocus: _exploreSearch),
            const CinemasScreen(),
            SettingsScreen(onExplore: () => setState(() => _tab = 1)),
          ],
        ),
      ),
      bottomNavigationBar: ValueListenableBuilder<bool>(
        valueListenable: _compact,
        builder: (context, compact, _) => _GlassTabBar(
          tabs: _tabs,
          current: _tab,
          compact: compact,
          onSelect: (i) {
            setState(() => _tab = i);
            _compact.value = false;
          },
          onAssistant: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const AssistantScreen()),
          ),
        ),
      ),
    );
  }
}

class _GlassTabBar extends StatelessWidget {
  const _GlassTabBar({
    required this.tabs,
    required this.current,
    required this.compact,
    required this.onSelect,
    required this.onAssistant,
  });

  final List<_Tab> tabs;
  final int current;
  final bool compact;
  final ValueChanged<int> onSelect;
  final VoidCallback onAssistant;

  Widget _item(int i) => Expanded(
    child: _TabItem(
      tab: tabs[i],
      key: TourTargets.tab(i),
      active: i == current,
      compact: compact,
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
        // The slot keeps its height, so the page under it never shifts; the
        // bar inside shrinks into its bottom while scrolling down.
        child: SizedBox(
          height: 64,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              height: compact ? 48 : 64,
              margin: EdgeInsets.symmetric(horizontal: compact ? 28 : 0),
              child: Glass(
                radius: 30,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Row(
                    // Two tabs each side of the assistant's gold button.
                    children: [
                      for (var i = 0; i < 2; i++) _item(i),
                      _AssistantButton(
                        key: TourTargets.assistant,
                        onTap: onAssistant,
                        compact: compact,
                      ),
                      for (var i = 2; i < tabs.length; i++) _item(i),
                    ],
                  ),
                ),
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
  const _AssistantButton({
    super.key,
    required this.onTap,
    required this.compact,
  });
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Semantics(
      button: true,
      label: tr('اسأل عالشباك', 'Ask 3al Shebbak'),
      child: Tooltip(
        message: tr('اسأل عالشباك', 'Ask 3al Shebbak'),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Material(
                color: AppColors.gold,
                shape: const CircleBorder(),
                elevation: 4,
                shadowColor: AppColors.gold.withValues(alpha: 0.5),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onTap,
                  child: SizedBox.square(
                    dimension: 36,
                    child: Icon(
                      Icons.forum_outlined,
                      size: 20,
                      color: AppColors.onGold,
                    ),
                  ),
                ),
              ),
              _Label(
                text: tr('اسأل', 'Ask'),
                color: AppColors.gold,
                bold: true,
                hidden: compact,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    super.key,
    required this.tab,
    required this.active,
    required this.compact,
    required this.onTap,
  });

  final _Tab tab;
  final bool active;
  final bool compact;
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
                _Label(
                  text: tab.label,
                  color: color,
                  bold: active,
                  hidden: compact,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A tab's name under its icon; folds away while scrolling down.
class _Label extends StatelessWidget {
  const _Label({
    required this.text,
    required this.color,
    required this.bold,
    required this.hidden,
  });

  final String text;
  final Color color;
  final bool bold;
  final bool hidden;

  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: const Duration(milliseconds: 220),
    curve: Curves.easeOut,
    child: hidden
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: AppText.body(
                10.5,
                color: color,
                weight: bold ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
  );
}
