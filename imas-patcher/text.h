#ifndef __TEXT__H__
#define __TEXT__H__

#include <QtGui>

#include "patcher.h"

QByteArray text_encode(const QString & source,QString *issue=NULL);
QByteArray text_encode_control(const QString & source,QString *issue);
QByteArray text_encode_control_length(QString source,int length,QString *issue);

#define SCIPT_GROUP_NONE		0
#define SCIPT_GROUP_TEXT		1
#define SCIPT_GROUP_NAME		2

struct ImasScriptNode{
	unsigned char com;
	QByteArray data;
	QByteArray text;
	int group;
	int line;
};

struct ImasScript{
    QString issue;

	QList<ImasScriptNode *> nodes;

	ImasScript(rwops *rw);

	QByteArray spit();

	~ImasScript(){CLEAR_LIST(nodes);}
};

class ImasScriptText{
public:
	QList<QString> names;
	QList<QString> lines;
	QList<int> linenos;

	QString name(int no);
	QString line(int no);
	int lineno(int no);

	ImasScriptText(rwops *source);

	QString issue;
};

#endif
