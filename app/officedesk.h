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
#ifndef OFFICEDESK_H
#define OFFICEDESK_H

#include <QFileSystemWatcher>
#include <QJsonObject>
#include <QObject>
#include <QVariant>

#include <functional>

/// The office mode desk: the sticky notes (up to eight) and the wall
/// calendar's events. Stored in office-desk.json in the app's data folder, shared with
/// Cool Retro Term SE (OfficeDesk.swift) and with agents through the MCP
/// server (`cool-retro-term --mcp`). Changes made elsewhere are picked up as
/// soon as the file changes.
///
/// Everything read from the file or from an agent is checked here: note
/// text and event titles are plain text with length limits, dates are
/// YYYY-MM-DD, times HH:MM, and there are caps on the number of notes and
/// events. Each change re-reads the file and saves it under a lock
/// (office-desk.lock), so the apps and agents don't overwrite each other.
///
/// File format (version 2; version 1, with three fixed notes, is read too):
///   {"version": 2,
///    "notes": [{"id": "...", "text": "...", "color": "yellow"}, ...],
///    "events": [{"id": "...", "date": "YYYY-MM-DD", "time": "HH:MM" or "", "title": "..."}, ...]}
class OfficeDesk : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList notes READ notes NOTIFY changed)
    Q_PROPERTY(int maxNotes READ maxNotesValue CONSTANT)
    Q_PROPERTY(QVariantList events READ events NOTIFY changed)
    Q_PROPERTY(QString filePath READ filePath CONSTANT)
    Q_PROPERTY(QString mcpCommand READ mcpCommand CONSTANT)

public:
    static constexpr int maxNoteLength = 280;
    static constexpr int maxTitleLength = 120;
    static constexpr int maxEvents = 500;
    static constexpr int maxNotes = 8;

    explicit OfficeDesk(QObject *parent = nullptr);

    QVariantList notes() const;
    int maxNotesValue() const { return maxNotes; }
    QVariantList events() const;
    QString filePath() const;
    /// The command to register the MCP server with an agent such as Claude Code.
    QString mcpCommand() const;

    /// Changes from the app. Each one is saved straight away.
    /// Returns the new note's id, or "" if there are already maxNotes.
    Q_INVOKABLE QString addNote(const QString &text, const QString &color);
    /// An empty colour keeps the note's colour.
    Q_INVOKABLE bool updateNote(const QString &id, const QString &text, const QString &color);
    Q_INVOKABLE bool removeNote(const QString &id);
    Q_INVOKABLE QString addEvent(const QString &date, const QString &time, const QString &title);
    Q_INVOKABLE bool updateEvent(const QString &id, const QString &date, const QString &time, const QString &title);
    Q_INVOKABLE bool removeEvent(const QString &id);
    /// Puts text on the clipboard (for "Copy MCP Setup Command").
    Q_INVOKABLE void copyToClipboard(const QString &text) const;

    /// Runs the MCP server on stdin/stdout until stdin closes. Returns the
    /// process exit code.
    static int runMcpServer();

signals:
    void changed();

private:
    void load();
    bool save();
    /// Re-reads the file, applies `change` and saves, holding the lock.
    bool modify(const std::function<bool()> &change);
    void watch();
    QJsonObject toJson() const;
    void fromJson(const QJsonObject &json);
    QJsonObject eventToJson(const QVariantMap &event) const;

    QVariantList m_notes;   // {id, text, color}, in the order they're placed
    QVariantList m_events;  // {id, date, time, title}, sorted by date and time
    QFileSystemWatcher m_watcher;
    bool m_saving = false;
};

#endif // OFFICEDESK_H
