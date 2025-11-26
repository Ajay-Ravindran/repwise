package com.example.repwise

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	companion object {
		const val ACTION_START_WORKOUT = "com.example.repwise.START_WORKOUT"
		private const val CHANNEL = "com.example.repwise/workout_widget"
	}

	private var methodChannel: MethodChannel? = null
	private var pendingStartWorkoutIntent = false

	override fun onCreate(savedInstanceState: Bundle?) {
		super.onCreate(savedInstanceState)
		if (hasStartWorkoutIntent(intent)) {
			pendingStartWorkoutIntent = true
		}
	}

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
			setMethodCallHandler { call, result ->
				when (call.method) {
					"consumeStartWorkoutIntent" -> {
						result.success(consumePendingStartIntent())
					}
					else -> result.notImplemented()
				}
			}
		}
	}

	override fun onNewIntent(intent: Intent) {
		super.onNewIntent(intent)
		setIntent(intent)
		if (hasStartWorkoutIntent(intent)) {
			pendingStartWorkoutIntent = true
			notifyFlutterStartIntent()
		}
	}

	override fun onResume() {
		super.onResume()
		if (hasStartWorkoutIntent(intent)) {
			pendingStartWorkoutIntent = true
			notifyFlutterStartIntent()
		}
	}

	private fun hasStartWorkoutIntent(intent: Intent?): Boolean {
		return intent?.action == ACTION_START_WORKOUT
	}

	private fun consumePendingStartIntent(): Boolean {
		val shouldStart = pendingStartWorkoutIntent || hasStartWorkoutIntent(intent)
		if (shouldStart) {
			pendingStartWorkoutIntent = false
			clearStartWorkoutAction()
		}
		return shouldStart
	}

	private fun clearStartWorkoutAction() {
		intent?.action = null
	}

	private fun notifyFlutterStartIntent() {
		if (!pendingStartWorkoutIntent) {
			return
		}
		try {
			methodChannel?.invokeMethod("startWorkoutIntent", null)
		} catch (_: Exception) {
			// The Flutter side may not be ready yet; the pending flag ensures the intent is consumed later.
		}
	}
}
