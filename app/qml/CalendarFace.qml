/*******************************************************************************
* Copyright (c) 2026 cool-retro-term contributors
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

/// The wall calendar in the 3D office, drawn into its texture: this month,
/// today circled, days with events marked, and the next few events. Event
/// titles come from the desk (officeDesk), which agents can write, so
/// they're only ever shown as plain text.
Rectangle {
    id: face
    width: 384
    height: 480
    color: "#f4f2ec"


    /// [{date: "YYYY-MM-DD", time, title}], sorted.
    property var events: []
    property date now: new Date()

    // Turn the page at midnight.
    Timer { interval: 60000; running: true; repeat: true; onTriggered: face.now = new Date() }

    readonly property int year: now.getFullYear()
    readonly property int month: now.getMonth()
    readonly property int day: now.getDate()
    readonly property int firstDay: Qt.locale().firstDayOfWeek % 7          // 0 = Sunday
    readonly property int offset: (new Date(year, month, 1).getDay() - firstDay + 7) % 7
    readonly property int daysInMonth: new Date(year, month + 1, 0).getDate()
    readonly property string todayIso: iso(year, month, day)
    readonly property var eventDays: {
        const days = {}
        for (const e of events || [])
            days[e.date] = true
        return days
    }
    readonly property var upcoming: (events || []).filter(e => e.date >= todayIso).slice(0, 3)

    /// The date of the day under a point on the page (u, v from 0 to 1,
    /// from the top left), or "" if it isn't on a day of this month. The same
    /// layout as below (and OfficeDeskArt.calendarDate in Cool Retro Term SE).
    function dateAt(u, v) {
        const x = u * width, y = v * height
        const cellWidth = (width - 32) / 7
        if (x < 16 || x >= width - 16 || y < 226 || y >= 226 + 6 * 28)
            return ""
        const index = Math.floor((y - 226) / 28) * 7 + Math.floor((x - 16) / cellWidth)
        const day = index - offset + 1
        return day >= 1 && day <= daysInMonth ? iso(year, month, day) : ""
    }

    function pad(n) { return (n < 10 ? "0" : "") + n }
    function iso(y, m, d) { return y + "-" + pad(m + 1) + "-" + pad(d) }
    function shortDate(isoDate) {
        const parts = isoDate.split("-")
        const d = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
        return Qt.locale().monthName(d.getMonth(), Locale.ShortFormat) + " " + d.getDate()
    }

    Image {
        x: 16; y: 16
        width: parent.width - 32
        height: 150
        source: "office/calendar-picture.jpg"
        fillMode: Image.PreserveAspectCrop
    }

    Rectangle {
        x: 16; y: 172
        width: parent.width - 32
        height: 30
        color: "#c83c32"
        Text {
            anchors.centerIn: parent
            text: Qt.locale().standaloneMonthName(face.month) + " " + face.year
            textFormat: Text.PlainText
            color: "white"
            font.pixelSize: 20
            font.bold: true
        }
    }

    Repeater {
        model: 7
        Text {
            x: 16 + index * (face.width - 32) / 7
            y: 206
            width: (face.width - 32) / 7
            horizontalAlignment: Text.AlignHCenter
            text: Qt.locale().dayName((face.firstDay + index) % 7, Locale.ShortFormat).slice(0, 2)
            textFormat: Text.PlainText
            font.pixelSize: 13
            font.bold: true
            color: "#6a6660"
        }
    }

    Repeater {
        model: 42
        Item {
            readonly property int dayNumber: index - face.offset + 1
            readonly property bool inMonth: dayNumber >= 1 && dayNumber <= face.daysInMonth
            readonly property string isoDate: inMonth ? face.iso(face.year, face.month, dayNumber) : ""
            x: 16 + (index % 7) * width
            y: 226 + Math.floor(index / 7) * height
            width: (face.width - 32) / 7
            height: 28
            visible: inMonth || index < 35

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                color: "transparent"
                border.color: "#c6c2b8"
            }
            Text {
                anchors.centerIn: parent
                visible: parent.inMonth
                text: parent.dayNumber
                textFormat: Text.PlainText
                font.pixelSize: 15
                color: "#3a3834"
            }
            // Today
            Rectangle {
                visible: parent.inMonth && parent.isoDate === face.todayIso
                anchors.centerIn: parent
                width: 30; height: 24; radius: 12
                color: "transparent"
                border.color: "#d22828"
                border.width: 3
            }
            // A day with events
            Rectangle {
                visible: parent.inMonth && face.eventDays[parent.isoDate] === true
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 2
                width: 18; height: 3
                color: "#2860b4"
            }
        }
    }

    Column {
        x: 18; y: 400
        width: face.width - 36
        spacing: 2
        Repeater {
            model: face.upcoming
            Text {
                width: parent.width
                text: face.shortDate(modelData.date) + (modelData.time ? " " + modelData.time : "") + "  " + modelData.title
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font.pixelSize: 16
                color: "#2b2d6e"
            }
        }
    }
}
