package com.example.veyra.e2ee

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import org.signal.libsignal.protocol.IdentityKeyPair
import org.signal.libsignal.protocol.SessionBuilder
import org.signal.libsignal.protocol.SessionCipher
import org.signal.libsignal.protocol.SignalProtocolAddress
import org.signal.libsignal.protocol.UntrustedIdentityException
import org.signal.libsignal.protocol.ecc.ECKeyPair
import org.signal.libsignal.protocol.kem.KEMKeyPair
import org.signal.libsignal.protocol.kem.KEMKeyType
import org.signal.libsignal.protocol.message.PreKeySignalMessage
import org.signal.libsignal.protocol.message.SignalMessage
import org.signal.libsignal.protocol.state.KyberPreKeyRecord
import org.signal.libsignal.protocol.state.PreKeyBundle
import org.signal.libsignal.protocol.state.PreKeyRecord
import org.signal.libsignal.protocol.state.SignedPreKeyRecord
import org.signal.libsignal.protocol.state.impl.InMemorySignalProtocolStore
import org.signal.libsignal.protocol.util.KeyHelper

class LibSignalProtocolTest {
    @Test
    fun firstOfflineMessageAndBidirectionalReplyDecrypt() {
        val alice = endpoint("alice")
        val bob = endpoint("bob")
        alice.establish(bob)

        val first = alice.cipherFor(bob).encrypt("Hello Bob".encodeToByteArray())
        val opened = bob.cipherFor(alice).decrypt(PreKeySignalMessage(first.serialize()))
        assertArrayEquals("Hello Bob".encodeToByteArray(), opened)

        val reply = bob.cipherFor(alice).encrypt("Hello Alice".encodeToByteArray())
        val replyOpened = alice.cipherFor(bob).decrypt(SignalMessage(reply.serialize()))
        assertArrayEquals("Hello Alice".encodeToByteArray(), replyOpened)
    }

    @Test
    fun tamperingWrongRecipientDuplicateAndOutOfOrderFailSafely() {
        val alice = endpoint("alice")
        val bob = endpoint("bob")
        val charlie = endpoint("charlie")
        alice.establish(bob)
        val first = alice.cipherFor(bob).encrypt("first".encodeToByteArray())

        assertThrows(Exception::class.java) {
            charlie.cipherFor(alice).decrypt(PreKeySignalMessage(first.serialize()))
        }
        val serialized = first.serialize()
        serialized[serialized.lastIndex] = (serialized.last().toInt() xor 1).toByte()
        assertThrows(Exception::class.java) {
            bob.cipherFor(alice).decrypt(PreKeySignalMessage(serialized))
        }

        val valid = alice.cipherFor(bob).encrypt("valid".encodeToByteArray())
        assertArrayEquals(
            "valid".encodeToByteArray(),
            bob.cipherFor(alice).decrypt(PreKeySignalMessage(valid.serialize())),
        )
        assertThrows(Exception::class.java) {
            bob.cipherFor(alice).decrypt(PreKeySignalMessage(valid.serialize()))
        }

        val reply = bob.cipherFor(alice).encrypt("reply".encodeToByteArray())
        assertArrayEquals(
            "reply".encodeToByteArray(),
            alice.cipherFor(bob).decrypt(SignalMessage(reply.serialize())),
        )

        val a = alice.cipherFor(bob).encrypt("A".encodeToByteArray())
        val b = alice.cipherFor(bob).encrypt("B".encodeToByteArray())
        val c = alice.cipherFor(bob).encrypt("C".encodeToByteArray())
        assertArrayEquals("A".encodeToByteArray(), bob.decryptSignal(alice, a.serialize()))
        assertArrayEquals("C".encodeToByteArray(), bob.decryptSignal(alice, c.serialize()))
        assertArrayEquals("B".encodeToByteArray(), bob.decryptSignal(alice, b.serialize()))
    }

    @Test
    fun identityChangeIsRejected() {
        val alice = endpoint("alice")
        val bob = endpoint("bob")
        alice.establish(bob)
        val resetBob = endpoint("bob")
        assertThrows(UntrustedIdentityException::class.java) {
            alice.establish(resetBob)
        }
    }

    private fun endpoint(name: String): Endpoint {
        val identity = IdentityKeyPair.generate()
        val store = InMemorySignalProtocolStore(identity, KeyHelper.generateRegistrationId(false))
        val preKeyPair = ECKeyPair.generate()
        val signedPair = ECKeyPair.generate()
        val signedSignature = identity.privateKey.calculateSignature(signedPair.publicKey.serialize())
        val kyberPair = KEMKeyPair.generate(KEMKeyType.KYBER_1024)
        val kyberSignature = identity.privateKey.calculateSignature(kyberPair.publicKey.serialize())
        store.storePreKey(PRE_KEY_ID, PreKeyRecord(PRE_KEY_ID, preKeyPair))
        store.storeSignedPreKey(
            SIGNED_PRE_KEY_ID,
            SignedPreKeyRecord(SIGNED_PRE_KEY_ID, 1L, signedPair, signedSignature),
        )
        store.storeKyberPreKey(
            KYBER_PRE_KEY_ID,
            KyberPreKeyRecord(KYBER_PRE_KEY_ID, 1L, kyberPair, kyberSignature),
        )
        return Endpoint(
            SignalProtocolAddress(name, 1),
            store,
            PreKeyBundle(
                store.localRegistrationId,
                1,
                PRE_KEY_ID,
                preKeyPair.publicKey,
                SIGNED_PRE_KEY_ID,
                signedPair.publicKey,
                signedSignature,
                identity.publicKey,
                KYBER_PRE_KEY_ID,
                kyberPair.publicKey,
                kyberSignature,
            ),
        )
    }

    private data class Endpoint(
        val address: SignalProtocolAddress,
        val store: InMemorySignalProtocolStore,
        val bundle: PreKeyBundle,
    ) {
        fun establish(remote: Endpoint) {
            SessionBuilder(store, remote.address, address).process(remote.bundle)
        }

        fun cipherFor(remote: Endpoint): SessionCipher =
            SessionCipher(store, address, remote.address)

        fun decryptSignal(remote: Endpoint, serialized: ByteArray): ByteArray =
            cipherFor(remote).decrypt(SignalMessage(serialized))
    }

    companion object {
        private const val PRE_KEY_ID = 1
        private const val SIGNED_PRE_KEY_ID = 2
        private const val KYBER_PRE_KEY_ID = 3
    }
}
