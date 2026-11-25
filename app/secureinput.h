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
#ifndef SECUREINPUT_H
#define SECUREINPUT_H

#include <QObject>

// Secure Keyboard Entry, as in Terminal.app (and Cool Retro Term SE): while
// the app is in front, macOS stops other apps from reading keystrokes, which
// protects passwords typed at prompts. Does nothing on other systems.
class SecureInput : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)

public:
    explicit SecureInput(QObject *parent = nullptr);
    ~SecureInput() override;

    bool enabled() const { return m_enabled; }
    void setEnabled(bool enabled);

signals:
    void enabledChanged();

private:
    void update();

    bool m_enabled = false;
    bool m_active = false;   // whether EnableSecureEventInput() is in effect
};

#endif // SECUREINPUT_H
