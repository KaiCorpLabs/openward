package dev.openward.openward

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import java.io.File
import java.lang.ref.WeakReference
import java.security.KeyStore
import java.security.SecureRandom
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * The vault's unlock keys in the Android Keystore, for the Rust core
 * (openward-app `security::android`), which calls the three static methods
 * over JNI. Nothing here is reached from Dart: the key goes back to Rust.
 *
 * Each key is 32 random bytes, encrypted with an AES-256-GCM key that the
 * Keystore makes and never lets out (StrongBox where the phone has it) and
 * kept encrypted in `noBackupFilesDir`, out of backups. With `biometric`
 * the Keystore key asks for a strong biometric on every use
 * (BiometricPrompt with a CryptoObject) and is invalidated when the
 * fingerprints or faces change, as Touch ID's BIOMETRY_CURRENT_SET on macOS.
 * Without it, it is the "Later" key of the device, as the session keyring.
 *
 * Every method answers the 32 bytes, or one byte saying why not:
 * 1 cancelled, 2 unavailable, 3 missing, 4 failed. `remove` answers nothing
 * when it went well.
 */
object VaultKeystore {
    private const val CANCELLED: Byte = 1
    private const val UNAVAILABLE: Byte = 2
    private const val MISSING: Byte = 3
    private const val FAILED: Byte = 4
    private const val KEYSTORE = "AndroidKeyStore"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"

    @Volatile private var activity: WeakReference<FragmentActivity>? = null
    @Volatile private var context: Context? = null

    /** The activity that shows BiometricPrompt, set while it lives. */
    fun attach(a: FragmentActivity) {
        activity = WeakReference(a)
        context = a.applicationContext
    }

    private fun alias(id: String, biometric: Boolean) =
        "openward." + (if (biometric) "unlock." else "device.") + id

    private fun file(alias: String): File? {
        val c = context ?: return null
        val dir = File(c.noBackupFilesDir, "keystore")
        dir.mkdirs()
        return File(dir, "$alias.bin")
    }

    private fun answer(code: Byte) = byteArrayOf(code)

    @JvmStatic
    fun create(id: String, biometric: Boolean): ByteArray {
        if (context == null) return answer(UNAVAILABLE)
        if (biometric && !canAuthenticate()) return answer(UNAVAILABLE)
        val alias = alias(id, biometric)
        return try {
            val key = generate(alias, biometric)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, key)
            val secret = ByteArray(32).also { SecureRandom().nextBytes(it) }
            val done = if (biometric) authenticate(cipher) else Result.success(cipher)
            done.fold(
                onSuccess = { c ->
                    val sealed = c.doFinal(secret)
                    val out = file(alias) ?: return answer(UNAVAILABLE)
                    out.writeBytes(c.iv + sealed)
                    secret
                },
                onFailure = { e ->
                    secret.fill(0)
                    forget(alias)
                    answer(code(e))
                },
            )
        } catch (e: Exception) {
            forget(alias)
            answer(code(e))
        }
    }

    @JvmStatic
    fun read(id: String, biometric: Boolean): ByteArray {
        if (context == null) return answer(UNAVAILABLE)
        val alias = alias(id, biometric)
        return try {
            val sealed = file(alias)?.takeIf { it.exists() }?.readBytes() ?: return answer(MISSING)
            val store = KeyStore.getInstance(KEYSTORE).apply { load(null) }
            val key = store.getKey(alias, null) as? SecretKey ?: return answer(MISSING)
            if (sealed.size < 12 + 16 + 32) return answer(MISSING)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, sealed, 0, 12))
            val done = if (biometric) authenticate(cipher) else Result.success(cipher)
            done.fold(
                onSuccess = { c -> c.doFinal(sealed, 12, sealed.size - 12) },
                onFailure = { e -> answer(code(e)) },
            )
        } catch (e: KeyPermanentlyInvalidatedException) {
            // The fingerprints or faces changed: the key is gone for good.
            forget(alias)
            answer(MISSING)
        } catch (e: Exception) {
            answer(code(e))
        }
    }

    @JvmStatic
    fun remove(id: String, biometric: Boolean): ByteArray {
        if (context == null) return answer(UNAVAILABLE)
        return try {
            forget(alias(id, biometric))
            ByteArray(0)
        } catch (e: Exception) {
            answer(FAILED)
        }
    }

    private fun forget(alias: String) {
        try {
            KeyStore.getInstance(KEYSTORE).apply { load(null) }.deleteEntry(alias)
        } catch (_: Exception) {
        }
        file(alias)?.delete()
    }

    private fun canAuthenticate(): Boolean {
        val c = context ?: return false
        return BiometricManager.from(c).canAuthenticate(BIOMETRIC_STRONG) ==
            BiometricManager.BIOMETRIC_SUCCESS
    }

    private fun generate(alias: String, biometric: Boolean): SecretKey {
        fun spec(strongBox: Boolean): KeyGenParameterSpec {
            val b = KeyGenParameterSpec.Builder(
                alias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
            if (biometric) {
                b.setUserAuthenticationRequired(true)
                b.setInvalidatedByBiometricEnrollment(true)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    // Every use, with a strong biometric.
                    b.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
                } else {
                    @Suppress("DEPRECATION")
                    b.setUserAuthenticationValidityDurationSeconds(-1)
                }
            }
            if (strongBox) b.setIsStrongBoxBacked(true)
            return b.build()
        }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        return try {
            generator.init(spec(strongBox = true))
            generator.generateKey()
        } catch (_: StrongBoxUnavailableException) {
            generator.init(spec(strongBox = false))
            generator.generateKey()
        }
    }

    private class Failure(val code: Byte) : Exception()

    private fun code(e: Throwable): Byte = when (e) {
        is Failure -> e.code
        is KeyPermanentlyInvalidatedException -> MISSING
        else -> FAILED
    }

    /**
     * Shows BiometricPrompt on the main thread and waits for it here: the
     * core calls from one of its own threads, never the main one.
     */
    private fun authenticate(cipher: Cipher): Result<Cipher> {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            return Result.failure(Failure(FAILED))
        }
        val a = activity?.get() ?: return Result.failure(Failure(UNAVAILABLE))
        val done = CountDownLatch(1)
        var result: Result<Cipher> = Result.failure(Failure(CANCELLED))
        Handler(Looper.getMainLooper()).post {
            val prompt = BiometricPrompt(
                a,
                ContextCompat.getMainExecutor(a),
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(r: BiometricPrompt.AuthenticationResult) {
                        val c = r.cryptoObject?.cipher
                        result = if (c != null) Result.success(c) else Result.failure(Failure(FAILED))
                        done.countDown()
                    }

                    override fun onAuthenticationError(code: Int, message: CharSequence) {
                        result = Result.failure(
                            Failure(
                                when (code) {
                                    BiometricPrompt.ERROR_USER_CANCELED,
                                    BiometricPrompt.ERROR_NEGATIVE_BUTTON,
                                    BiometricPrompt.ERROR_CANCELED,
                                    BiometricPrompt.ERROR_TIMEOUT -> CANCELLED
                                    BiometricPrompt.ERROR_NO_BIOMETRICS,
                                    BiometricPrompt.ERROR_HW_NOT_PRESENT,
                                    BiometricPrompt.ERROR_HW_UNAVAILABLE,
                                    BiometricPrompt.ERROR_LOCKOUT,
                                    BiometricPrompt.ERROR_LOCKOUT_PERMANENT -> UNAVAILABLE
                                    else -> FAILED
                                },
                            ),
                        )
                        done.countDown()
                    }
                },
            )
            val info = BiometricPrompt.PromptInfo.Builder()
                .setTitle(a.getString(R.string.unlock_title))
                .setSubtitle(a.getString(R.string.unlock_subtitle))
                .setNegativeButtonText(a.getString(R.string.unlock_password))
                .setAllowedAuthenticators(BIOMETRIC_STRONG)
                .build()
            try {
                prompt.authenticate(info, BiometricPrompt.CryptoObject(cipher))
            } catch (e: Exception) {
                result = Result.failure(Failure(FAILED))
                done.countDown()
            }
        }
        // Not forever: a prompt left open does not hold the core's thread.
        if (!done.await(3, TimeUnit.MINUTES)) return Result.failure(Failure(CANCELLED))
        return result
    }
}
