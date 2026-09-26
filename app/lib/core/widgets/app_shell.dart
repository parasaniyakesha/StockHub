import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../data/models/platform.dart';
import '../constants/app_config.dart';
import '../routes/app_routes.dart';
import '../routes/nav_items.dart';
import '../session/auth_service.dart';
import '../session/notification_center.dart';
import '../storage/preferences.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'brand_logo.dart';
import 'cards.dart';
import 'dialogs.dart';

const double _sidebarWidth = 232;
const double _sidebarCollapsedWidth = 68;
const double _headerHeight = 60;

/// Enterprise desktop shell: fixed left sidebar + top header + content area.
/// Every authenticated route is wrapped with this via [ShellPage].
class ShellPage extends StatefulWidget {
  const ShellPage({super.key, required this.title, required this.child, this.breadcrumb, this.headerActions = const []});

  final String title;
  final String? breadcrumb;
  final Widget child;
  final List<Widget> headerActions;

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  late bool _collapsed = Preferences.sidebarCollapsed;

  void _toggle() {
    setState(() => _collapsed = !_collapsed);
    Preferences.sidebarCollapsed = _collapsed;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Sidebar(collapsed: _collapsed, onToggle: _toggle),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(title: widget.title, breadcrumb: widget.breadcrumb, actions: widget.headerActions),
                Expanded(child: widget.child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.collapsed, required this.onToggle});
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthService>();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: collapsed ? _sidebarCollapsedWidth : _sidebarWidth,
      color: AppColors.sidebar,
      child: Column(children: [
        SizedBox(
          height: _headerHeight,
          child: Row(children: [
            const SizedBox(width: 18),
            const BrandLogo(size: 30),
            if (!collapsed) ...[
              const SizedBox(width: 10),
              const Expanded(
                child: Text(AppConfig.appName, style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
              ),
            ],
          ]),
        ),
        const SizedBox(height: Gap.sm),
        Expanded(
          child: Obx(() {
            final visible = navItems.where((n) => n.access.allows(auth)).toList();
            final children = <Widget>[];
            String? lastSection;
            for (final item in visible) {
              if (!collapsed && item.section.isNotEmpty && item.section != lastSection) {
                children.add(_SectionLabel(item.section));
              }
              lastSection = item.section;
              children.add(_NavTile(item: item, collapsed: collapsed));
            }
            return ListView(padding: const EdgeInsets.symmetric(horizontal: 10), children: children);
          }),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.sm),
          child: _NavButton(
            icon: collapsed ? Icons.chevron_right : Icons.chevron_left,
            label: collapsed ? null : 'Collapse',
            onTap: onToggle,
          ),
        ),
      ]),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
        child: Text(text.toUpperCase(), style: const TextStyle(color: Color(0xFF64749A), fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
      );
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.item, required this.collapsed});
  final NavItem item;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final selected = Get.currentRoute == item.route || Get.currentRoute.startsWith('${item.route}/');
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Tooltip(
        message: collapsed ? item.label : '',
        waitDuration: const Duration(milliseconds: 300),
        child: _NavButton(
          icon: selected ? item.selectedIcon : item.icon,
          label: collapsed ? null : item.label,
          selected: selected,
          onTap: () => Get.toNamed(item.route),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.onTap, this.label, this.selected = false});
  final IconData icon;
  final String? label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.sidebarSelected : Colors.transparent,
      borderRadius: BorderRadius.circular(Radii.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        hoverColor: AppColors.sidebarHover,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Icon(icon, size: 19, color: selected ? AppColors.sidebarTextActive : AppColors.sidebarText),
            if (label != null) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Text(label!,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: selected ? AppColors.sidebarTextActive : AppColors.sidebarText, fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, this.breadcrumb, this.actions = const []});
  final String title;
  final String? breadcrumb;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
      decoration: const BoxDecoration(color: AppColors.surface, border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (breadcrumb != null)
                Text(breadcrumb!, style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w500)),
              Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ],
          ),
        ),
        ...actions,
        if (actions.isNotEmpty) const SizedBox(width: Gap.md),
        const _NotificationBell(),
        const SizedBox(width: Gap.sm),
        const _UserMenu(),
      ]),
    );
  }
}

class _NotificationBell extends StatelessWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context) {
    final center = Get.find<NotificationCenter>();
    return PopupMenuButton<void>(
      tooltip: 'Notifications',
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 360, maxWidth: 360, maxHeight: 460),
      onOpened: center.loadLatest,
      itemBuilder: (context) => [
        PopupMenuItem<void>(enabled: false, padding: EdgeInsets.zero, child: _NotificationPanel(center: center)),
      ],
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Obx(() => Badge(
              isLabelVisible: center.unread.value > 0,
              label: Text('${center.unread.value > 99 ? '99+' : center.unread.value}'),
              backgroundColor: AppColors.danger,
              child: const Icon(Icons.notifications_outlined, size: 22, color: AppColors.textSecondary),
            )),
      ),
    );
  }
}

class _NotificationPanel extends StatelessWidget {
  const _NotificationPanel({required this.center});
  final NotificationCenter center;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 360,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.sm, Gap.sm),
          child: Row(children: [
            const Expanded(child: Text('Notifications', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
            Obx(() => center.unread.value > 0
                ? TextButton(onPressed: center.markAllRead, child: const Text('Mark all read', style: TextStyle(fontSize: 12)))
                : const SizedBox()),
          ]),
        ),
        const Divider(height: 1),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: Obx(() {
            if (center.loadingLatest.value) return const Padding(padding: EdgeInsets.all(Gap.xl), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))));
            if (center.latest.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(Gap.xl),
                child: Center(child: Text('No notifications yet', style: TextStyle(color: AppColors.textMuted, fontSize: 12.5))),
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              itemCount: center.latest.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) => _NotificationTile(n: center.latest[i], onTap: () => center.markRead(center.latest[i])),
            );
          }),
        ),
        const Divider(height: 1),
        InkWell(
          onTap: () {
            Navigator.of(context, rootNavigator: true).maybePop();
            Get.toNamed(AppRoutes.notifications);
          },
          child: const Padding(padding: EdgeInsets.all(Gap.sm), child: Center(child: Text('View all', style: TextStyle(fontSize: 12.5, color: AppColors.primary, fontWeight: FontWeight.w600)))),
        ),
      ]),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.n, required this.onTap});
  final AppNotification n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: n.isRead ? Colors.transparent : AppColors.primarySoft.withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.sm),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: n.isRead ? Colors.transparent : AppColors.primary)),
          ),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(n.title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(n.message, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Text(Fmt.relative(n.createdAt), style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _UserMenu extends StatelessWidget {
  const _UserMenu();

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthService>();
    return Obx(() {
      final user = auth.current;
      if (user == null) return const SizedBox();
      return PopupMenuButton<String>(
        tooltip: 'Account',
        position: PopupMenuPosition.under,
        offset: const Offset(0, 6),
        onSelected: (value) {
          if (value == 'settings') Get.toNamed(AppRoutes.settings);
          if (value == 'logout') auth.logout();
        },
        itemBuilder: (context) => [
          PopupMenuItem<String>(
            enabled: false,
            child: SizedBox(
              width: 220,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(user.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                Text(user.email, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                const SizedBox(height: 4),
                StatusBadgeRole(user.role),
              ]),
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem<String>(value: 'settings', child: Row(children: [Icon(Icons.settings_outlined, size: 17), SizedBox(width: 10), Text('Account settings')])),
          const PopupMenuItem<String>(value: 'logout', child: Row(children: [Icon(Icons.logout, size: 17, color: AppColors.danger), SizedBox(width: 10), Text('Sign out', style: TextStyle(color: AppColors.danger))])),
        ],
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(children: [
            InitialsAvatar(Fmt.initials(user.name), size: 32),
            const SizedBox(width: 8),
            const Icon(Icons.expand_more, size: 18, color: AppColors.textMuted),
          ]),
        ),
      );
    });
  }
}

class StatusBadgeRole extends StatelessWidget {
  const StatusBadgeRole(this.role, {super.key});
  final String role;
  @override
  Widget build(BuildContext context) {
    final label = switch (role) { 'ADMIN' => 'Administrator', 'MANAGER' => 'Manager', _ => 'Store user' };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.primary)),
    );
  }
}

/// Confirms before signing out (used on the settings page too).
Future<void> confirmLogout() async {
  if (await confirmDialog(title: 'Sign out', message: 'You will need to sign in again to continue.', confirmLabel: 'Sign out')) {
    await Get.find<AuthService>().logout();
  }
}
