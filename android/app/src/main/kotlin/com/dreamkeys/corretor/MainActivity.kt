package com.dreamkeys.corretor

import android.content.Intent
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Espelho Android do canal de deep link do `AppDelegate.swift`.
 *
 * Por que um MethodChannel e não o roteamento nativo do engine: o
 * `FlutterDeepLinkingEnabled` empurra o path CRU pro Navigator e cai em
 * "Página não encontrada" (decisão documentada no Info.plist). Aqui a URL
 * inteira vai pro Dart e o `DeepLinkService` decide a rota.
 *
 * Cold start (app fechado): o intent já está no `getIntent()` quando o engine
 * sobe — guardamos em `pendingDeepLink` e o Dart resgata via `getInitialLink`,
 * porque nesse instante o handler do Flutter ainda não existe.
 * Warm start (`launchMode="singleTop"`): chega em `onNewIntent`.
 */
class MainActivity : FlutterFragmentActivity() {
    private var deepLinkChannel: MethodChannel? = null
    private var pendingDeepLink: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        extractLink(intent)?.let { pendingDeepLink = it }

        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEEP_LINK_CHANNEL,
        )
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialLink" -> {
                    result.success(pendingDeepLink)
                    pendingDeepLink = null
                }
                else -> result.notImplemented()
            }
        }
        deepLinkChannel = channel
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Mantém o getIntent() coerente com o último intent recebido.
        setIntent(intent)
        val link = extractLink(intent) ?: return
        pendingDeepLink = link
        deepLinkChannel?.invokeMethod("onLink", link)
    }

    /**
     * Só ACTION_VIEW carrega link (App Link https ou `dreamkeys://`); o
     * ACTION_MAIN do ícone do launcher não tem `data` e é ignorado.
     */
    private fun extractLink(intent: Intent?): String? {
        if (intent == null || intent.action != Intent.ACTION_VIEW) return null
        val data = intent.data ?: return null
        return data.toString().takeIf { it.isNotEmpty() }
    }

    companion object {
        private const val DEEP_LINK_CHANNEL = "com.dreamkeys.corretor/deep_link"
    }
}
