package com.xax.CryptoSavingsTracker.presentation.navigation

import androidx.lifecycle.ViewModel
import com.xax.CryptoSavingsTracker.domain.navigation.NavigationTelemetryTracker
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject

@HiltViewModel
class NavigationRuntimeViewModel @Inject constructor(
    val telemetryTracker: NavigationTelemetryTracker
) : ViewModel()
