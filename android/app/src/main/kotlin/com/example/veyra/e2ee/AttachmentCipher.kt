package com.example.veyra.e2ee

import android.content.Context
import android.util.Base64
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.UUID
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/** Streaming AES-256-GCM for attachment bytes; the libsignal ratchet only carries its key. */
internal class AttachmentCipher(private val context: Context) {
    private val random = SecureRandom()

    fun encrypt(inputPath: String): Map<String, Any> {
        val input = File(inputPath)
        if (!input.isFile) throw EngineFailure("ATTACHMENT_FILE_MISSING", "Attachment file is unavailable")
        val key = ByteArray(KEY_BYTES).also(random::nextBytes)
        val nonce = ByteArray(NONCE_BYTES).also(random::nextBytes)
        val output = privateFile("encrypted", ".ciphertext")
        return try {
            val cipher = Cipher.getInstance(ALGORITHM)
            cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_BITS, nonce))
            cipher.updateAAD(AAD)
            transform(input, output, cipher)
            mapOf(
                "version" to 1,
                "algorithm" to "AES-256-GCM",
                "key" to encoded(key),
                "nonce" to encoded(nonce),
                "ciphertextPath" to output.absolutePath,
                "plaintextSize" to input.length(),
                "encryptedSize" to output.length(),
                "ciphertextSha256" to sha256(output),
            )
        } catch (error: Exception) {
            output.delete()
            throw EngineFailure("ATTACHMENT_ENCRYPTION_FAILED", "Attachment encryption failed")
        } finally {
            key.fill(0)
            nonce.fill(0)
        }
    }

    fun decrypt(ciphertextPath: String, keyValue: String, nonceValue: String): Map<String, Any> {
        val input = File(ciphertextPath)
        if (!input.isFile) throw EngineFailure("ATTACHMENT_FILE_MISSING", "Encrypted attachment is unavailable")
        val key = decoded(keyValue, KEY_BYTES)
        val nonce = decoded(nonceValue, NONCE_BYTES)
        val pending = privateFile("decrypting", ".pending")
        val finalFile = privateFile("received", ".bin", create = false)
        return try {
            val cipher = Cipher.getInstance(ALGORITHM)
            cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_BITS, nonce))
            cipher.updateAAD(AAD)
            transform(input, pending, cipher)
            if (!pending.renameTo(finalFile)) throw IllegalStateException("Atomic persistence failed")
            mapOf("plaintextPath" to finalFile.absolutePath, "plaintextSize" to finalFile.length())
        } catch (_: AEADBadTagException) {
            pending.delete()
            finalFile.delete()
            throw EngineFailure("ATTACHMENT_AUTHENTICATION_FAILED", "Attachment authentication failed")
        } catch (error: EngineFailure) {
            throw error
        } catch (_: Exception) {
            pending.delete()
            finalFile.delete()
            throw EngineFailure("ATTACHMENT_DECRYPTION_FAILED", "Attachment decryption failed")
        } finally {
            key.fill(0)
            nonce.fill(0)
        }
    }

    fun deletePrivateFile(path: String): Boolean {
        val file = File(path).canonicalFile
        val roots = listOf(context.cacheDir.canonicalFile, context.filesDir.canonicalFile)
        if (roots.none { file.path.startsWith(it.path + File.separator) }) {
            throw EngineFailure("ATTACHMENT_FILE_INVALID", "Attachment path is outside private storage")
        }
        return !file.exists() || file.delete()
    }

    fun cleanupAbandonedFiles(retainedPaths: List<String>, olderThanEpochMs: Long): Int {
        val directory = File(context.filesDir, "attachments").canonicalFile
        val retained = retainedPaths.mapNotNull {
            try { File(it).canonicalPath } catch (_: Exception) { null }
        }.toSet()
        var deleted = 0
        directory.listFiles()?.forEach { file ->
            if (file.isFile && file.canonicalPath !in retained && file.lastModified() < olderThanEpochMs) {
                if (file.delete()) deleted++
            }
        }
        return deleted
    }

    private fun transform(input: File, output: File, cipher: Cipher) {
        FileInputStream(input).use { source ->
            FileOutputStream(output).use { sink ->
                val buffer = ByteArray(BUFFER_BYTES)
                while (true) {
                    val count = source.read(buffer)
                    if (count < 0) break
                    cipher.update(buffer, 0, count)?.let(sink::write)
                }
                cipher.doFinal()?.let(sink::write)
                sink.fd.sync()
                buffer.fill(0)
            }
        }
    }

    private fun privateFile(prefix: String, suffix: String, create: Boolean = true): File {
        val directory = File(context.filesDir, "attachments").apply { mkdirs() }
        val file = File(directory, "$prefix-${UUID.randomUUID()}$suffix")
        if (create) file.createNewFile()
        return file
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).use { input ->
            val buffer = ByteArray(BUFFER_BYTES)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return encoded(digest.digest())
    }

    private fun encoded(value: ByteArray): String = Base64.encodeToString(value, Base64.NO_WRAP)

    private fun decoded(value: String, expected: Int): ByteArray = try {
        Base64.decode(value, Base64.NO_WRAP).also {
            if (it.size != expected) throw IllegalArgumentException()
        }
    } catch (_: Exception) {
        throw EngineFailure("ATTACHMENT_KEY_INVALID", "Attachment key material is invalid")
    }

    companion object {
        private const val ALGORITHM = "AES/GCM/NoPadding"
        private const val KEY_BYTES = 32
        private const val NONCE_BYTES = 12
        private const val TAG_BITS = 128
        private const val BUFFER_BYTES = 64 * 1024
        private val AAD = "veyra-attachment-v1".toByteArray(Charsets.UTF_8)
    }
}
