#ifndef __POM__H__
#define __POM__H__

#include <QtGui>
#include "patcher.h"

struct PomConversionResult{
	int maxDiff;
	int avgDiff;
};

struct PomFile{
	rwops *rw;

	unsigned char *palettes;
	unsigned char *data;

	quint32 width,height;
	quint16 images,subs;
	quint16 ua,ub;

	int bpp;

	PomFile(rwops *a);
	QByteArray spit();
	~PomFile();

	QImage *get(int no);
	PomConversionResult set(int no,QImage *image);

	QString issue;
};

#endif // __POM__H__
