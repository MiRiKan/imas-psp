#ifndef __MIF__H__
#define __MIF__H__

#include <QtGui>
#include "patcher.h"


struct MifFileNode{
	int index;
	int x,y,w,h,a,b;
};

struct MifConversionResult{
	int remapped;
	int skipped;
};

struct MifFile{
	QList<MifFileNode *> nodes;

	MifFile(rwops *rw);

	MifConversionResult read(QImage picture);
	QByteArray spit();


	~MifFile();

	QString issue;
};


#endif // __MIF__H__
