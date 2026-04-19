package org.autojs.autojs.ui.snipe

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.os.CountDownTimer
import android.text.Editable
import android.text.TextWatcher
import android.view.MenuItem
import com.afollestad.materialdialogs.MaterialDialog
import org.autojs.autojs.ui.BaseActivity
import org.autojs.autojs.ui.main.MainActivity
import org.autojs.autojs.util.ClipboardUtils
import org.autojs.autojs.util.IntentUtils.startSafely
import org.autojs.autojs.util.ViewUtils.showToast
import org.autojs.autojs6.R
import org.autojs.autojs6.databinding.ActivitySnipeBinding
import java.util.Calendar

class SnipeActivity : BaseActivity() {

    private lateinit var binding: ActivitySnipeBinding

    // Time slots in minutes from midnight: 00:00, 10:00, 15:00, 20:00
    private val timeSlotsMinutes = listOf(0, 600, 900, 1200)

    private var session1SlotMinutes: Int = 0
    private var session2SlotMinutes: Int = 0

    private var session1Ready: Boolean = false
    private var session2Ready: Boolean = false

    private var snipeButtonClicked: Boolean = false

    private var countDownTimer: CountDownTimer? = null

    private var clipboardPromptShown: Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivitySnipeBinding.inflate(layoutInflater).also {
            setContentView(it.root)
            setToolbarAsBack(R.string.text_snipe)
        }
        setupToolbarNavigation()
        updateUpcomingSessions()
        setupInputListeners()
        setupButtonListeners()
        startCountdown()
        checkClipboard()
    }

    override fun onDestroy() {
        countDownTimer?.cancel()
        super.onDestroy()
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        return when (item.itemId) {
            android.R.id.home -> {
                navigateToMain()
                true
            }
            else -> super.onOptionsItemSelected(item)
        }
    }

    private fun setupToolbarNavigation() {
        binding.toolbar.setNavigationOnClickListener {
            navigateToMain()
        }
    }

    private fun setupInputListeners() {
        val textWatcher = object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: Editable?) {
                validateSession(1)
                validateSession(2)
            }
        }
        binding.etSession1.addTextChangedListener(textWatcher)
        binding.etSession2.addTextChangedListener(textWatcher)
    }

    private fun setupButtonListeners() {
        binding.btnCheckReady.setOnClickListener { checkBothReady() }
        binding.btnStartSnipe.setOnClickListener { startSnipe() }
        binding.textGoToMain.setOnClickListener { navigateToMain() }
    }

    private fun updateUpcomingSessions() {
        val now = Calendar.getInstance()
        val currentMinutes = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)

        val upcomingSlots = mutableListOf<Int>()

        for (slotMinutes in timeSlotsMinutes) {
            if (slotMinutes > currentMinutes) {
                upcomingSlots.add(slotMinutes)
            }
        }

        if (upcomingSlots.size < 2) {
            for (slotMinutes in timeSlotsMinutes) {
                if (slotMinutes !in upcomingSlots) {
                    upcomingSlots.add(slotMinutes)
                }
                if (upcomingSlots.size >= 2) break
            }
        }

        // Reset snipe button state when sessions change
        snipeButtonClicked = false
        binding.etSession1.isEnabled = true
        binding.etSession2.isEnabled = true
        updateSnipeButtonState(Long.MAX_VALUE)

        if (upcomingSlots.size >= 2) {
            session1SlotMinutes = upcomingSlots[0]
            session2SlotMinutes = upcomingSlots[1]
        } else {
            session1SlotMinutes = timeSlotsMinutes[0]
            session2SlotMinutes = timeSlotsMinutes[1]
        }

        binding.textSession1Time.text = getString(R.string.text_snipe_session_1, formatTime(session1SlotMinutes))
        binding.textSession2Time.text = getString(R.string.text_snipe_session_2, formatTime(session2SlotMinutes))
    }

    private fun formatTime(minutes: Int): String {
        val hours = minutes / 60
        val mins = minutes % 60
        return String.format("%02d:%02d", hours, mins)
    }

    private fun startCountdown() {
        countDownTimer?.cancel()

        val now = Calendar.getInstance()
        val currentSeconds = now.get(Calendar.HOUR_OF_DAY) * 3600 +
                now.get(Calendar.MINUTE) * 60 +
                now.get(Calendar.SECOND)

        val session1Seconds = session1SlotMinutes * 60
        val deltaSeconds = if (session1Seconds > currentSeconds) {
            session1Seconds - currentSeconds
        } else {
            val session2Seconds = session2SlotMinutes * 60
            if (session2Seconds > currentSeconds) {
                session2Seconds - currentSeconds
            } else {
                (24 * 3600 - currentSeconds) + session1Seconds
            }
        }

        val deltaMillis = deltaSeconds * 1000L

        countDownTimer = object : CountDownTimer(deltaMillis, 1000L) {
            override fun onTick(millisUntilFinished: Long) {
                runOnUiThread {
                    val minutes = (millisUntilFinished / 1000L) / 60
                    val seconds = (millisUntilFinished / 1000L) % 60
                    binding.textCountdown.text = String.format("%02d:%02d", minutes, seconds)
                    updateSnipeButtonState(millisUntilFinished)
                }
            }

            override fun onFinish() {
                runOnUiThread {
                    updateUpcomingSessions()
                    startCountdown()
                }
            }
        }.start()
    }

    private fun updateSnipeButtonState(millisUntilSession: Long) {
        val threeMinutesMillis = 3 * 60 * 1000L
        val isWithinWindow = millisUntilSession in 1..threeMinutesMillis
        val canClick = isWithinWindow && !snipeButtonClicked

        binding.btnStartSnipe.isEnabled = canClick

        binding.btnStartSnipe.text = when {
            snipeButtonClicked -> getString(R.string.text_snipe_started)
            else -> getString(R.string.text_start_snipe)
        }
    }

    private fun validateSession(sessionNumber: Int): Boolean {
        val editText = when (sessionNumber) {
            1 -> binding.etSession1
            2 -> binding.etSession2
            else -> return false
        }
        val statusText = when (sessionNumber) {
            1 -> binding.textStatus1
            2 -> binding.textStatus2
            else -> return false
        }

        val text = editText.text.toString().trim()
        val isReady = text.isNotEmpty()

        when (sessionNumber) {
            1 -> session1Ready = isReady
            2 -> session2Ready = isReady
        }

        if (text.isEmpty()) {
            statusText.setText(R.string.text_snipe_status_not_ready)
            statusText.setTextColor(getColor(android.R.color.darker_gray))
        } else if (isReady) {
            statusText.setText(R.string.text_snipe_status_ready)
            statusText.setTextColor(getColor(android.R.color.holo_green_dark))
        } else {
            statusText.setText(R.string.text_snipe_status_not_ready)
            statusText.setTextColor(getColor(android.R.color.darker_gray))
        }

        return isReady
    }

    private fun checkBothReady() {
        val session1Valid = validateSession(1)
        val session2Valid = validateSession(2)

        if (session1Valid && session2Valid) {
            showToast(this, R.string.text_both_sessions_ready)
        } else {
            val missing = mutableListOf<String>()
            if (!session1Valid) missing.add(getString(R.string.text_snipe_session_1, formatTime(session1SlotMinutes)))
            if (!session2Valid) missing.add(getString(R.string.text_snipe_session_2, formatTime(session2SlotMinutes)))
            showToast(this, getString(R.string.text_session_not_ready, missing.joinToString(", ")))
        }
    }

    private fun startSnipe() {
        if (snipeButtonClicked) return
        snipeButtonClicked = true

        binding.btnStartSnipe.isEnabled = false
        binding.btnStartSnipe.text = getString(R.string.text_snipe_started)

        binding.etSession1.isEnabled = false
        binding.etSession2.isEnabled = false

        showToast(this, R.string.text_snipe_initiated)
    }

    private fun checkClipboard() {
        if (clipboardPromptShown) return
        clipboardPromptShown = true

        val clipText = ClipboardUtils.getClip(this)?.toString()

        if (clipText.isNullOrBlank()) return

        val sessions = listOf(
            getString(R.string.text_snipe_session_1, formatTime(session1SlotMinutes)),
            getString(R.string.text_snipe_session_2, formatTime(session2SlotMinutes))
        )

        val preview = if (clipText.length > 50) clipText.take(50) + "..." else clipText

        MaterialDialog.Builder(this)
            .title(R.string.text_clipboard_detected)
            .content(getString(R.string.text_clipboard_prompt_content, preview))
            .items(sessions)
            .itemsCallback { _, _, which, _ ->
                val targetEt = if (which == 0) binding.etSession1 else binding.etSession2
                targetEt.setText(clipText)
            }
            .negativeText(R.string.dialog_button_dismiss)
            .show()
    }

    private fun navigateToMain() {
        MainActivity.launch(this)
        finish()
    }

    companion object {
        @JvmStatic
        fun launch(context: Context) {
            Intent(context, SnipeActivity::class.java).startSafely(context)
        }
    }
}