package com.example.veyra.e2ee

import android.content.Context
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import org.signal.libsignal.protocol.DuplicateMessageException
import org.signal.libsignal.protocol.IdentityKey
import org.signal.libsignal.protocol.IdentityKeyPair
import org.signal.libsignal.protocol.InvalidKeyException
import org.signal.libsignal.protocol.InvalidMessageException
import org.signal.libsignal.protocol.NoSessionException
import org.signal.libsignal.protocol.SessionBuilder
import org.signal.libsignal.protocol.SessionCipher
import org.signal.libsignal.protocol.SignalProtocolAddress
import org.signal.libsignal.protocol.UntrustedIdentityException
import org.signal.libsignal.protocol.ecc.ECKeyPair
import org.signal.libsignal.protocol.ecc.ECPublicKey
import org.signal.libsignal.protocol.fingerprint.NumericFingerprintGenerator
import org.signal.libsignal.protocol.kem.KEMKeyPair
import org.signal.libsignal.protocol.kem.KEMKeyType
import org.signal.libsignal.protocol.kem.KEMPublicKey
import org.signal.libsignal.protocol.message.CiphertextMessage
import org.signal.libsignal.protocol.message.PreKeySignalMessage
import org.signal.libsignal.protocol.message.SignalMessage
import org.signal.libsignal.protocol.state.KyberPreKeyRecord
import org.signal.libsignal.protocol.state.PreKeyBundle
import org.signal.libsignal.protocol.state.PreKeyRecord
import org.signal.libsignal.protocol.state.SignedPreKeyRecord
import org.signal.libsignal.protocol.util.KeyHelper
import java.util.UUID

internal class LibSignalEngine(
    context: Context,
    private val localUserId: String,
    private val localDeviceId: String,
) {
    private val state =
        KeystoreBackedStateStore(context, "${validated(localUserId)}_${validated(localDeviceId)}")
    private var metadata: Metadata
    private val store: PersistentSignalStore
    private val localAddress = address(localUserId, localDeviceId)

    init {
        state.ensureProtectionKey()
        metadata = loadOrCreateMetadata()
        val identity = state.read(IDENTITY_RECORD)?.useBytes { IdentityKeyPair(it) }
            ?: throw EngineFailure("IDENTITY_MISSING", "Device identity is unavailable")
        store = PersistentSignalStore(
            state,
            identity,
            metadata.registrationId,
            signedPreKeyIds = { listOf(metadata.signedPreKeyId) },
            kyberPreKeyIds = { metadata.preKeyIds },
        )
    }

    fun hasIdentity(): Boolean = state.has(IDENTITY_RECORD)

    fun publicBundle(): Map<String, Any> {
        val signed = store.loadSignedPreKey(metadata.signedPreKeyId)
        val preKeys = metadata.preKeyIds.filterNot { state.has("published_$it") }.map { id ->
            val preKey = store.loadPreKey(id)
            val kyber = store.loadKyberPreKey(id)
            mapOf(
                "prekeyId" to id,
                "publicKey" to encoded(preKey.keyPair.publicKey.serialize()),
                "kyberPrekeyId" to id,
                "kyberPublicKey" to encoded(kyber.keyPair.publicKey.serialize()),
                "kyberSignature" to encoded(kyber.signature),
            )
        }
        return mapOf(
            "protocolVersion" to PROTOCOL_VERSION,
            "registrationId" to metadata.registrationId,
            "identityPublicKey" to encoded(store.identityKeyPair.publicKey.serialize()),
            "signedPrekeyId" to signed.id,
            "signedPrekeyPublic" to encoded(signed.keyPair.publicKey.serialize()),
            "signedPrekeySignature" to encoded(signed.signature),
            "prekeys" to preKeys,
        )
    }

    fun markPreKeysPublished(ids: List<Int>) {
        ids.forEach { state.write("published_$it", byteArrayOf(1)) }
    }

    fun replenishPreKeys(count: Int) {
        if (count !in 1..MAX_PREKEY_REPLENISHMENT) {
            throw EngineFailure("INVALID_BUNDLE", "Invalid pre-key replenishment count")
        }
        val firstId = metadata.nextPreKeyId
        val ids = (firstId until firstId + count).toList()
        ids.forEach { id ->
            state.write("prekey_$id", PreKeyRecord(id, ECKeyPair.generate()).serialize())
            val kyberPair = KEMKeyPair.generate(KEMKeyType.KYBER_1024)
            val signature = store.identityKeyPair.privateKey
                .calculateSignature(kyberPair.publicKey.serialize())
            state.write(
                "kyber_$id",
                KyberPreKeyRecord(id, System.currentTimeMillis(), kyberPair, signature).serialize(),
            )
        }
        metadata = metadata.copy(
            preKeyIds = metadata.preKeyIds + ids,
            nextPreKeyId = firstId + count,
        )
        persistMetadata()
    }

    fun hasSession(remoteUserId: String, remoteDeviceId: String): Boolean =
        store.containsSession(address(remoteUserId, remoteDeviceId))

    fun establishSession(
        remoteUserId: String,
        remoteDeviceId: String,
        bundle: Map<String, Any?>,
    ) {
        try {
            val oneTime = requiredMap(bundle, "oneTimePrekey")
            val remoteAddress = address(remoteUserId, remoteDeviceId)
            val preKeyBundle = PreKeyBundle(
                requiredInt(bundle, "registrationId"),
                SIGNAL_DEVICE_ID,
                requiredInt(oneTime, "prekeyId"),
                ECPublicKey(decoded(oneTime, "publicKey")),
                requiredInt(bundle, "signedPrekeyId"),
                ECPublicKey(decoded(bundle, "signedPrekeyPublic")),
                decoded(bundle, "signedPrekeySignature"),
                IdentityKey(decoded(bundle, "identityPublicKey")),
                requiredInt(oneTime, "kyberPrekeyId"),
                KEMPublicKey(decoded(oneTime, "kyberPublicKey")),
                decoded(oneTime, "kyberSignature"),
            )
            SessionBuilder(store, store, store, store, remoteAddress, localAddress)
                .process(preKeyBundle)
        } catch (error: UntrustedIdentityException) {
            throw EngineFailure("IDENTITY_CHANGED", "Remote device identity changed")
        } catch (error: InvalidKeyException) {
            throw EngineFailure("INVALID_BUNDLE", "Remote pre-key bundle is invalid")
        }
    }

    fun encrypt(remoteUserId: String, remoteDeviceId: String, plaintext: ByteArray): Map<String, Any> {
        try {
            val remote = address(remoteUserId, remoteDeviceId)
            val message = SessionCipher(store, store, store, store, store, localAddress, remote)
                .encrypt(plaintext)
            return mapOf(
                "protocolVersion" to PROTOCOL_VERSION,
                "messageType" to when (message.type) {
                    CiphertextMessage.PREKEY_TYPE -> "prekey"
                    CiphertextMessage.WHISPER_TYPE -> "signal"
                    else -> throw EngineFailure("UNSUPPORTED_PROTOCOL", "Unsupported message type")
                },
                "ciphertext" to encoded(message.serialize()),
            )
        } catch (error: NoSessionException) {
            throw EngineFailure("SESSION_MISSING", "Secure session is unavailable")
        } catch (error: UntrustedIdentityException) {
            throw EngineFailure("IDENTITY_CHANGED", "Remote device identity changed")
        } finally {
            plaintext.fill(0)
        }
    }

    fun decrypt(
        remoteUserId: String,
        remoteDeviceId: String,
        messageType: String,
        ciphertext: ByteArray,
    ): Map<String, Any> {
        try {
            val remote = address(remoteUserId, remoteDeviceId)
            val cipher = SessionCipher(store, store, store, store, store, localAddress, remote)
            val plaintext = when (messageType) {
                "prekey" -> cipher.decrypt(PreKeySignalMessage(ciphertext))
                "signal" -> cipher.decrypt(SignalMessage(ciphertext))
                else -> throw EngineFailure("UNSUPPORTED_PROTOCOL", "Unsupported message type")
            }
            return mapOf(
                "plaintext" to plaintext,
                "identityTrust" to if (store.isVerified(remote)) "verified" else "trusted",
            )
        } catch (error: UntrustedIdentityException) {
            throw EngineFailure("IDENTITY_CHANGED", "Remote device identity changed")
        } catch (error: DuplicateMessageException) {
            throw EngineFailure("DECRYPTION_FAILED", "Duplicate protocol message")
        } catch (error: InvalidMessageException) {
            throw EngineFailure("DECRYPTION_FAILED", "Authenticated decryption failed")
        } catch (error: Exception) {
            if (error is EngineFailure) throw error
            throw EngineFailure("DECRYPTION_FAILED", "Authenticated decryption failed")
        } finally {
            ciphertext.fill(0)
        }
    }

    fun safetyNumber(remoteUserId: String, remoteDeviceId: String): Map<String, Any> {
        val remote = address(remoteUserId, remoteDeviceId)
        val fingerprint = fingerprint(remote, remoteUserId, remoteDeviceId)
        return mapOf(
            "display" to fingerprint.displayableFingerprint.displayText,
            "scannable" to encoded(fingerprint.scannableFingerprint.serialized),
            "verified" to store.isVerified(remote),
        )
    }

    fun verifyScannable(
        remoteUserId: String,
        remoteDeviceId: String,
        scanned: ByteArray,
    ): Boolean {
        val remote = address(remoteUserId, remoteDeviceId)
        val matches = try {
            fingerprint(remote, remoteUserId, remoteDeviceId)
                .scannableFingerprint.compareTo(scanned)
        } catch (_: Exception) {
            false
        } finally {
            scanned.fill(0)
        }
        if (matches) store.markVerified(remote)
        return matches
    }

    fun markVerified(remoteUserId: String, remoteDeviceId: String) {
        store.markVerified(address(remoteUserId, remoteDeviceId))
    }

    fun deleteSession(remoteUserId: String, remoteDeviceId: String) {
        store.deleteSession(address(remoteUserId, remoteDeviceId))
    }

    private fun loadOrCreateMetadata(): Metadata {
        state.read(METADATA_RECORD)?.let { bytes ->
            return bytes.useBytes { Metadata.fromJson(JSONObject(String(it, Charsets.UTF_8))) }
        }
        val identity = IdentityKeyPair.generate()
        val registrationId = KeyHelper.generateRegistrationId(false)
        val signedPreKeyId = 1
        val signedPair = ECKeyPair.generate()
        val signedSignature = identity.privateKey.calculateSignature(signedPair.publicKey.serialize())
        val signedRecord = SignedPreKeyRecord(
            signedPreKeyId,
            System.currentTimeMillis(),
            signedPair,
            signedSignature,
        )
        state.write(IDENTITY_RECORD, identity.serialize())
        state.write("signed_$signedPreKeyId", signedRecord.serialize())
        val ids = (1..INITIAL_PREKEY_COUNT).toList()
        ids.forEach { id ->
            state.write("prekey_$id", PreKeyRecord(id, ECKeyPair.generate()).serialize())
            val kyberPair = KEMKeyPair.generate(KEMKeyType.KYBER_1024)
            val signature = identity.privateKey.calculateSignature(kyberPair.publicKey.serialize())
            state.write(
                "kyber_$id",
                KyberPreKeyRecord(id, System.currentTimeMillis(), kyberPair, signature).serialize(),
            )
        }
        val created = Metadata(registrationId, signedPreKeyId, ids, INITIAL_PREKEY_COUNT + 1)
        state.write(METADATA_RECORD, created.toJson().toString().toByteArray(Charsets.UTF_8))
        return created
    }

    private fun persistMetadata() {
        state.write(METADATA_RECORD, metadata.toJson().toString().toByteArray(Charsets.UTF_8))
    }

    private fun fingerprint(
        remote: SignalProtocolAddress,
        remoteUserId: String,
        remoteDeviceId: String,
    ) = NumericFingerprintGenerator(FINGERPRINT_ITERATIONS).createFor(
        FINGERPRINT_VERSION,
        "$localUserId.$localDeviceId".toByteArray(Charsets.UTF_8),
        store.identityKeyPair.publicKey,
        "$remoteUserId.$remoteDeviceId".toByteArray(Charsets.UTF_8),
        store.getIdentity(remote)
            ?: throw EngineFailure("SESSION_MISSING", "Remote identity is unavailable"),
    )

    private data class Metadata(
        val registrationId: Int,
        val signedPreKeyId: Int,
        val preKeyIds: List<Int>,
        val nextPreKeyId: Int,
    ) {
        fun toJson(): JSONObject = JSONObject()
            .put("registrationId", registrationId)
            .put("signedPreKeyId", signedPreKeyId)
            .put("preKeyIds", JSONArray(preKeyIds))
            .put("nextPreKeyId", nextPreKeyId)

        companion object {
            fun fromJson(json: JSONObject): Metadata {
                val values = json.getJSONArray("preKeyIds")
                val ids = List(values.length()) { values.getInt(it) }
                return Metadata(
                    json.getInt("registrationId"),
                    json.getInt("signedPreKeyId"),
                    ids,
                    json.optInt("nextPreKeyId", (ids.maxOrNull() ?: 0) + 1),
                )
            }
        }
    }

    private fun address(userId: String, deviceId: String) =
        SignalProtocolAddress("${validated(userId)}.${validated(deviceId)}", SIGNAL_DEVICE_ID)

    private fun validated(value: String): String =
        try {
            UUID.fromString(value).toString()
        } catch (_: IllegalArgumentException) {
            throw EngineFailure("INVALID_BUNDLE", "Invalid device address")
        }

    private fun encoded(value: ByteArray): String = Base64.encodeToString(value, Base64.NO_WRAP)

    private fun decoded(map: Map<String, Any?>, key: String): ByteArray =
        try {
            Base64.decode(map[key] as String, Base64.NO_WRAP)
        } catch (_: Exception) {
            throw EngineFailure("INVALID_BUNDLE", "Invalid public material")
        }

    @Suppress("UNCHECKED_CAST")
    private fun requiredMap(map: Map<String, Any?>, key: String): Map<String, Any?> =
        map[key] as? Map<String, Any?>
            ?: throw EngineFailure("INVALID_BUNDLE", "Incomplete pre-key bundle")

    private fun requiredInt(map: Map<String, Any?>, key: String): Int =
        (map[key] as? Number)?.toInt()
            ?: throw EngineFailure("INVALID_BUNDLE", "Incomplete pre-key bundle")

    private inline fun <T> ByteArray.useBytes(block: (ByteArray) -> T): T =
        try {
            block(this)
        } finally {
            fill(0)
        }

    companion object {
        private const val PROTOCOL_VERSION = 1
        private const val SIGNAL_DEVICE_ID = 1
        private const val INITIAL_PREKEY_COUNT = 50
        private const val MAX_PREKEY_REPLENISHMENT = 100
        private const val FINGERPRINT_VERSION = 1
        private const val FINGERPRINT_ITERATIONS = 5200
        private const val IDENTITY_RECORD = "identity_local"
        private const val METADATA_RECORD = "metadata"
    }
}

internal class EngineFailure(val code: String, override val message: String) : Exception(message)
