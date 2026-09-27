package com.example.veyra.e2ee

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Test
import java.security.SecureRandom
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

class AttachmentCryptoTest {
    private val random = SecureRandom()
    private val aad = "veyra-attachment-v1".toByteArray()

    @Test
    fun uniqueKeysRoundTripAndTamperingFailsClosed() {
        val firstKey = ByteArray(32).also(random::nextBytes)
        val secondKey = ByteArray(32).also(random::nextBytes)
        assertFalse(firstKey.contentEquals(secondKey))
        val nonce = ByteArray(12).also(random::nextBytes)
        val plaintext = "VEYRA_ATTACHMENT_SECRET_847291".toByteArray()
        val ciphertext = crypt(Cipher.ENCRYPT_MODE, firstKey, nonce, plaintext)
        assertArrayEquals(plaintext, crypt(Cipher.DECRYPT_MODE, firstKey, nonce, ciphertext))

        val tampered = ciphertext.copyOf().also { it[it.lastIndex / 2] = (it[it.lastIndex / 2].toInt() xor 1).toByte() }
        assertThrows(AEADBadTagException::class.java) {
            crypt(Cipher.DECRYPT_MODE, firstKey, nonce, tampered)
        }
        assertThrows(AEADBadTagException::class.java) {
            crypt(Cipher.DECRYPT_MODE, secondKey, nonce, ciphertext)
        }
    }

    private fun crypt(mode: Int, key: ByteArray, nonce: ByteArray, input: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(mode, SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce))
        cipher.updateAAD(aad)
        return cipher.doFinal(input)
    }
}
