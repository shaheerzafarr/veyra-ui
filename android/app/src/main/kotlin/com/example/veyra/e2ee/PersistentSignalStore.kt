package com.example.veyra.e2ee

import org.signal.libsignal.protocol.IdentityKey
import org.signal.libsignal.protocol.IdentityKeyPair
import org.signal.libsignal.protocol.InvalidKeyIdException
import org.signal.libsignal.protocol.NoSessionException
import org.signal.libsignal.protocol.ReusedBaseKeyException
import org.signal.libsignal.protocol.SignalProtocolAddress
import org.signal.libsignal.protocol.ecc.ECPublicKey
import org.signal.libsignal.protocol.state.IdentityKeyStore
import org.signal.libsignal.protocol.state.KyberPreKeyRecord
import org.signal.libsignal.protocol.state.KyberPreKeyStore
import org.signal.libsignal.protocol.state.PreKeyRecord
import org.signal.libsignal.protocol.state.PreKeyStore
import org.signal.libsignal.protocol.state.SessionRecord
import org.signal.libsignal.protocol.state.SessionStore
import org.signal.libsignal.protocol.state.SignedPreKeyRecord
import org.signal.libsignal.protocol.state.SignedPreKeyStore
import java.security.MessageDigest

/** Durable synchronous adapters required by libsignal's Java API. */
internal class PersistentSignalStore(
    private val state: KeystoreBackedStateStore,
    private val identityKeyPair: IdentityKeyPair,
    private val registrationId: Int,
    private val signedPreKeyIds: () -> List<Int>,
    private val kyberPreKeyIds: () -> List<Int>,
) : IdentityKeyStore, PreKeyStore, SignedPreKeyStore, KyberPreKeyStore, SessionStore {
    override fun getIdentityKeyPair(): IdentityKeyPair = identityKeyPair

    override fun getLocalRegistrationId(): Int = registrationId

    override fun saveIdentity(
        address: SignalProtocolAddress,
        identityKey: IdentityKey,
    ): IdentityKeyStore.IdentityChange {
        val existing = getIdentity(address)
        return if (existing == null || existing == identityKey) {
            state.write(identityRecord(address), identityKey.serialize())
            IdentityKeyStore.IdentityChange.NEW_OR_UNCHANGED
        } else {
            // Never silently replace a pinned identity. The application must
            // surface the change and require an explicit trust reset.
            IdentityKeyStore.IdentityChange.REPLACED_EXISTING
        }
    }

    override fun isTrustedIdentity(
        address: SignalProtocolAddress,
        identityKey: IdentityKey,
        direction: IdentityKeyStore.Direction,
    ): Boolean {
        val existing = getIdentity(address)
        return existing == null || existing == identityKey
    }

    override fun getIdentity(address: SignalProtocolAddress): IdentityKey? =
        state.read(identityRecord(address))?.useBytes { IdentityKey(it) }

    override fun loadPreKey(preKeyId: Int): PreKeyRecord =
        state.read("prekey_$preKeyId")?.useBytes { PreKeyRecord(it) }
            ?: throw InvalidKeyIdException("Pre-key unavailable")

    override fun storePreKey(preKeyId: Int, record: PreKeyRecord) {
        state.write("prekey_$preKeyId", record.serialize())
    }

    override fun containsPreKey(preKeyId: Int): Boolean = state.has("prekey_$preKeyId")

    override fun removePreKey(preKeyId: Int) {
        state.delete("prekey_$preKeyId")
    }

    override fun loadSignedPreKey(signedPreKeyId: Int): SignedPreKeyRecord =
        state.read("signed_$signedPreKeyId")?.useBytes { SignedPreKeyRecord(it) }
            ?: throw InvalidKeyIdException("Signed pre-key unavailable")

    override fun loadSignedPreKeys(): List<SignedPreKeyRecord> =
        signedPreKeyIds().map(::loadSignedPreKey)

    override fun storeSignedPreKey(signedPreKeyId: Int, record: SignedPreKeyRecord) {
        state.write("signed_$signedPreKeyId", record.serialize())
    }

    override fun containsSignedPreKey(signedPreKeyId: Int): Boolean =
        state.has("signed_$signedPreKeyId")

    override fun removeSignedPreKey(signedPreKeyId: Int) {
        state.delete("signed_$signedPreKeyId")
    }

    override fun loadKyberPreKey(kyberPreKeyId: Int): KyberPreKeyRecord =
        state.read("kyber_$kyberPreKeyId")?.useBytes { KyberPreKeyRecord(it) }
            ?: throw InvalidKeyIdException("Kyber pre-key unavailable")

    override fun loadKyberPreKeys(): List<KyberPreKeyRecord> =
        kyberPreKeyIds().map(::loadKyberPreKey)

    override fun storeKyberPreKey(kyberPreKeyId: Int, record: KyberPreKeyRecord) {
        state.write("kyber_$kyberPreKeyId", record.serialize())
    }

    override fun containsKyberPreKey(kyberPreKeyId: Int): Boolean =
        state.has("kyber_$kyberPreKeyId")

    override fun markKyberPreKeyUsed(
        kyberPreKeyId: Int,
        signedPreKeyId: Int,
        baseKey: ECPublicKey,
    ) {
        val digest = MessageDigest.getInstance("SHA-256").digest(baseKey.serialize())
        val suffix = digest.joinToString("") { "%02x".format(it) }
        digest.fill(0)
        val recordId = "kyber_used_${kyberPreKeyId}_${signedPreKeyId}_$suffix"
        if (state.has(recordId)) throw ReusedBaseKeyException()
        state.write(recordId, byteArrayOf(1))
    }

    override fun loadSession(address: SignalProtocolAddress): SessionRecord? =
        state.read(sessionRecord(address))?.useBytes { SessionRecord(it) }

    override fun loadExistingSessions(
        addresses: List<SignalProtocolAddress>,
    ): List<SessionRecord> = addresses.map { address ->
        loadSession(address) ?: throw NoSessionException(address, "Session unavailable")
    }

    override fun getSubDeviceSessions(name: String): List<Int> = emptyList()

    override fun storeSession(address: SignalProtocolAddress, record: SessionRecord) {
        state.write(sessionRecord(address), record.serialize())
    }

    override fun containsSession(address: SignalProtocolAddress): Boolean =
        state.has(sessionRecord(address))

    override fun deleteSession(address: SignalProtocolAddress) {
        state.delete(sessionRecord(address))
    }

    override fun deleteAllSessions(name: String) {
        // Phase 5C deletes exact immutable device sessions.
    }

    fun isVerified(address: SignalProtocolAddress): Boolean = state.has(verifiedRecord(address))

    fun markVerified(address: SignalProtocolAddress) {
        state.write(verifiedRecord(address), byteArrayOf(1))
    }

    private fun identityRecord(address: SignalProtocolAddress) = "identity_${addressKey(address)}"

    private fun sessionRecord(address: SignalProtocolAddress) = "session_${addressKey(address)}"

    private fun verifiedRecord(address: SignalProtocolAddress) = "verified_${addressKey(address)}"

    private fun addressKey(address: SignalProtocolAddress): String =
        "${address.name}_${address.deviceId}".replace('.', '_')

    private inline fun <T> ByteArray.useBytes(block: (ByteArray) -> T): T =
        try {
            block(this)
        } finally {
            fill(0)
        }
}
