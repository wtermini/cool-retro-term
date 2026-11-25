TEMPLATE = subdirs

# Apply this project's patches to the qmltermwidget submodule (see
# patches/README.md). Each patch is applied once; already applied ones are
# skipped, so running qmake again is safe.
QMLTERMWIDGET_PATCHES = $$files($$PWD/patches/qmltermwidget-*.patch)
for(patch, QMLTERMWIDGET_PATCHES) {
    !system(git -C $$PWD/qmltermwidget apply --reverse --check $$patch > /dev/null 2>&1) {
        !system(git -C $$PWD/qmltermwidget apply $$patch) {
            error("Could not apply $$patch to qmltermwidget")
        }
        message("Applied $$patch")
    }
}

CONFIG += ordered

SUBDIRS += qmltermwidget
SUBDIRS += app

desktop.files += cool-retro-term.desktop
desktop.path += /usr/share/applications

INSTALLS += desktop
