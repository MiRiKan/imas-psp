OTHER_FILES += imas-patcher.rc
HEADERS += text.h \
    patcher.h \
    mainwindow.h \
    about.h \
    lzss.h
SOURCES += text.cc \
    patcher.cc \
    mainwindow.cpp \
    about.cpp \
    lzss.c \
    main.cpp
RESOURCES += resource.qrc
FORMS += mainwindow.ui \
    about.ui
RC_FILE=imas-patcher.rc
