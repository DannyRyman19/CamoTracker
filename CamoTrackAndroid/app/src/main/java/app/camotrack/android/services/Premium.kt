package app.camotrack.android.services

import android.app.Activity
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.camotrack.android.BuildConfig
import app.camotrack.android.core.KeyValueStore
import app.camotrack.android.i18n.L
import app.camotrack.android.i18n.Strings
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import com.android.billingclient.api.acknowledgePurchase
import com.android.billingclient.api.queryProductDetails
import com.android.billingclient.api.queryPurchasesAsync
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.text.DateFormat
import java.util.Date
import java.util.Locale

/**
 * Premium (iOS Premium.swift) through Google Play Billing: a yearly
 * subscription or a one-off lifetime purchase. Removes ads, adds pins, camo
 * app icons and layout customisation. The answer is cached
 * (`mw4_premium`, as on iPhone) so the app opens right offline, and checked
 * against Play on each launch.
 */
object Premium {
    const val YEARLY = "premium_yearly"
    const val LIFETIME = "premium_lifetime"
    const val CACHE_KEY = "mw4_premium"
    const val SUBSCRIBER_KEY = "mw4_premium_subscriber"
    /** Debug builds without Play products: a test purchase that unlocks straight away. */
    const val FAKE_KEY = "mw4_debug_fake_premium"

    enum class Notice(private val key: String) {
        Purchased("purchased"), Restored("restored"), Pending("pending"),
        PurchaseFailed("purchase_failed"), RestoreFailed("restore_failed"), NothingToRestore("nothing");
        val title: String get() = L("ct.premium.notice.$key")
        val message: String get() = L("ct.premium.notice.${key}_message")
    }

    data class Plan(val lifetime: Boolean, val periodEnd: Long? = null, val renews: Boolean = true) {
        /** "Lifetime: yours for good", "Yearly · renews 3 Nov 2027", "Yearly" (iOS PremiumPlan.line). */
        val line: String
            get() = when {
                lifetime -> L("ct.premium.plan.lifetime")
                periodEnd == null -> L("mw4.ui.premium.yearly")
                else -> L(if (renews) "ct.premium.plan.renews" else "ct.premium.plan.ends",
                          DateFormat.getDateInstance(DateFormat.MEDIUM, Locale(Strings.language)).format(Date(periodEnd)))
            }
    }

    var isPremium by mutableStateOf(false); private set
    var isSubscriber by mutableStateOf(false); private set
    var plan by mutableStateOf<Plan?>(null); private set
    var products by mutableStateOf<List<ProductDetails>>(emptyList()); private set
    var purchasing by mutableStateOf(false); private set
    var loadFailed by mutableStateOf(false); private set
    /** Debug builds while Play has no products: offer test purchases. */
    val offersFake: Boolean get() = BuildConfig.DEBUG && products.isEmpty()

    private lateinit var store: KeyValueStore
    private lateinit var client: BillingClient
    private val scope = CoroutineScope(Dispatchers.Main.immediate)
    private var pendingBuy: CompletableDeferred<Notice?>? = null
    /** Called when Premium changes (the tracker's pins, the ads). */
    var onChange: ((Boolean) -> Unit)? = null

    fun start(context: Context, store: KeyValueStore) {
        this.store = store
        isPremium = store.getBoolean(CACHE_KEY) || (BuildConfig.DEBUG && store.getBoolean(FAKE_KEY))
        isSubscriber = store.getBoolean(SUBSCRIBER_KEY)
        client = BillingClient.newBuilder(context.applicationContext)
            .setListener { result, purchases -> scope.launch { onPurchases(result, purchases) } }
            .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
            .build()
        connect { scope.launch { loadProducts(); refresh() } }
    }

    private fun connect(then: () -> Unit) {
        if (client.isReady) return then()
        client.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                if (result.responseCode == BillingClient.BillingResponseCode.OK) then() else loadFailed = true
            }
            override fun onBillingServiceDisconnected() {}
        })
    }

    suspend fun loadProducts() {
        if (!client.isReady) return
        val subs = client.queryProductDetails(QueryProductDetailsParams.newBuilder().setProductList(listOf(
            QueryProductDetailsParams.Product.newBuilder().setProductId(YEARLY).setProductType(BillingClient.ProductType.SUBS).build(),
        )).build())
        val once = client.queryProductDetails(QueryProductDetailsParams.newBuilder().setProductList(listOf(
            QueryProductDetailsParams.Product.newBuilder().setProductId(LIFETIME).setProductType(BillingClient.ProductType.INAPP).build(),
        )).build())
        products = subs.productDetailsList.orEmpty() + once.productDetailsList.orEmpty()
        loadFailed = subs.billingResult.responseCode != BillingClient.BillingResponseCode.OK
    }

    /** Checks what this Google account owns. Returns whether anything was found. */
    suspend fun refresh(): Boolean {
        if (!client.isReady) return false
        val subs = client.queryPurchasesAsync(QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.SUBS).build())
        val once = client.queryPurchasesAsync(QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.INAPP).build())
        if (subs.billingResult.responseCode != BillingClient.BillingResponseCode.OK) return false
        val owned = (subs.purchasesList + once.purchasesList).filter { it.purchaseState == Purchase.PurchaseState.PURCHASED }
        owned.forEach { acknowledge(it) }
        val lifetime = owned.any { LIFETIME in it.products }
        val yearly = owned.firstOrNull { YEARLY in it.products }
        set(premium = lifetime || yearly != null, subscriber = yearly != null,
            plan = when {
                lifetime -> Plan(lifetime = true)
                yearly != null -> Plan(lifetime = false, renews = yearly.isAutoRenewing)
                else -> null
            })
        return owned.isNotEmpty()
    }

    private suspend fun acknowledge(p: Purchase) {
        if (!p.isAcknowledged) client.acknowledgePurchase(AcknowledgePurchaseParams.newBuilder().setPurchaseToken(p.purchaseToken).build())
    }

    private fun set(premium: Boolean, subscriber: Boolean, plan: Plan?) {
        if (BuildConfig.DEBUG && store.getBoolean(FAKE_KEY)) return
        isSubscriber = premium && subscriber
        this.plan = plan
        store.putBoolean(SUBSCRIBER_KEY, isSubscriber)
        if (premium == isPremium) return
        isPremium = premium
        store.putBoolean(CACHE_KEY, premium)
        onChange?.invoke(premium)
    }

    /** Buys `product`; null when the player cancelled. */
    suspend fun buy(activity: Activity, product: ProductDetails): Notice? {
        if (purchasing) return null
        val params = BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(product).apply {
            product.subscriptionOfferDetails?.firstOrNull()?.let { setOfferToken(it.offerToken) }
        }.build()
        purchasing = true
        val done = CompletableDeferred<Notice?>().also { pendingBuy = it }
        val launch = client.launchBillingFlow(activity, BillingFlowParams.newBuilder().setProductDetailsParamsList(listOf(params)).build())
        if (launch.responseCode != BillingClient.BillingResponseCode.OK) {
            purchasing = false; pendingBuy = null
            return if (launch.responseCode == BillingClient.BillingResponseCode.USER_CANCELED) null else Notice.PurchaseFailed
        }
        return done.await()
    }

    private suspend fun onPurchases(result: BillingResult, purchases: List<Purchase>?) {
        val notice = when (result.responseCode) {
            BillingClient.BillingResponseCode.OK -> {
                val list = purchases.orEmpty()
                if (list.any { it.purchaseState == Purchase.PurchaseState.PENDING }) Notice.Pending
                else { refresh(); if (isPremium) Notice.Purchased else Notice.PurchaseFailed }
            }
            BillingClient.BillingResponseCode.USER_CANCELED -> null
            BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED -> { refresh(); Notice.Restored }
            else -> Notice.PurchaseFailed
        }
        purchasing = false
        pendingBuy?.complete(notice); pendingBuy = null
    }

    suspend fun restore(): Notice {
        if (!client.isReady) return Notice.RestoreFailed
        val found = refresh()
        return if (isPremium) Notice.Restored else if (found) Notice.RestoreFailed else Notice.NothingToRestore
    }

    // ── Debug test purchases ──
    fun fakeBuy() {
        if (!BuildConfig.DEBUG) return
        store.putBoolean(FAKE_KEY, true)
        isPremium = true; plan = Plan(lifetime = true); onChange?.invoke(true)
    }

    fun resetFake() {
        if (!BuildConfig.DEBUG) return
        store.putBoolean(FAKE_KEY, false)
        isPremium = store.getBoolean(CACHE_KEY); plan = null; onChange?.invoke(isPremium)
    }

    /** Play's price for `id`, formatted ("£4.99 / year"), or null before products load. */
    fun price(id: String): String? = products.firstOrNull { it.productId == id }?.let { p ->
        p.oneTimePurchaseOfferDetails?.formattedPrice
            ?: p.subscriptionOfferDetails?.firstOrNull()?.pricingPhases?.pricingPhaseList?.lastOrNull()?.formattedPrice
    }
}
