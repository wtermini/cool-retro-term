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
import QtQuick 2.2
import QtQuick.Window

import "menus"

QtObject {
    id: appRoot

    property ApplicationSettings appSettings: ApplicationSettings {
        onInitializedSettings: appRoot.createWindow()
    }

    property TimeManager timeManager: TimeManager {
        // Effects animate while any window can be seen; they stop when every
        // window is minimised or hidden.
        enableTimer: appRoot.shownWindowCount > 0
    }

    property SettingsWindow settingsWindow: SettingsWindow {
        visible: false
    }

    property AboutDialog aboutDialog: AboutDialog {
        visible: false
    }

    property Component windowComponent: Component {
        TerminalWindow { }
    }

    property ListModel windowsModel: ListModel { }

    /// Windows that are neither minimised nor hidden.
    property int shownWindowCount: 0

    function updateShownWindowCount() {
        var shown = 0
        for (var i = 0; i < windowsModel.count; i++) {
            var w = windowsModel.get(i).window
            if (w && w.visible && w.visibility !== Window.Minimized && w.visibility !== Window.Hidden)
                shown++
        }
        shownWindowCount = shown
    }

    function createWindow() {
        var window = windowComponent.createObject(null)
        if (!window)
            return

        windowsModel.append({ window: window })
        window.visibilityChanged.connect(updateShownWindowCount)
        window.show()
        window.requestActivate()
        updateShownWindowCount()
    }

    function closeWindow(window) {
        for (var i = 0; i < windowsModel.count; i++) {
            if (windowsModel.get(i).window === window) {
                windowsModel.remove(i)
                break
            }
        }

        window.destroy()
        updateShownWindowCount()

        if (windowsModel.count === 0) {
            appSettings.close()
        }
    }
}
