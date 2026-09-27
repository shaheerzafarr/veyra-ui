package com.example.veyra.e2ee

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Base64
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** The sole Flutter boundary to the pinned official libsignal Java API. */
class E2eeBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var engine: LibSignalEngine? = null

    fun register() {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        worker.execute {
            try {
                val value = dispatch(call)
                main.post { result.success(value) }
            } catch (error: EngineFailure) {
                main.post { result.error(error.code, error.message, null) }
            } catch (_: Exception) {
                main.post {
                    result.error(
                        "E2EE_NOT_INITIALIZED",
                        "Secure messaging operation failed",
                        null,
                    )
                }
            }
        }
    }

    private fun dispatch(call: MethodCall): Any = when (call.method) {
        "initialize" -> {
            val args = arguments(call)
            engine = LibSignalEngine(
                context.applicationContext,
                requiredString(args, "localUserId"),
                requiredString(args, "localDeviceId"),
            )
            true
        }
        "hasIdentity" -> requiredEngine().hasIdentity()
        "getPublicBundle" -> requiredEngine().publicBundle()
        "markPreKeysPublished" -> {
            val ids = (arguments(call)["ids"] as? List<*>)
                ?.map { (it as Number).toInt() }
                ?: throw EngineFailure("INVALID_BUNDLE", "Invalid pre-key identifiers")
            requiredEngine().markPreKeysPublished(ids)
            true
        }
        "replenishPreKeys" -> {
            val count = (arguments(call)["count"] as? Number)?.toInt()
                ?: throw EngineFailure("INVALID_BUNDLE", "Invalid pre-key count")
            requiredEngine().replenishPreKeys(count)
            true
        }
        "hasSession" -> withRemote(call) { engine, userId, deviceId ->
            engine.hasSession(userId, deviceId)
        }
        "establishSession" -> withRemote(call) { engine, userId, deviceId ->
            @Suppress("UNCHECKED_CAST")
            val bundle = arguments(call)["bundle"] as? Map<String, Any?>
                ?: throw EngineFailure("INVALID_BUNDLE", "Pre-key bundle is missing")
            engine.establishSession(userId, deviceId, bundle)
            true
        }
        "encrypt" -> withRemote(call) { engine, userId, deviceId ->
            val plaintext = arguments(call)["plaintext"] as? ByteArray
                ?: throw EngineFailure("INVALID_BUNDLE", "Plaintext payload is missing")
            engine.encrypt(userId, deviceId, plaintext)
        }
        "decrypt" -> withRemote(call) { engine, userId, deviceId ->
            val args = arguments(call)
            val ciphertext = try {
                Base64.decode(requiredString(args, "ciphertext"), Base64.NO_WRAP)
            } catch (_: IllegalArgumentException) {
                throw EngineFailure("DECRYPTION_FAILED", "Ciphertext encoding is invalid")
            }
            engine.decrypt(
                userId,
                deviceId,
                requiredString(args, "messageType"),
                ciphertext,
            )
        }
        "getSafetyNumber" -> withRemote(call) { engine, userId, deviceId ->
            engine.safetyNumber(userId, deviceId)
        }
        "markVerified" -> withRemote(call) { engine, userId, deviceId ->
            engine.markVerified(userId, deviceId)
            true
        }
        "verifyScannable" -> withRemote(call) { engine, userId, deviceId ->
            val scanned = arguments(call)["scannable"] as? ByteArray
                ?: throw EngineFailure("INVALID_BUNDLE", "Verification payload is missing")
            engine.verifyScannable(userId, deviceId, scanned)
        }
        "deleteSession" -> withRemote(call) { engine, userId, deviceId ->
            engine.deleteSession(userId, deviceId)
            true
        }
        else -> throw EngineFailure("UNSUPPORTED_PROTOCOL", "Unsupported secure operation")
    }

    private fun <T> withRemote(
        call: MethodCall,
        action: (LibSignalEngine, String, String) -> T,
    ): T {
        val args = arguments(call)
        return action(
            requiredEngine(),
            requiredString(args, "remoteUserId"),
            requiredString(args, "remoteDeviceId"),
        )
    }

    @Suppress("UNCHECKED_CAST")
    private fun arguments(call: MethodCall): Map<String, Any?> =
        call.arguments as? Map<String, Any?> ?: emptyMap()

    private fun requiredString(arguments: Map<String, Any?>, name: String): String =
        arguments[name] as? String
            ?: throw EngineFailure("INVALID_BUNDLE", "Required secure parameter is missing")

    private fun requiredEngine(): LibSignalEngine =
        engine ?: throw EngineFailure("E2EE_NOT_INITIALIZED", "Secure messaging is unavailable")

    companion object {
        private const val CHANNEL_NAME = "com.veyra/e2ee"
    }
}
