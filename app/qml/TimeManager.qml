/*******************************************************************************
* Copyright (c) 2013-2021 "Filippo Scognamiglio"
* https://github.com/Swordfish90/cool-retro-term
*
* This file is part of cool-retro-term.
*
* cool-retro-term is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program.  If not, see <http://www.gnu.org/licenses/>.
*******************************************************************************/
import QtQuick

// Drives the animated effects (noise, flicker, jitter, sync, glow line).
//
// A plain timer at the effects frame rate (60 fps / frame skip) is used
// rather than a per-frame animation: a running animation makes Qt Quick
// render every display refresh (60 or 120 times a second), even when the
// effects only change 20 times a second. When "pause effects when idle" is
// on, the timer also stops a few seconds after the last output or key press,
// so an idle terminal costs almost nothing; any activity resumes it.
QtObject {
    id: timeManager

    property bool enableTimer: false
    property real time: 0

    property int framesPerUpdate: Math.max(1, appSettings.effectsFrameSkip)

    /// No output or input for a while (only when pausing when idle is on).
    property bool idle: false
    readonly property int idleDelay: 5000

    readonly property real _start: Date.now()

    /// Call on terminal output, key presses and window activation.
    /// When the user last typed or used the mouse (not program output), in
    /// milliseconds since the epoch: office mode's idle orbit uses it.
    property real lastUserInput: Date.now()
    function noteUserInput() {
        lastUserInput = Date.now()
        noteActivity()
    }

    function noteActivity() {
        if (idle)
            idle = false
        idleTimer.restart()
    }

    property var frameTimer: Timer {
        interval: Math.round(1000 * timeManager.framesPerUpdate / 60)
        repeat: true
        running: timeManager.enableTimer && !timeManager.idle
        onTriggered: timeManager.time = (Date.now() - timeManager._start) / 1000
    }

    property var idleTimer: Timer {
        interval: timeManager.idleDelay
        running: timeManager.enableTimer && appSettings.pauseEffectsWhenIdle
        onTriggered: timeManager.idle = true
    }

    property var settingsWatcher: Connections {
        target: appSettings
        function onPauseEffectsWhenIdleChanged() {
            if (!appSettings.pauseEffectsWhenIdle)
                timeManager.idle = false
        }
    }
}
