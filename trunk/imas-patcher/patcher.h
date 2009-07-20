#ifndef PATCHER_H
#define PATCHER_H

#include <QtGui>

#define DIE(v) do{issue=(v);goto error;}while(0)
#define ASSUME(v,e) if((v)==0) DIE(e)
#define TASSUME(v,e) if((v)==0) do{issue=(e);throw (QString)(e);}while(0)
#define TRY(v) if((v)==0) goto error;
#define CHECK() if(!issue.isEmpty()) goto error
#define TCHECK() if(!issue.isEmpty()) throw(issue)

#define CLEAR_LIST(l) do{while(l.count()) delete l.takeFirst();}while(0)

#define elems(l) ((int)(sizeof(l)/sizeof((l)[0])))

char *unpad(char *s,char c);

struct IsoEntry{
	quint32 block;
	quint32 size;

	IsoEntry(quint32 b,quint32 s){block=b;size=s;}
};

class rwops{
public:
	virtual int read(void *data,size_t count);
	virtual int write(void *data,size_t count);
	virtual void seek(qint64 loc);
	virtual qint64 tell();
	virtual rwops *clone();

	qint64 size();

	virtual QString readline();

	int lineno;
	virtual int line();

	char *slurp(size_t *size);

	QString issue;

	virtual ~rwops();
};

class rwfile :public rwops{
public:
	QFile file;
	QString filename;

	int read(void *data,size_t count);
	int write(void *data,size_t count);
	void seek(qint64 loc);
	qint64 tell();
	rwops *clone();

	QString readline();
	int line();

	QString issue;

	rwfile(const QString & filename);
};

class rwbound :public rwops{
public:
	rwops *file;
	qint64 start,size,pos;

	int read(void *data,size_t count);
	int write(void *data,size_t count);
	void seek(qint64 loc);
	qint64 tell();
	virtual rwops *clone();

	int line();

	rwbound(rwops *orig,qint64 sstart,qint64 ssize);
	~rwbound();
};

class rwmemfile :public rwops{
public:
	char *dd;
	qint64 size,pos;

	int read(void *data,size_t count);
	int write(void *data,size_t count);
	void seek(qint64 loc);
	qint64 tell();
	virtual rwops *clone();

	rwmemfile(void *data,qint64 size);
	~rwmemfile();
};


class Yum{
	quint32 entryloc;
	rwops *rw;

public:
	void spit(char *data,size_t size);
	quint32 size,uncompressed;

	quint32 slurp(char **out);
	QByteArray slurp();
	rwmemfile *torw();

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
