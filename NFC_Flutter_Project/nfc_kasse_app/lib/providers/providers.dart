import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/api_config.dart';
import '../models/cart_item.dart';
import '../models/category_model.dart';
import '../models/customer_model.dart';
import '../models/product_model.dart';
import '../models/user_model.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/product_service.dart';
import '../services/sales_service.dart';
import '../services/stats_service.dart';
import '../services/update_service.dart';
import '../services/users_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

// ---------------------------------------------------------------------------
// Infrastructure
// ---------------------------------------------------------------------------

final storageProvider = Provider<FlutterSecureStorage>(
  (_) => const FlutterSecureStorage(),
);

/// The backend URL the user configured on the login screen.
/// Initialised from secure storage in main() so it survives app restarts.
final serverUrlProvider = StateProvider<String>(
  (ref) => ApiConfig.defaultBaseUrl,
);

/// Recreated automatically whenever [serverUrlProvider] changes, so a URL
/// update on the login screen takes effect for all subsequent requests.
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    ref.watch(storageProvider),
    baseUrl: ref.watch(serverUrlProvider),
  );
});

// ---------------------------------------------------------------------------
// Services
// ---------------------------------------------------------------------------

final authServiceProvider = Provider(
  (ref) => AuthService(ref.watch(apiClientProvider)),
);
final salesServiceProvider = Provider(
  (ref) => SalesService(ref.watch(apiClientProvider)),
);
final productServiceProvider = Provider(
  (ref) => ProductService(ref.watch(apiClientProvider)),
);
final statsServiceProvider = Provider(
  (ref) => StatsService(ref.watch(apiClientProvider)),
);
final usersServiceProvider = Provider(
  (ref) => UsersService(ref.watch(apiClientProvider)),
);
final updateServiceProvider = Provider(
  (ref) => UpdateService(ref.watch(apiClientProvider).dio),
);

/// Current app version string (e.g. "1.0.0"), read from the device at runtime.
final appVersionProvider = FutureProvider<String>(
  (_) async => (await PackageInfo.fromPlatform()).version,
);

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

/// Manages the authentication state for the whole app.
///
/// `build()` runs on app start: if a token is found in secure storage, it
/// silently restores the session by calling `/api/auth/me`. On failure (expired
/// token, network error) it clears storage and returns null → [LoginScreen] is shown.
class AuthNotifier extends AsyncNotifier<UserModel?> {
  @override
  Future<UserModel?> build() async {
    final client = ref.read(apiClientProvider);
    if (!await client.hasStoredTokens()) return null;
    try {
      return await ref.read(authServiceProvider).fetchMe();
    } catch (_) {
      await client.clearTokens();
      return null;
    }
  }

  Future<void> login(String username, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authServiceProvider).login(username, password),
    );
  }

  Future<void> logout() async {
    final token = await ref.read(storageProvider).read(key: 'refresh_token') ?? '';
    await ref.read(authServiceProvider).logout(token);
    state = const AsyncData(null);
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, UserModel?>(
  AuthNotifier.new,
);

// ---------------------------------------------------------------------------
// Cart
// ---------------------------------------------------------------------------

/// In-memory shopping cart. State is a list of [CartItem]s (one per product).
/// Multiple units of the same product are represented by [CartItem.quantity],
/// not by duplicate list entries.
class CartNotifier extends Notifier<List<CartItem>> {
  @override
  List<CartItem> build() => [];

  /// Adds [product] to the cart. If it is already present, increments the
  /// quantity instead of creating a second entry.
  void addProduct(ProductModel product) {
    final idx = state.indexWhere((i) => i.product.id == product.id);
    if (idx >= 0) {
      final list = [...state];
      list[idx] = list[idx].withQuantity(list[idx].quantity + 1);
      state = list;
    } else {
      state = [...state, CartItem(product: product, quantity: 1)];
    }
  }

  void removeItem(int productId) {
    state = state.where((i) => i.product.id != productId).toList();
  }

  void clear() => state = [];

  double get total => state.fold(0.0, (s, i) => s + i.subtotal);

  /// Expands each [CartItem] into [CartItem.quantity] repeated product IDs.
  ///
  /// The booking API expects one ID per purchased unit so it can create
  /// individual sale rows (enabling per-item cancellation). For example,
  /// 2 units of product 5 → `[5, 5]`.
  ///
  /// Note: the server de-duplicates IDs only for the product lookup (to avoid
  /// SQL `IN` de-duplication returning fewer rows). The full repeated list is
  /// used for pricing and sale row creation.
  List<int> get productIds =>
      state.expand((i) => List.filled(i.quantity, i.product.id)).toList();
}

final cartProvider = NotifierProvider<CartNotifier, List<CartItem>>(
  CartNotifier.new,
);

// ---------------------------------------------------------------------------
// UI state
// ---------------------------------------------------------------------------

final customerProvider = StateProvider<CustomerModel?>((ref) => null);

// Last successful booking for storno: {sale_ids, product_names, total}
final lastBookingProvider = StateProvider<Map<String, dynamic>?>((ref) => null);

final selectedCategoryProvider = StateProvider<CategoryModel?>((ref) => null);

final editModeProvider = StateProvider<bool>((ref) => false);

enum AppScreen { pos, stats, users, settings, account }

final currentScreenProvider = StateProvider<AppScreen>((ref) => AppScreen.pos);

// ---------------------------------------------------------------------------
// Async data
// ---------------------------------------------------------------------------

/// Products for a given category, keyed by category ID.
///
/// Watches [productsRefreshProvider] so that incrementing it causes all
/// category-specific instances to refetch (used after create/edit/delete).
final productsProvider = FutureProvider.family<List<ProductModel>, int>(
  (ref, categoryId) async {
    ref.watch(productsRefreshProvider); // invalidate trigger
    return ref.read(productServiceProvider).getProducts(categoryId);
  },
);

/// Incrementing this integer invalidates all [productsProvider] instances.
/// Pattern: `ref.read(productsRefreshProvider.notifier).state++`
final productsRefreshProvider = StateProvider<int>((ref) => 0);

// Incrementing this integer invalidates [categoriesProvider].
final categoriesRefreshProvider = StateProvider<int>((ref) => 0);

/// All categories visible to the logged-in user (filtered server-side by
/// their `user_category_access` rows or their manager status).
final categoriesProvider = FutureProvider<List<CategoryModel>>((ref) {
  ref.watch(categoriesRefreshProvider);
  return ref.read(productServiceProvider).getCategories();
});
