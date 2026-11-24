import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../models/catalog.dart';
import '../../shared/widgets/pulse.dart';
import '../../core/api/api_client.dart';
import '../../core/storage/app_storage.dart';
import 'cart_panel.dart';
import 'cart_store.dart';
import 'modifier_dialog.dart';
import 'pos_providers.dart';
import 'stock_guard.dart';

/// Order taking for one table (port of components/pos/PosContent.tsx).
class OrderPage extends ConsumerStatefulWidget {
  const OrderPage({super.key, required this.tableId, this.backRoute = '/pos/tables'});
  final int? tableId;
  final String backRoute;
  @override
  ConsumerState<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends ConsumerState<OrderPage> {
  String _category = 'Toutes';
  String _query = '';
  bool _search = false;

  @override
  void initState() {
    super.initState();
    final id = widget.tableId;
    if (id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(cartProvider.notifier).initForTable(id));
    }
  }

  void _toast(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m), backgroundColor: Theme.of(context).colorScheme.error));

  Future<void> _onProductTap(Product p) async {
    final id = widget.tableId!;
    final blocked = wouldExceedStock(
      allowOversell: ref.read(allowOversellProvider).value ?? false,
      cart: ref.read(cartProvider),
      order: ref.read(activeOrderProvider(id)).value,
      productId: p.id,
      productType: p.type,
      stockCount: p.stockCount,
    );
    if (blocked) return _toast('Stock insuffisant pour ${p.name}');

    if (p.modifiers.isEmpty) {
      ref.read(cartProvider.notifier).addItem(product: p);
      return;
    }
    final chosen = await showModifierDialog(context, p);
    if (chosen != null && mounted) ref.read(cartProvider.notifier).addItem(product: p, modifiers: chosen);
  }

  String _tableLabel(int id) {
    final floors = ref.watch(floorsProvider).value ?? const [];
    for (final f in floors) {
      for (final t in f.tables) {
        if (t.id == id) return t.name;
      }
    }
    return '$id';
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.tableId;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    if (id == null) {
      return Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(LucideIcons.store, size: 64, color: AppColors.slate400),
            const SizedBox(height: 16),
            Text('TABLE NON IDENTIFIÉE', style: titleStyle.copyWith(fontSize: 22)),
            const SizedBox(height: 24),
            FilledButton(onPressed: () => context.go(widget.backRoute), child: const Text('Choisir une table')),
          ]),
        ),
      );
    }

    // Adopt the server's order id (never syncing back to null: virtual tables never resolve an open order).
    ref.listen(activeOrderProvider(id), (_, next) {
      final order = next.value;
      if (order != null) ref.read(cartProvider.notifier).syncOrderId(order.id);
    });

    final products = ref.watch(productsProvider);
    final cart = ref.watch(cartProvider);
    final label = _tableLabel(id);
    final wide = MediaQuery.sizeOf(context).width >= 1000;

    final menu = Column(children: [
      _header(context, label, cart, wide),
      if (_search && !wide) _searchField(),
      _categories(products.value ?? const []),
      Expanded(
        child: products.when(
          loading: () => const _MenuSkeleton(),
          error: (e, _) => Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Impossible de charger le menu'),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: () => ref.invalidate(productsProvider), child: const Text('Réessayer')),
            ]),
          ),
          data: (list) => _grid(list),
        ),
      ),
    ]);

    return Scaffold(
      backgroundColor: dark ? AppColors.slate950 : AppColors.slate50,
      body: SafeArea(
        child: wide
            ? Row(children: [
                Expanded(child: Container(color: dark ? AppColors.slate950 : Colors.white, child: menu)),
                Container(
                  width: 400,
                  decoration: BoxDecoration(border: Border(left: BorderSide(color: scheme.outline))),
                  child: CartPanel(tableId: id, tableLabel: label),
                ),
              ])
            : Container(color: dark ? AppColors.slate950 : Colors.white, child: menu),
      ),
    );
  }

  Widget _header(BuildContext context, String label, CartState cart, bool wide) {
    final scheme = Theme.of(context).colorScheme;
    final id = widget.tableId!;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        _SquareButton(icon: LucideIcons.chevronLeft, onTap: () => context.canPop() ? context.pop() : context.go(widget.backRoute)),
        const SizedBox(width: 12),
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('TABLE', style: microLabelStyle.copyWith(color: scheme.primary, letterSpacing: 2)),
            Text(label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle.copyWith(fontSize: 28, height: 1)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(child: wide ? _searchField() : const SizedBox.shrink()),
        // Le menu est gardé en mémoire toute la session: ce bouton recharge produits et options.
        _SquareButton(icon: LucideIcons.refreshCw, onTap: () => ref.invalidate(productsProvider)),
        const SizedBox(width: 8),
        if (!wide) ...[
          _SquareButton(icon: LucideIcons.search, onTap: () => setState(() => _search = !_search)),
          const SizedBox(width: 8),
          Stack(clipBehavior: Clip.none, children: [
            _SquareButton(
              icon: LucideIcons.shoppingCart,
              onTap: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                showDragHandle: true,
                builder: (sheetCtx) => FractionallySizedBox(
                  heightFactor: 0.92,
                  child: CartPanel(tableId: id, tableLabel: label, onSent: () => Navigator.of(sheetCtx).pop()),
                ),
              ),
            ),
            if (cart.items.isNotEmpty)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                  child: Text('${cart.items.length}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: scheme.onPrimary)),
                ),
              ),
          ]),
        ],
      ]),
    );
  }

  Widget _searchField() => Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: TextField(
            autofocus: false,
            onChanged: (v) => setState(() => _query = v),
            style: const TextStyle(fontWeight: FontWeight.w700),
            decoration: const InputDecoration(hintText: 'Rechercher...', prefixIcon: Icon(LucideIcons.search, size: 20)),
          ),
        ),
      );

  Widget _categories(List<Product> products) {
    final scheme = Theme.of(context).colorScheme;
    final names = <String>{for (final p in products) if (p.categoryName.isNotEmpty) p.categoryName};
    final cats = ['Toutes', ...names];
    return Container(
      height: 80,
      decoration: BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: scheme.outline))),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        itemCount: cats.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final c = cats[i];
          final active = c == _category;
          return GestureDetector(
            onTap: () => setState(() => _category = c),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              transform: Matrix4.translationValues(0, active ? -3 : 0, 0),
              padding: const EdgeInsets.symmetric(horizontal: 28),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? scheme.primary : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                boxShadow: active ? [BoxShadow(color: scheme.primary.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))] : null,
              ),
              child: Text(c.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: active ? scheme.onPrimary : AppColors.slate400)),
            ),
          );
        },
      ),
    );
  }

  Widget _grid(List<Product> all) {
    final backend = ref.read(storageProvider).backendIp;
    final q = _query.toLowerCase();
    final list = all.where((p) => (_category == 'Toutes' || p.categoryName == _category) && p.name.toLowerCase().contains(q)).toList();
    if (list.isEmpty) {
      return Center(child: Text('AUCUN PRODUIT', style: microLabelStyle.copyWith(color: AppColors.slate400, letterSpacing: 3)));
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 200, mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 0.78),
      itemCount: list.length,
      itemBuilder: (_, i) => _ProductCard(
        product: list[i],
        imageUrl: list[i].imageUrl == null || list[i].imageUrl!.isEmpty ? null : resolveMediaUrl(list[i].imageUrl!, backend),
        onTap: () => _onProductTap(list[i]),
      ),
    );
  }
}

class _SquareButton extends StatelessWidget {
  const _SquareButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
          child: Icon(icon, size: 22),
        ),
      );
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.imageUrl, required this.onTap});
  final Product product;
  final String? imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: dark ? AppColors.slate900 : Colors.white,
      borderRadius: BorderRadius.circular(32),
      child: InkWell(
        borderRadius: BorderRadius.circular(32),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(32), border: Border.all(color: scheme.outline, width: 2)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(color: dark ? AppColors.darkMuted : AppColors.slate50, borderRadius: BorderRadius.circular(24)),
                clipBehavior: Clip.antiAlias,
                child: Stack(fit: StackFit.expand, children: [
                  if (imageUrl != null)
                    // Decode at card size: full-resolution uploads are slow and heavy on a phone.
                    Image.network(
                      imageUrl!,
                      fit: BoxFit.cover,
                      cacheWidth: 360,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) => const _PlaceholderIcon(),
                    )
                  else
                    const _PlaceholderIcon(),
                  if (product.categoryName.isNotEmpty)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(6)),
                        child: Text(product.categoryName, style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            Text(product.name.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
            Text(formatCurrency(product.price), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, color: scheme.primary)),
          ]),
        ),
      ),
    );
  }
}

class _PlaceholderIcon extends StatelessWidget {
  const _PlaceholderIcon();
  @override
  Widget build(BuildContext context) => const Center(child: Icon(LucideIcons.utensilsCrossed, size: 44, color: AppColors.slate400));
}

/// Placeholder cards shown while the menu loads (same grid geometry, so nothing jumps afterwards).
class _MenuSkeleton extends StatelessWidget {
  const _MenuSkeleton();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Pulse(
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 200, mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 0.78),
        itemCount: 12,
        itemBuilder: (_, _) => Container(
          decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(32)),
        ),
      ),
    );
  }
}
