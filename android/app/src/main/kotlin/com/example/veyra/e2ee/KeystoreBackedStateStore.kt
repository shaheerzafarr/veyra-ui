package com.example.veyra.e2ee

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Encrypted blob container for future serialized libsignal store records.
 * It does not define or interpret any Signal Protocol serialization.
 */
internal class KeystoreBackedStateStore(context: Context, namespace: String) {
    private val directory =
        File(context.noBackupFilesDir, "e2ee_state/$namespace").apply { mkdirs() }

    fun ensureProtectionKey() {
        protectionKey()
    }

    fun write(recordId: String, plaintext: ByteArray) {
        val file = atomicFile(recordId)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, protectionKey())
        cipher.updateAAD(recordId.toByteArray(Charsets.UTF_8))
        val ciphertext = cipher.doFinal(plaintext)
        val encoded = ByteArrayOutputStream().use { bytes ->
            bytes.write(FORMAT_VERSION)
            bytes.write(cipher.iv.size)
            bytes.write(cipher.iv)
            bytes.write(ciphertext)
            bytes.toByteArray()
        }
        val stream = file.startWrite()
        try {
            stream.write(encoded)
            stream.fd.sync()
            file.finishWrite(stream)
        } catch (error: Exception) {
            file.failWrite(stream)
            throw error
        } finally {
            plaintext.fill(0)
        }
    }

    fun read(recordId: String): ByteArray? {
        val file = atomicFile(recordId)
        if (!file.baseFile.exists()) return null
        return DataInputStream(file.openRead()).use { input ->
            require(input.readUnsignedByte() == FORMAT_VERSION) { "Unsupported state format" }
            val ivSize = input.readUnsignedByte()
            require(ivSize in 12..16) { "Invalid state nonce" }
            val iv = ByteArray(ivSize)
            input.readFully(iv)
            val ciphertext = input.readBytes()
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, protectionKey(), GCMParameterSpec(128, iv))
            cipher.updateAAD(recordId.toByteArray(Charsets.UTF_8))
            cipher.doFinal(ciphertext)
        }
    }

    fun has(recordId: String): Boolean = atomicFile(recordId).baseFile.exists()

    fun delete(recordId: String) {
        atomicFile(recordId).delete()
    }

    private fun atomicFile(recordId: String): AtomicFile {
        require(RECORD_ID.matches(recordId)) { "Invalid secure-state record identifier" }
        return AtomicFile(File(directory, recordId))
    }

    private fun protectionKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .setUserAuthenticationRequired(false)
                .build(),
        )
        return generator.generateKey()
    }

    companion object {
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val KEY_ALIAS = "veyra_e2ee_state_v1"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val FORMAT_VERSION = 1
        private val RECORD_ID = Regex("[A-Za-z0-9_.-]{1,120}")
    }
}
