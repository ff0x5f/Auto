package org.autojs.autojs.ui.snipe

import android.app.Activity
import android.os.Bundle
import android.os.CountDownTimer
import android.text.Editable
import android.text.TextWatcher
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import com.afollestad.materialdialogs.MaterialDialog
import com.google.android.material.floatingactionbutton.FloatingActionButton
import org.autojs.autojs.ui.fragment.BindingDelegates.viewBinding
import org.autojs.autojs.ui.main.ViewPagerFragment
import org.autojs.autojs.util.ClipboardUtils
import org.autojs.autojs.util.ViewUtils.showToast
import org.autojs.autojs6.R
import org.autojs.autojs6.databinding.FragmentSnipeBinding
import java.util.Calendar

class SnipeFragment : ViewPagerFragment(ROTATION_GONE) {

    private val binding by viewBinding(FragmentSnipeBinding::bind)

    private val timeSlotsMinutes = listOf(0, 600, 900, 1200)

    private var session1SlotMinutes: Int = 0
    private var session2SlotMinutes: Int = 0

    private var session1Ready: Boolean = false
    private var session2Ready: Boolean = false

    private var snipeButtonClicked: Boolean = false

    private var countDownTimer: CountDownTimer? = null

    private var clipboardPromptShown: Boolean = false

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        return inflater.inflate(R.layout.fragment_snipe, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        setupInputListeners()
        setupButtonListeners()
        updateUpcomingSessions()
        startCountdown()
        checkClipboard()
    }

    override fun onDestroyView() {
        countDownTimer?.cancel()
        super.onDestroyView()
    }

    override fun onFabClick(fab: FloatingActionButton) {
        // No FAB for this fragment
    }

    override fun onBackPressed(activity: Activity): Boolean {
        return false
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
                activity?.runOnUiThread {
                    val minutes = (millisUntilFinished / 1000L) / 60
                    val seconds = (millisUntilFinished / 1000L) % 60
                    binding.textCountdown.text = String.format("%02d:%02d", minutes, seconds)
                    updateSnipeButtonState(millisUntilFinished)
                }
            }

            override fun onFinish() {
                activity?.runOnUiThread {
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
            statusText.setTextColor(requireContext().getColor(android.R.color.darker_gray))
        } else if (isReady) {
            statusText.setText(R.string.text_snipe_status_ready)
            statusText.setTextColor(requireContext().getColor(android.R.color.holo_green_dark))
        } else {
            statusText.setText(R.string.text_snipe_status_not_ready)
            statusText.setTextColor(requireContext().getColor(android.R.color.darker_gray))
        }

        return isReady
    }

    private fun checkBothReady() {
        val session1Valid = validateSession(1)
        val session2Valid = validateSession(2)

        val activity = activity ?: return
        if (session1Valid && session2Valid) {
            showToast(activity, R.string.text_both_sessions_ready)
        } else {
            val missing = mutableListOf<String>()
            if (!session1Valid) missing.add(getString(R.string.text_snipe_session_1, formatTime(session1SlotMinutes)))
            if (!session2Valid) missing.add(getString(R.string.text_snipe_session_2, formatTime(session2SlotMinutes)))
            showToast(activity, getString(R.string.text_session_not_ready, missing.joinToString(", ")))
        }
    }

    private fun startSnipe() {
        if (snipeButtonClicked) return
        snipeButtonClicked = true

        binding.btnStartSnipe.isEnabled = false
        binding.btnStartSnipe.text = getString(R.string.text_snipe_started)

        binding.etSession1.isEnabled = false
        binding.etSession2.isEnabled = false

        val activity = activity ?: return
        showToast(activity, R.string.text_snipe_initiated)
    }

    private fun checkClipboard() {
        if (clipboardPromptShown) return
        clipboardPromptShown = true

        val activity = activity ?: return
        val clipText = ClipboardUtils.getClip(activity)?.toString()

        if (clipText.isNullOrBlank()) return

        val sessions = listOf(
            getString(R.string.text_snipe_session_1, formatTime(session1SlotMinutes)),
            getString(R.string.text_snipe_session_2, formatTime(session2SlotMinutes))
        )

        val preview = if (clipText.length > 50) clipText.take(50) + "..." else clipText

        MaterialDialog.Builder(activity)
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
}