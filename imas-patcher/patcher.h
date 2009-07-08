#ifndef PATCHER_H
#define PATCHER_H

#include <QtGui>
#include <stdio.h>

#define DIE(v) do{issue=(v);goto error;}while(0)
#define ASSUME(v,e) if((v)==0) DIE(e)
#define CHECK() if(!issue.isEmpty()) goto error

#define CLEAR_LIST(l) do{while(l.count()) delete l.takeFirst();}while(0)

char *unpad(char *s,char c);

struct IsoEntry{
	quint32 block;
	quint32 size;

	IsoEntry(quint32 b,quint32 s){block=b;size=s;}
};

struct IsoDirent {
	int  a;
	char b;
	int  c;
} __attribute__((__packed__));

class rwops{
public:
	virtual int read(char *data,size_t count);
	virtual int write(char *data,size_t count);
	virtual void seek(qint64 loc);
	virtual rwops *clone();

	virtual QString readline();


	char *slurp(size_t *size);

	QString issue;

	virtual ~rwops();
};

class rwfile :public rwops{
public:
	QFile file;
	QString filename;

	int read(char *data,size_t count);
	int write(char *data,size_t count);
	void seek(qint64 loc);
	rwops *clone();

	QString readline();

	QString issue;

	rwfile(const QString & filename);
};

/*
class rwfile :public rwops{
public:
	FILE *file;
	QString filename;

	int read(char *data,size_t count);
	int write(char *data,size_t count);
	void seek(qint64 loc);
	rwops *clone();

	QString readline();

	QString issue;

	rwfile(const QString & filename);
};
*/

class rwbound :public rwops{
public:
	rwops *file;
	qint64 start,size,pos;

	int read(char *data,size_t count);
	int write(char *data,size_t count);
	void seek(qint64 loc);
	virtual rwops *clone();

	rwbound(rwops *orig,qint64 sstart,qint64 ssize);
	~rwbound();
};

class Yum{
	quint32 entryloc;
	rwops *rw;

public:
	void spit(char *data,size_t size);
	quint32 slurp(char **out);

	QString issue;

	Yum(rwops *orig,int no);
};

class Iso{
	rwfile file;
	QHash<QString,IsoEntry *> entries;
	bool parsed;
	quint32 rootloc;

	void readdirent(int location,const QString & path);

public:
	Iso(const QString & path);
	~Iso();

	rwops *open(const QString & path);

	QString issue;
	QString volume;
};

#endif // PATCHER_H
