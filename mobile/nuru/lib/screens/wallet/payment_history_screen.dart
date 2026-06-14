import '../../core/widgets/nuru_refresh_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/services/wallet_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nuru_loader.dart';
import '../../core/widgets/app_icon.dart';
import '../../providers/wallet_provider.dart';

import '../../core/widgets/app_snackbar.dart';
import 'receipt_screen.dart';

/// Premium Payment History screen - matches the 2026 mockup exactly.
///
/// Features:
///   • Yellow "Total Spent" hero card with 30-day trend pill
///   • Horizontal scrollable category tabs (All / Tickets / Contributions /
///     Vendors / Promotions / Ads) - counts come from the backend
///   • Filter sheet (status + sort) reachable from the funnel icon
///   • Tap any row → ReceiptScreen (existing flow, unchanged)
///   • Pull-to-refresh + infinite scroll
///   • Empty state per category (Promotions / Ads return a friendly
///     "no payments yet" panel because they don't yet flow through the
///     unified Transaction table - backend explicitly returns []).
class PaymentHistoryScreen extends StatefulWidget {
  const PaymentHistoryScreen({super.key});

  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen> {
  static const _categories = <_CategoryDef>[
    _CategoryDef('all', 'All'),
    _CategoryDef('tickets', 'Tickets'),
    _CategoryDef('contributions', 'Contributions'),
    _CategoryDef('vendors', 'Vendors'),
    _CategoryDef('promotions', 'Promotions'),
    _CategoryDef('ads', 'Ads'),
  ];

  String _category = 'all';
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;

  Map<String, dynamic> _summary = {};
  Map<String, int> _counts = const {};
  List<dynamic> _txs = [];
  String? _emptyReason;

  // Filter state - applied client-side over what the API returned.
  String _statusFilter = 'all'; // all | paid | pending | failed
  String _sortBy = 'newest'; // newest | oldest | highest | lowest

  final ScrollController _scrollCtrl = ScrollController();
  final ScrollController _tabScrollCtrl = ScrollController();
  final List<GlobalKey> _tabKeys =
      List.generate(_categories.length, (_) => GlobalKey());

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(() {
      if (_scrollCtrl.position.pixels >=
              _scrollCtrl.position.maxScrollExtent - 240 &&
          _hasMore &&
          !_loadingMore) {
        _loadMore();
      }
    });
    _load();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _tabScrollCtrl.dispose();
    super.dispose();
  }

  void _scrollActiveTabIntoView() {
    final i = _categories.indexWhere((c) => c.key == _category);
    if (i < 0 || i >= _tabKeys.length) return;
    final ctx = _tabKeys[i].currentContext;
    if (ctx == null || !_tabScrollCtrl.hasClients) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final viewport = _tabScrollCtrl.position.viewportDimension;
    final tabOffset = box
        .localToGlobal(Offset.zero, ancestor: context.findRenderObject())
        .dx;
    final tabWidth = box.size.width;
    final currentScroll = _tabScrollCtrl.offset;
    final centerAbs = currentScroll + tabOffset + tabWidth / 2;
    final target = (centerAbs - viewport / 2).clamp(
      _tabScrollCtrl.position.minScrollExtent,
      _tabScrollCtrl.position.maxScrollExtent,
    );
    _tabScrollCtrl.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }



  Future<void> _load({bool refresh = false}) async {
    if (refresh) _page = 1;
    setState(() => _loading = true);
    final res = await WalletService.paymentHistory(
      category: _category,
      page: 1,
      limit: 20,
    );
    if (!mounted) return;
    if (res['success'] == true) {
      final data = (res['data'] as Map?) ?? {};
      final pagination = (data['pagination'] as Map?) ?? {};
      setState(() {
        _summary = (data['summary'] as Map?)?.cast<String, dynamic>() ?? {};
        _counts =
            ((data['counts'] as Map?) ?? {}).map((k, v) => MapEntry('$k', (v as num).toInt()));
        _txs = (data['transactions'] as List?) ?? [];
        _emptyReason = data['empty_reason'] as String?;
        final totalPages = (pagination['total_pages'] as num?)?.toInt() ?? 1;
        _hasMore = totalPages > 1;
        _page = 1;
        _loading = false;
      });
    } else {
      setState(() {
        _loading = false;
        _txs = [];
        _hasMore = false;
      });
      AppSnackbar.error(context, res['message']?.toString() ?? 'Failed to load history');
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final next = _page + 1;
    final res = await WalletService.paymentHistory(
      category: _category,
      page: next,
      limit: 20,
    );
    if (!mounted) return;
    if (res['success'] == true) {
      final data = (res['data'] as Map?) ?? {};
      final pagination = (data['pagination'] as Map?) ?? {};
      final totalPages = (pagination['total_pages'] as num?)?.toInt() ?? 1;
      setState(() {
        _txs = [..._txs, ...((data['transactions'] as List?) ?? [])];
        _page = next;
        _hasMore = next < totalPages;
        _loadingMore = false;
      });
    } else {
      setState(() => _loadingMore = false);
    }
  }

  void _setCategory(String c) {
    if (_category == c) return;
    setState(() => _category = c);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _scrollActiveTabIntoView());
    _load(refresh: true);
  }


  // ─── Filtering / sorting (client-side over current page set) ──────
  List<dynamic> get _visibleTxs {
    Iterable<dynamic> list = _txs;
    if (_statusFilter != 'all') {
      list = list.where((t) {
        final s = (t is Map ? '${t['status']}' : '').toLowerCase();
        if (_statusFilter == 'paid') return s == 'paid' || s == 'credited';
        if (_statusFilter == 'pending') return s == 'pending' || s == 'processing';
        if (_statusFilter == 'failed') return s == 'failed' || s == 'reversed';
        return true;
      });
    }
    final sorted = list.toList();
    sorted.sort((a, b) {
      final am = a is Map ? a : <String, dynamic>{};
      final bm = b is Map ? b : <String, dynamic>{};
      switch (_sortBy) {
        case 'oldest':
          return ('${am['created_at'] ?? am['initiated_at'] ?? ''}')
              .compareTo('${bm['created_at'] ?? bm['initiated_at'] ?? ''}');
        case 'highest':
          return ((bm['gross_amount'] as num?) ?? 0)
              .compareTo((am['gross_amount'] as num?) ?? 0);
        case 'lowest':
          return ((am['gross_amount'] as num?) ?? 0)
              .compareTo((bm['gross_amount'] as num?) ?? 0);
        case 'newest':
        default:
          return ('${bm['initiated_at'] ?? bm['created_at'] ?? ''}')
              .compareTo('${am['initiated_at'] ?? am['created_at'] ?? ''}');
      }
    });
    return sorted;
  }

  // ─── Helpers ──────────────────────────────────────────────────────
  TextStyle _f({
    double size = 14,
    FontWeight weight = FontWeight.w500,
    Color color = AppColors.textPrimary,
    double height = 1.3,
    double letterSpacing = 0,
  }) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );

  String _fmtMoney(num v, String currency) {
    final s = v
        .toStringAsFixed(0)
        .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    return '$currency $s';
  }

  String _fmtDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}  •  $h:$mm $ampm';
  }

  // ─── Build ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final walletCurrency = context.watch<WalletProvider>().currency;
    final currency =
        (_summary['currency_code']?.toString().isNotEmpty == true)
            ? _summary['currency_code'].toString()
            : walletCurrency;
    final totalSpent = (_summary['total_spent'] as num?) ?? 0;
    final txCount = (_summary['transaction_count'] as num?)?.toInt() ?? 0;
    final pct = (_summary['percent_change_30d'] as num?)?.toDouble() ?? 0.0;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leadingWidth: 56,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const AppIcon('chevron-left',
              size: 22, color: AppColors.textPrimary),
        ),
        title: Text(
          'Payment History',
          style: _f(size: 17, weight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Filter',
            icon: const AppIcon('filter', size: 20, color: AppColors.textPrimary),
            onPressed: _openFilterSheet,
          ),
        ],
      ),
      body: NuruRefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => _load(refresh: true),
        child: CustomScrollView(
          controller: _scrollCtrl,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ─── Category tabs (sticky) ───
            SliverToBoxAdapter(child: _categoryTabs()),

            // ─── Total Spent hero card ───
            SliverToBoxAdapter(
              child: _loading
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: _skeletonHero(),
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: _totalSpentCard(currency, totalSpent, txCount, pct),
                    ),
            ),

            // ─── "Recent Transactions" header ───
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                child: Text('Recent Transactions',
                    style: _f(size: 16, weight: FontWeight.w700)),
              ),
            ),

            // ─── List ───
            if (_loading)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, __) => _skeletonRow(),
                  childCount: 6,
                ),
              )
            else if (_visibleTxs.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _emptyState(),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) {
                    if (i >= _visibleTxs.length) {
                      return _loadingMore
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 18),
                              child: Center(child: NuruLoader(size: 28)),
                            )
                          : const SizedBox.shrink();
                    }
                    return _txRow(_visibleTxs[i] as Map<String, dynamic>, currency);
                  },
                  childCount: _visibleTxs.length + (_hasMore ? 1 : 0),
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  // ─── Category tabs row (auto-scrolls active chip into view) ──────
  Widget _categoryTabs() {
    return SizedBox(
      height: 36,
      child: SingleChildScrollView(
        controller: _tabScrollCtrl,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: List.generate(_categories.length, (i) {
            final c = _categories[i];
            final selected = c.key == _category;
            return Padding(
              key: _tabKeys[i],
              padding: EdgeInsets.only(right: i == _categories.length - 1 ? 0 : 10),
              child: GestureDetector(
                onTap: () => _setCategory(c.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primary : const Color(0xFFF9F9F9),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: selected ? AppColors.primary : const Color(0xFFEFEFEF),
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      c.label,
                      style: _f(
                        size: 11,
                        weight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }


  // ─── Total Spent hero card (yellow on the mockup uses neutral grey) ──
  // The mockup screen shows a soft grey hero card; only navigation
  // chips and CTAs are yellow. We follow the mockup precisely.
  Widget _totalSpentCard(String currency, num total, int count, double pct) {
    final isPositive = pct >= 0;
    final pctText =
        '${isPositive ? '↑' : '↓'} ${pct.abs().toStringAsFixed(0)}%';
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEFEFF3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total Spent',
                    style: _f(
                      size: 13,
                      weight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    )),
                const SizedBox(height: 6),
                Text(
                  _fmtMoney(total, currency),
                  style: _f(size: 26, weight: FontWeight.w800, height: 1.1),
                ),
                const SizedBox(height: 6),
                Text(
                  count == 1
                      ? 'Across 1 transaction'
                      : 'Across $count transactions',
                  style: _f(
                    size: 12,
                    color: AppColors.textTertiary,
                    weight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isPositive
                  ? AppColors.success.withOpacity(0.12)
                  : AppColors.error.withOpacity(0.10),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              pctText,
              style: _f(
                size: 11,
                weight: FontWeight.w800,
                color: isPositive ? AppColors.success : AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Single transaction row (matches mockup: square icon, title,
  //     subtitle, amount + status pill, chevron) ──────────────────
  Widget _txRow(Map<String, dynamic> tx, String currency) {
    final targetType = (tx['target_type'] ?? '').toString();
    final desc = (tx['payment_description'] ?? '').toString();
    final amount = (tx['gross_amount'] as num?) ?? 0;
    final status = (tx['status'] ?? '').toString();
    final txCurrency = (tx['currency_code'] ?? currency).toString();
    final when = _fmtDate(
      (tx['confirmed_at'] ?? tx['initiated_at'] ?? tx['created_at'])?.toString(),
    );

    final visual = _visualForTarget(targetType);
    final title = _titleForTx(targetType, desc);
    final subtitle = _subtitleForTx(targetType, desc);
    final statusPill = _statusPill(status);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            final code = (tx['transaction_code'] ?? tx['id'] ?? '').toString();
            if (code.isNotEmpty) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ReceiptScreen(transactionCode: code),
                ),
              );
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: visual.bg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: SvgPicture.asset(
                    visual.svg,
                    width: 22,
                    height: 22,
                    colorFilter: ColorFilter.mode(visual.fg, BlendMode.srcIn),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: _f(size: 14, weight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      if (subtitle.isNotEmpty)
                        Text(subtitle,
                            style: _f(
                              size: 12,
                              color: AppColors.textTertiary,
                              weight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      if (when.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(when,
                            style: _f(
                              size: 11,
                              color: AppColors.textTertiary,
                              weight: FontWeight.w500,
                            )),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_fmtMoney(amount, txCurrency),
                        style: _f(size: 13, weight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    statusPill,
                  ],
                ),
                const SizedBox(width: 4),
                const AppIcon('chevron-right',
                    color: AppColors.textTertiary, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusPill(String status) {
    final s = status.toLowerCase();
    Color bg, fg;
    String label;
    if (s == 'paid' || s == 'credited') {
      bg = AppColors.success.withOpacity(0.12);
      fg = AppColors.success;
      label = 'Paid';
    } else if (s == 'pending' || s == 'processing') {
      bg = AppColors.warning.withOpacity(0.14);
      fg = const Color(0xFFB45309);
      label = s == 'processing' ? 'Processing' : 'Pending';
    } else if (s == 'failed' || s == 'reversed') {
      bg = AppColors.error.withOpacity(0.10);
      fg = AppColors.error;
      label = s == 'reversed' ? 'Reversed' : 'Failed';
    } else {
      bg = const Color(0xFFEFF1F5);
      fg = AppColors.textSecondary;
      label = status.isEmpty ? '-' : status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label,
          style: _f(size: 10, weight: FontWeight.w800, color: fg)),
    );
  }

  // ─── Visual mapping per target type (project SVGs only) ──────────
  _Visual _visualForTarget(String t) {
    switch (t) {
      case 'ticket':
        return _Visual(
          bg: const Color(0xFFFFF6CF),
          fg: const Color(0xFFB45309),
          svg: 'assets/icons/ticket-icon.svg',
        );
      case 'contribution':
        return _Visual(
          bg: AppColors.success.withOpacity(0.12),
          fg: AppColors.success,
          svg: 'assets/icons/heart-icon.svg',
        );
      case 'booking':
        return _Visual(
          bg: AppColors.blue.withOpacity(0.10),
          fg: AppColors.blue,
          svg: 'assets/icons/bag-icon.svg',
        );
      case 'wallet_topup':
        return _Visual(
          bg: AppColors.primary.withOpacity(0.12),
          fg: const Color(0xFFB45309),
          svg: 'assets/icons/wallet-icon.svg',
        );
      default:
        return _Visual(
          bg: const Color(0xFFEFF1F5),
          fg: AppColors.textSecondary,
          svg: 'assets/icons/card-icon.svg',
        );
    }
  }


  String _titleForTx(String t, String desc) {
    switch (t) {
      case 'ticket':
        return 'Ticket Purchase';
      case 'contribution':
        return 'Contribution';
      case 'booking':
        return 'Vendor Payment';
      case 'wallet_topup':
        return 'Wallet Top-Up';
      default:
        return desc.isEmpty ? 'Payment' : desc;
    }
  }

  String _subtitleForTx(String t, String desc) {
    if (desc.isEmpty) return '';
    // Strip the leading "Ticket purchase for ..." style prefix to keep
    // the subtitle short.
    final cleaned = desc
        .replaceAll(RegExp(r'^(ticket purchase for|contribution to|booking for)\s*',
            caseSensitive: false), '')
        .trim();
    return cleaned;
  }

  // ─── Empty state ──────────────────────────────────────────────────
  /// Per-category copy. Avoids awkward "No <tab-label> payments" strings.
  /// Icons are project SVG stems (resolved via AppIcon → assets/icons/*-icon.svg).
  ({String title, String body, String iconSvg}) _emptyCopy() {
    final isVirtual = _emptyReason == 'no_promotion_payments_yet';
    switch (_category) {
      case 'all':
        return (
          title: "You haven't made any payments yet",
          body:
              'When you buy a ticket, contribute, or pay a vendor, the receipt will land here.',
          iconSvg: 'wallet',
        );
      case 'tickets':
        return (
          title: 'No ticket purchases yet',
          body: 'Tickets you buy from events will show up here.',
          iconSvg: 'ticket',
        );
      case 'contributions':
        return (
          title: 'No contributions yet',
          body:
              'Money you contribute to events you support will be listed here.',
          iconSvg: 'heart',
        );
      case 'vendors':
        return (
          title: 'No vendor payments yet',
          body: 'Payments for services you booked will appear here.',
          iconSvg: 'bag',
        );
      case 'promotions':
        return (
          title: isVirtual ? 'No promotion payments yet' : 'Nothing here yet',
          body:
              'When you boost an event or post, those payments will appear here.',
          iconSvg: 'trending-up',
        );
      case 'ads':
        return (
          title: isVirtual ? 'No ad payments yet' : 'Nothing here yet',
          body: 'Ads you run on Nuru will be billed and listed here.',
          iconSvg: 'star',
        );
      default:
        return (
          title: 'No payments yet',
          body: 'Your receipts will appear here.',
          iconSvg: 'wallet',
        );
    }
  }

  Widget _emptyState() {
    final c = _emptyCopy();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 60),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(28),
            ),
            alignment: Alignment.center,
            child: AppIcon(c.iconSvg, size: 34, color: const Color(0xFFB45309)),
          ),
          const SizedBox(height: 18),
          Text(c.title,
              textAlign: TextAlign.center,
              style: _f(size: 17, weight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            c.body,
            textAlign: TextAlign.center,
            style: _f(
              size: 13,
              color: AppColors.textSecondary,
              weight: FontWeight.w500,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }


  // ─── Skeletons (mirror the real layout, animated shimmer) ────────
  Widget _shimmerBox(double w, double h, {double r = 8, Color? color}) {
    return _ShimmerBox(width: w, height: h, radius: r, color: color);
  }

  Widget _skeletonHero() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEFEFF3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _shimmerBox(86, 12, r: 6),
                const SizedBox(height: 12),
                _shimmerBox(170, 24, r: 8),
                const SizedBox(height: 10),
                _shimmerBox(120, 11, r: 6),
              ],
            ),
          ),
          _shimmerBox(54, 20, r: 999),
        ],
      ),
    );
  }

  Widget _skeletonRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
      child: Row(
        children: [
          _shimmerBox(44, 44, r: 12),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _shimmerBox(140, 13, r: 6),
                const SizedBox(height: 8),
                _shimmerBox(180, 11, r: 6),
                const SizedBox(height: 6),
                _shimmerBox(90, 10, r: 6),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _shimmerBox(72, 13, r: 6),
              const SizedBox(height: 8),
              _shimmerBox(46, 14, r: 999),
            ],
          ),
          const SizedBox(width: 8),
          _shimmerBox(14, 14, r: 4),
        ],
      ),
    );
  }


  // ─── Filter sheet ────────────────────────────────────────────────
  void _openFilterSheet() {
    String tmpStatus = _statusFilter;
    String tmpSort = _sortBy;

    const statusOpts = [
      ['all', 'All payments', 'See everything in this category'],
      ['paid', 'Paid', 'Successfully completed payments'],
      ['pending', 'Pending', 'Still being processed'],
      ['failed', 'Failed', 'Did not go through'],
    ];
    const sortOpts = [
      ['newest', 'Newest first', 'Most recent at the top'],
      ['oldest', 'Oldest first', 'Earliest at the top'],
      ['highest', 'Highest amount', 'Largest payments first'],
      ['lowest', 'Lowest amount', 'Smallest payments first'],
    ];

    Widget optionRow({
      required String label,
      required String subtitle,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? AppColors.primary : const Color(0xFFEFEFF3),
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: _f(
                            size: 14,
                            weight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          )),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: _f(
                            size: 11.5,
                            weight: FontWeight.w500,
                            color: AppColors.textTertiary,
                          )),
                    ],
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? AppColors.primary : Colors.white,
                    border: Border.all(
                      color: selected
                          ? AppColors.primary
                          : const Color(0xFFD1D5DB),
                      width: 2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: selected
                      ? const AppIcon('check', size: 12, color: Colors.white)
                      : null,
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget sectionHeader(String title, String iconName) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: AppIcon(iconName, size: 14, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Text(title,
                  style: _f(
                    size: 13,
                    weight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  )),
            ],
          ),
        );

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final dirty =
              tmpStatus != _statusFilter || tmpSort != _sortBy;
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 12, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Filter & sort',
                                style: _f(size: 18, weight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text('Tune what you see in your history',
                                style: _f(
                                  size: 12.5,
                                  weight: FontWeight.w500,
                                  color: AppColors.textTertiary,
                                )),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const AppIcon('close',
                            size: 16, color: AppColors.textSecondary),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFFF6F6F8),
                          shape: const CircleBorder(),
                          padding: const EdgeInsets.all(8),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        sectionHeader('Payment status', 'filter'),
                        for (int i = 0; i < statusOpts.length; i++) ...[
                          optionRow(
                            label: statusOpts[i][1],
                            subtitle: statusOpts[i][2],
                            selected: tmpStatus == statusOpts[i][0],
                            onTap: () =>
                                setSheet(() => tmpStatus = statusOpts[i][0]),
                          ),
                          if (i != statusOpts.length - 1)
                            const SizedBox(height: 8),
                        ],
                        const SizedBox(height: 22),
                        sectionHeader('Sort order', 'chevron-down'),
                        for (int i = 0; i < sortOpts.length; i++) ...[
                          optionRow(
                            label: sortOpts[i][1],
                            subtitle: sortOpts[i][2],
                            selected: tmpSort == sortOpts[i][0],
                            onTap: () =>
                                setSheet(() => tmpSort = sortOpts[i][0]),
                          ),
                          if (i != sortOpts.length - 1)
                            const SizedBox(height: 8),
                        ],
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.fromLTRB(
                      20, 12, 20, 14 + MediaQuery.of(ctx).padding.bottom),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xFFEFEFF3))),
                  ),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => setSheet(() {
                          tmpStatus = 'all';
                          tmpSort = 'newest';
                        }),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 14),
                        ),
                        child: Text('Reset',
                            style: _f(size: 13.5, weight: FontWeight.w700)),
                      ),
                      const Spacer(),
                      SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.textOnPrimary,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 22),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: () {
                            setState(() {
                              _statusFilter = tmpStatus;
                              _sortBy = tmpSort;
                            });
                            Navigator.pop(ctx);
                          },
                          child: Text(
                            dirty ? 'Apply filters' : 'Done',
                            style: _f(
                              size: 14,
                              weight: FontWeight.w800,
                              color: AppColors.textOnPrimary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CategoryDef {
  final String key;
  final String label;
  const _CategoryDef(this.key, this.label);
}

class _Visual {
  final Color bg;
  final Color fg;
  final String svg;
  const _Visual({required this.bg, required this.fg, required this.svg});
}

/// Animated shimmer block used by the payment-history skeletons.
class _ShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final double radius;
  final Color? color;
  const _ShimmerBox({
    required this.width,
    required this.height,
    required this.radius,
    this.color,
  });

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.color ?? const Color(0xFFEFF0F3);
    final highlight = const Color(0xFFF8F9FB);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.radius),
          child: ShaderMask(
            shaderCallback: (rect) {
              return LinearGradient(
                begin: Alignment(-1 + 2 * t, 0),
                end: Alignment(1 + 2 * t, 0),
                colors: [base, highlight, base],
                stops: const [0.35, 0.5, 0.65],
              ).createShader(rect);
            },
            blendMode: BlendMode.srcATop,
            child: Container(
              width: widget.width,
              height: widget.height,
              color: base,
            ),
          ),
        );
      },
    );
  }
}
