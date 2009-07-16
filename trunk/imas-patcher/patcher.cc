#include "patcher.h"

extern "C" {
#include "lzss.h"
}

char *unpad(char *s,char c){
	char *p=s+strlen(s)-1;

	while(*p==c)
		*p--='\0';

	return s;
}

int rwops::read(void *,size_t){

	return 0;
}
int rwops::write(void *,size_t){

	return 0;
}
void rwops::seek(qint64){

}
qint64 rwops::tell(){
	return 0;
}

char *rwops::slurp(size_t *size){
	size_t blocks=1;
	char *data=new char[blocks*0x800];
	int c;

	while((c=read(data+(blocks-1)*0x800,0x800))!=0){
		if(c!=0x800) break;

		char *data2=new char[(++blocks)*0x800];
		memcpy(data2,data,(blocks-1)*0x800);
		delete[] data;

		data=data2;
	}

	if(size) *size=(blocks-1)*0x800+c;
	return data;
}
qint64 rwops::size(){
	qint64 p=tell();

	seek(((qint64)1)<<63);
	qint64 res=tell();
	seek(p);

	return res;
}
rwops *rwops::clone(){
	return new rwops();
}
rwops::~rwops(){

}


QString rwops::readline(){
	QByteArray a;
	char c;

	if(tell()==0) lineno=0;

	while(read(&c,1)!=0 && c!='\n')
		a.append(c);

	a.append('\n');

	lineno++;
	return QString::fromUtf8(a);
}

int rwops::line(){
	return lineno;
}

rwfile::rwfile(const QString & f)
		:file(f),filename(f){
	if(!file.open(QIODevice::ReadWrite))
		issue=QString("%1 - %2").arg(filename).arg(file.errorString());

	lineno=0;
}

int rwfile::read(void *data,size_t count){
	lineno=0;
	return file.read((char *)data,count);
}
int rwfile::write(void *data,size_t count){
	lineno=0;
	return file.write((char *)data,count);
}
void rwfile::seek(qint64 loc){
	lineno=0;
	file.seek(loc);
}
qint64 rwfile::tell(){
	return file.pos();
}
rwops *rwfile::clone(){
	return new rwfile(filename);
}
QString rwfile::readline(){
	if(file.atEnd())
		return NULL;

	QByteArray arr=file.readLine();

	lineno++;
	return QString::fromUtf8(arr.data(),arr.size());
}
int rwfile::line(){
	return lineno;
}

rwbound::rwbound(rwops *orig,qint64 sstart,qint64 ssize)
		:file(orig->clone()), start(sstart), size(ssize), pos(sstart){
	file->seek(pos);
}

int rwbound::read(void *data,size_t count){
	if(pos+count>start+size)
		count=start+size-pos;

	count=file->read(data,count);
	pos+=count;
	return count;
}
int rwbound::write(void *data,size_t count){
	if(pos+count>start+size)
		count=start+size-pos;

	count=file->write(data,count);
	pos+=count;
	return count;
}
void rwbound::seek(qint64 loc){
	loc=loc<0?start+size-loc:start+loc;

	if(loc<start) loc=start;
	if(loc>start+size) loc=start+size;

	pos=loc;
	file->seek(loc);
}
qint64 rwbound::tell(){
	return pos;
}

rwops *rwbound::clone(){
	return new rwbound(file,start,size);
}
int rwbound::line(){
	return file->line();
}
rwbound::~rwbound(){
	delete file;
}

int rwmemfile::read(void *data,size_t count){
	if(pos+count>size) count=size-pos;

	memcpy(data,dd+pos,count);
	pos+=count;

	return count;
}
int rwmemfile::write(void *data,size_t count){
	if(pos+count>size) count=size-pos;

	memcpy(dd+pos,data,count);
	pos+=count;

	return count;
}
void rwmemfile::seek(qint64 loc){
	pos=loc;
	if(pos>size) pos=size;
}
qint64 rwmemfile::tell(){
	return pos;
}

rwops *rwmemfile::clone(){
	return new rwmemfile(dd,size);
}

rwmemfile::rwmemfile(void *data,qint64 insize){
	dd=new char[size=insize];
	memcpy(dd,data,size);
	pos=0;
}
rwmemfile::~rwmemfile(){
	delete dd;
}

void Yum::spit(char *in,size_t insize){
	quint32 v[4];

	rw->seek(entryloc);
	rw->read((char *)v,sizeof(v));

	quint32
			start			= v[0],
			uncompressed	= v[2],
			next			= v[3];

	char *data=in;
	quint32 datasize=insize;

	if(uncompressed){
		data=new char[insize*2];

		datasize=lzss_encode(in,insize,data,insize*2);
		v[2]=insize;
	}

	if(datasize>next-start){
		issue=QString("not enough space; short by %1 bytes: need %2 have %3")
			  .arg(datasize-(next-start))
			  .arg(datasize)
			  .arg(next-start);
		return;
	}
	v[1]=datasize;

	rw->seek(start);
	rw->write(data,datasize);

	rw->seek(entryloc);
	rw->write((char *)v,sizeof(quint32)*3);
}


rwmemfile *Yum::torw(){
	char *data;
	quint32 count=slurp(&data);

	rwmemfile *f=new rwmemfile(data,count);

	delete[] data;

	return f;
}

QByteArray Yum::slurp(){
	char *data;
	quint32 count=slurp(&data);

	QByteArray res(data,count);

	delete[] data;

	return res;
}
quint32 Yum::slurp(char **out){
	quint32 v[3];

	rw->seek(entryloc);
	rw->read((char *)v,sizeof(v));

	quint32
			start			= v[0],
			size			= v[1],
			uncompressed	= v[2];

	char *data=new char[size];
	rw->seek(start);
	rw->read(data,size);

	if(uncompressed){
		char *data2=new char[uncompressed];

		lzss_decode(data,size,data2,uncompressed);

		delete[] data;

		*out=data2;
		return uncompressed;
	} else{
		*out=data;
		return size;
	}
}

Yum::Yum(rwops *orig,int no)
		:rw(orig){
	char data[0x20];
	rw->seek(0);
	rw->read(data,sizeof(data));

	if(memcmp(data,"YUM\0\0\0\0\0",8)){
		issue="Not a YUM file";
		return;
	}

	quint32 packs=*(quint32 *)(data+8);
	entryloc=0x20+packs*0x10+no*0x0c;

	quint32 v[3];

	rw->seek(entryloc);
	rw->read((char *)v,sizeof(v));

	size			= v[1];
	uncompressed	= v[2];
}

void Iso::readdirent(int location,const QString & path){
	int pos=0x0800*location;

	while(1){
		file.seek(pos);
		quint8 size;
		file.read((char *)&size,sizeof(size));
		if(size==0) return;

		file.seek(pos+2);
		quint32 loc;
		file.read((char *)&loc,sizeof(loc));

		file.seek(pos+10);
		quint32 esize;
		file.read((char *)&esize,sizeof(esize));

		file.seek(pos+25);
		quint8 type;
		file.read((char *)&type,sizeof(type));

		file.seek(pos+32);
		quint8 slen;
		file.read((char *)&slen,sizeof(slen));

		char s[0x100];
		file.read(s,slen);
		s[slen]='\0';

		pos+=size;

		if(s[0]<0x20) continue;

		QString thispath=QString("%1/%2").arg(path).arg(s).toUpper();


		if(type&2) readdirent(loc,thispath);
		else       entries[thispath]=new IsoEntry(loc,esize);
	//	QMessageBox::about(NULL,"",thispath);
	}
}

rwops *Iso::open(const QString & path){
	if(!parsed)
		readdirent(rootloc,""),parsed=true;

	IsoEntry *p=entries.value(path,NULL);
	if(p==NULL){
		issue=QString("No such file inside ISO - %1").arg(path);
		return NULL;
	}

	issue="";
	return new rwbound(&file,p->block*0x800,p->size);
}

Iso::Iso(const QString & path) :file(path){
	parsed=false;

	if(!file.issue.isEmpty()){
		issue=file.issue;
		return;
	}

	file.seek(0x8000);
	char data[9]={0};

	file.read(data,8);

	if(strcmp(data,"\1CD001\1")){
		issue=QString("Not a proper ISO file - %1").arg(path);
		return;
	}

	file.seek(0x8028);
	char volumeid[0x21]={0};
	file.read(volumeid,0x20);

	volume=QString::fromUtf8(unpad(volumeid,' '));

	file.seek(0x809e);
	if(sizeof(rootloc)!=file.read((char *)&rootloc,sizeof(rootloc))){
		issue=QString("%1 - %2").arg(path).arg(file.issue);
		return;
	}
}

Iso::~Iso(){
	QHashIterator<QString,IsoEntry *> i(entries);
	while(i.hasNext()){
		i.next();
		delete i.value();
	}
}

