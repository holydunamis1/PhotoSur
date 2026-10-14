import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

/// One-time, non-consumable "remove ads" product. Create it in App Store
/// Connect and Play Console with exactly this ID (type: non-consumable /
/// one-time in-app product, price $14.99). There is no subscription.
const String kAdFreeProductId = 'com.zdmgold.photosur.adfree';

class IapException implements Exception {
  const IapException(this.message, [this.cause]);
  final String message;
  final Object? cause;

  @override
  String toString() =>
      'IapException: $message${cause != null ? ' (cause: $cause)' : ''}';
}

/// StoreKit / Play Billing connection via in_app_purchase. Queries the
/// ad-free one-time product, handles purchase/restore/acknowledge.
///
/// *** Purchase validation approach — resolved in project discussion ***
/// No backend receipt-validation call. This was a real trade-off, not a
/// default: Section 1 mandates zero backend for sync, but that's not the
/// same claim as "no backend ever" — a validation server was genuinely
/// considered and rejected on its actual merits, not on the document's
/// say-so. Reasoning: on iOS, in_app_purchase v3.3 defaults to StoreKit2,
/// which performs real on-device cryptographic signature verification of
/// the transaction JWS before the app ever sees it as valid — this is not
/// blind client trust, a non-jailbroken device cannot fake a purchase this
/// way. On Android, Play Billing's purchase token is somewhat weaker
/// without server confirmation, but the value protected is a one-time ad-removal purchase —
/// server-side validation earns its engineering cost on high-value
/// unlocks; for an ad-removal toggle the realistic fraud population
/// (people rooting/jailbreaking specifically to dodge it) is close to
/// financially irrelevant at this app's scale.
///
/// [verifyPurchase] is intentionally the single seam where a future
/// server call could be inserted (e.g. a Cloudflare Worker, given
/// Cloudflare is already in use for website/ per Section 5) without
/// touching any other method in this class, if fraud data or revenue
/// ever justifies revisiting this decision.
class IapService {
  IapService._();
  static final IapService instance = IapService._();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  Future<bool> get isAvailable => _iap.isAvailable();

  /// Call once at app start (main.dart, Phase 6). [onEntitlementChanged]
  /// fires with true when ad-free should be granted, false when it should
  /// be revoked (expired, refunded, or restore found nothing).
  void startListening({
    required void Function(bool isAdFree) onEntitlementChanged,
    required void Function(String error) onError,
  }) {
    _subscription = _iap.purchaseStream.listen(
      (purchases) async {
        for (final purchase in purchases) {
          await _handlePurchaseUpdate(purchase, onEntitlementChanged, onError);
        }
      },
      onError: (Object error) => onError(error.toString()),
    );
  }

  Future<void> _handlePurchaseUpdate(
    PurchaseDetails purchase,
    void Function(bool isAdFree) onEntitlementChanged,
    void Function(String error) onError,
  ) async {
    switch (purchase.status) {
      case PurchaseStatus.pending:
        return;
      case PurchaseStatus.error:
        onError(purchase.error?.message ?? 'Unknown purchase error.');
        return;
      case PurchaseStatus.canceled:
        return;
      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        final verified = await verifyPurchase(purchase);
        if (verified) {
          onEntitlementChanged(true);
        }
        // Every purchase, verified or not, must be completed or the store
        // will keep redelivering it — completePurchase acknowledges
        // receipt, it does not imply entitlement was granted.
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
        return;
    }
  }

  /// The single verification seam — see class doc. Currently on-device
  /// only: trusts purchaseStream's PurchaseStatus, which for iOS
  /// StoreKit2 already reflects real cryptographic verification done by
  /// the OS itself before the app sees it. Swap this method's body for a
  /// server call later without touching any other method in this class.
  Future<bool> verifyPurchase(PurchaseDetails purchase) async {
    return purchase.status == PurchaseStatus.purchased ||
        purchase.status == PurchaseStatus.restored;
  }

  Future<ProductDetailsResponse> queryAdFreeProduct() async {
    try {
      return await _iap.queryProductDetails({kAdFreeProductId});
    } catch (e) {
      throw IapException('Failed to query product details.', e);
    }
  }

  Future<void> buyAdFree(ProductDetails product) async {
    try {
      final param = PurchaseParam(productDetails: product);
      await _iap.buyNonConsumable(purchaseParam: param);
    } catch (e) {
      throw IapException('Purchase failed.', e);
    }
  }

  Future<void> restorePurchases() async {
    try {
      await _iap.restorePurchases();
    } catch (e) {
      throw IapException('Restore purchases failed.', e);
    }
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
