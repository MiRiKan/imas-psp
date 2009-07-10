# -------------------------------------------------
# Project created by QtCreator 2009-07-09T20:47:41
# -------------------------------------------------
TARGET = imas-patcher
TEMPLATE = app
SOURCES += text.cc \
    pom.cc \
    patcher.cc \
    mainwindow.cpp \
    main.cpp \
    lzss.c \
    about.cpp
HEADERS += ui_report.h \
    text.h \
    pom.h \
    patcher.h \
    mainwindow.h \
    lzss.h \
    about.h
OTHER_FILES += imas-patcher.rc
FORMS += mainwindow.ui \
    about.ui
RESOURCES += resource.qrc
