package org.autojs.autojs.ui.snipe

import android.app.Activity
import android.os.Bundle
import android.os.CountDownTimer
import android.text.Editable
import android.text.TextWatcher
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.animation.Animation
import android.view.animation.ScaleAnimation
import com.afollestad.materialdialogs.MaterialDialog
import com.google.android.material.floatingactionbutton.FloatingActionButton
import org.autojs.autojs.AutoJs
import org.autojs.autojs.execution.ExecutionConfig
import org.autojs.autojs.execution.ScriptExecution
import org.autojs.autojs.execution.ScriptExecutionListener
import org.autojs.autojs.script.JavaScriptFileSource
import org.autojs.autojs.ui.main.ViewPagerFragment
import org.autojs.autojs.util.ClipboardUtils
import org.autojs.autojs.util.ViewUtils.showToast
import org.autojs.autojs6.R
import org.autojs.autojs6.databinding.FragmentSnipeBinding
import java.io.File
import java.util.Calendar

class SnipeFragment : ViewPagerFragment(ROTATION_GONE) {

    private var _binding: FragmentSnipeBinding? = null
    private val binding: FragmentSnipeBinding
        get() = _binding!!

    private val timeSlotsMinutes = listOf(0, 600, 900, 1200)

    private var session1SlotMinutes: Int = 0
    private var session2SlotMinutes: Int = 0

    private var session1Ready: Boolean = false
    private var session2Ready: Boolean = false

    private var snipeButtonClicked: Boolean = false

    private var countDownTimer: CountDownTimer? = null

    private var clipboardPromptShown: Boolean = false

    // Loading state
    private var isLoading: Boolean = false
    private var currentScriptName: String = ""

    // Pulse animation for countdown
    private var pulseAnimation: Animation? = null

    // Script execution listener
    private val scriptExecutionListener = object : ScriptExecutionListener {
        override fun onStart(execution: ScriptExecution) {
            // Script started
        }

        override fun onSuccess(execution: ScriptExecution, result: Any?) {
            activity?.runOnUiThread {
                hideLoading()
                showSuccessDialog()
            }
        }

        override fun onException(execution: ScriptExecution, e: Throwable) {
            activity?.runOnUiThread {
                hideLoading()
                showFailureDialog(e.message ?: "Unknown error")
            }
        }
    }

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentSnipeBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        setupInputListeners()
        setupButtonListeners()
        updateUpcomingSessions()
        startCountdown()
        checkClipboard()
        setupPulseAnimation()
    }

    override fun onDestroyView() {
        countDownTimer?.cancel()
        pulseAnimation?.cancel()
        _binding = null
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

    private fun setupPulseAnimation() {
        pulseAnimation = ScaleAnimation(
            1.0f, 1.1f,
            1.0f, 1.1f,
            Animation.RELATIVE_TO_SELF, 0.5f,
            Animation.RELATIVE_TO_SELF, 0.5f
        ).apply {
            duration = 500
            repeatCount = Animation.INFINITE
            repeatMode = Animation.REVERSE
        }
    }

    private fun updateUpcomingSessions() {
        val ctx = context ?: return
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
        updateSnipeButtonState(binding, Long.MAX_VALUE)

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
                    _binding?.let { b ->
                        val minutes = (millisUntilFinished / 1000L) / 60
                        val seconds = (millisUntilFinished / 1000L) % 60
                        b.textCountdown.text = String.format("%02d:%02d", minutes, seconds)
                        updateSnipeButtonState(b, millisUntilFinished)
                        updateCountdownColor(b, millisUntilFinished)
                    }
                }
            }

            override fun onFinish() {
                activity?.runOnUiThread {
                    _binding?.let {
                        updateUpcomingSessions()
                        startCountdown()
                    }
                }
            }
        }.start()
    }

    private fun updateCountdownColor(b: FragmentSnipeBinding, millisUntilFinished: Long) {
        val seconds = millisUntilFinished / 1000

        val colorRes = when {
            seconds > 60 -> R.color.snipe_countdown_green
            seconds > 15 -> R.color.snipe_countdown_yellow
            else -> R.color.snipe_countdown_red
        }

        b.textCountdown.setTextColor(requireContext().getColor(colorRes))

        // Start or stop pulse animation based on countdown
        if (seconds <= 15 && pulseAnimation != null && b.textCountdown.animation == null) {
            b.textCountdown.startAnimation(pulseAnimation)
        } else if (seconds > 15) {
            b.textCountdown.clearAnimation()
        }
    }

    private fun updateSnipeButtonState(b: FragmentSnipeBinding, millisUntilSession: Long) {
        val threeMinutesMillis = 3 * 60 * 1000L
        val isWithinWindow = millisUntilSession in 1..threeMinutesMillis
        val canClick = isWithinWindow && !snipeButtonClicked

        b.btnStartSnipe.isEnabled = canClick

        b.btnStartSnipe.text = when {
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

        val act = activity ?: return
        if (session1Valid && session2Valid) {
            showToast(act, R.string.text_both_sessions_ready)
            // 执行检查脚本
            runScript(act, "检查.js", isCheckScript = true)
        } else {
            val missing = mutableListOf<String>()
            if (!session1Valid) missing.add(getString(R.string.text_snipe_session_1, formatTime(session1SlotMinutes)))
            if (!session2Valid) missing.add(getString(R.string.text_snipe_session_2, formatTime(session2SlotMinutes)))
            showToast(act, getString(R.string.text_session_not_ready, missing.joinToString(", ")))
        }
    }

    private fun startSnipe() {
        if (snipeButtonClicked) return
        snipeButtonClicked = true

        binding.btnStartSnipe.isEnabled = false
        binding.btnStartSnipe.text = getString(R.string.text_snipe_started)

        binding.etSession1.isEnabled = false
        binding.etSession2.isEnabled = false

        val act = activity ?: return
        showToast(act, R.string.text_snipe_initiated)

        // 保存 Session 内容到文件，供脚本读取
        saveSnipeData(act)
        // 执行抢购脚本
        runScript(act, "抢购.js", isCheckScript = false)
    }

    private fun showLoading(message: String = getString(R.string.text_snipe_executing)) {
        binding.textLoadingMessage.text = message
        binding.loadingOverlay.visibility = View.VISIBLE
        isLoading = true
    }

    private fun hideLoading() {
        binding.loadingOverlay.visibility = View.GONE
        isLoading = false
    }

    private fun showSuccessDialog() {
        val act = activity ?: return
        MaterialDialog.Builder(act)
            .title(R.string.text_snipe_success_title)
            .content(R.string.text_snipe_success_message)
            .positiveIcon(R.drawable.ic_check_mark)
            .positiveText(R.string.dialog_button_confirm)
            .onPositive { dialog, _ ->
                dialog.dismiss()
                resetSnipeState()
            }
            .cancelable(false)
            .show()
    }

    private fun showFailureDialog(errorMessage: String) {
        val act = activity ?: return
        MaterialDialog.Builder(act)
            .title(R.string.text_snipe_failure_title)
            .content(getString(R.string.text_snipe_failure_message, errorMessage))
            .positiveIcon(R.drawable.ic_info)
            .positiveText(R.string.text_snipe_retry)
            .negativeText(R.string.text_snipe_dismiss)
            .onPositive { dialog, _ ->
                dialog.dismiss()
                // Retry
                snipeButtonClicked = false
                binding.btnStartSnipe.isEnabled = true
                binding.btnStartSnipe.text = getString(R.string.text_start_snipe)
            }
            .onNegative { dialog, _ ->
                dialog.dismiss()
                resetSnipeState()
            }
            .cancelable(false)
            .show()
    }

    private fun resetSnipeState() {
        snipeButtonClicked = false
        binding.btnStartSnipe.isEnabled = false
        binding.btnStartSnipe.text = getString(R.string.text_start_snipe)
        binding.etSession1.isEnabled = true
        binding.etSession2.isEnabled = true
    }

    private fun saveSnipeData(context: android.content.Context) {
        try {
            val dir = File(context.filesDir, "snipe")
            dir.mkdirs()
            File(dir, "session1.txt").writeText(binding.etSession1.text.toString())
            File(dir, "session2.txt").writeText(binding.etSession2.text.toString())
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun runScript(context: android.content.Context, scriptName: String, isCheckScript: Boolean = false) {
        try {
            val scriptFile = File(context.filesDir, "sample/测试/$scriptName")
            // 如果文件不存在，从 assets 复制
            if (!scriptFile.exists()) {
                copyAssetScript(context, scriptName, scriptFile)
            }
            currentScriptName = scriptName
            if (!isCheckScript) {
                showLoading()
            }
            val source = JavaScriptFileSource(scriptName, scriptFile)
            val config = ExecutionConfig(workingDirectory = scriptFile.parent)
            AutoJs.getInstance().scriptEngineService.execute(source, scriptExecutionListener, config)
        } catch (e: Exception) {
            e.printStackTrace()
            if (!isCheckScript) {
                hideLoading()
                showFailureDialog(e.message ?: "Unknown error")
            } else {
                showToast(context, "Script error: ${e.message}")
            }
        }
    }

    private fun copyAssetScript(context: android.content.Context, scriptName: String, targetFile: File) {
        try {
            targetFile.parentFile?.mkdirs()
            context.assets.open("sample/测试/$scriptName").use { input ->
                targetFile.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
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