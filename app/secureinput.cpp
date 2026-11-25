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
#include "secureinput.h"

#include <QGuiApplication>

#if defined(Q_OS_MAC)
#include <Carbon/Carbon.h>
#endif

SecureInput::SecureInput(QObject *parent)
    : QObject(parent)
{
    connect(qApp, &QGuiApplication::applicationStateChanged, this, [this] { update(); });
}

SecureInput::~SecureInput()
{
    m_enabled = false;
    update();
}

void SecureInput::setEnabled(bool enabled)
{
    if (m_enabled == enabled)
        return;
    m_enabled = enabled;
    update();
    emit enabledChanged();
}

// Only while the app is frontmost, as Terminal.app does. The system keeps a
// count of enable calls, so each enable is paired with exactly one disable.
void SecureInput::update()
{
    const bool shouldBeActive = m_enabled
        && QGuiApplication::applicationState() == Qt::ApplicationActive;
    if (shouldBeActive == m_active)
        return;
#if defined(Q_OS_MAC)
    if (shouldBeActive)
        EnableSecureEventInput();
    else
        DisableSecureEventInput();
#endif
    m_active = shouldBeActive;
}
