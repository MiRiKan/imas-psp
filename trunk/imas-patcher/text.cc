#include "text.h"

#include "doubletile.c.inc"

static QHash<unsigned short,unsigned short> codes_hash;
static QHash<char,unsigned short> replacements_hash;

static unsigned short ucs_to_sjis_table[]={
#include "sjis-table.c.inc"
};

static const char *ucs_names[]={
#include "unicode-names.c.inc"
};

static unsigned short lookup(uint l,uint r){
	if(l>0xff || r>0xff || !codes_hash.contains(l<<8|r))
		return 0;

	unsigned short res=codes_hash.value(l<<8|r,0);

	return res;
}

QByteArray text_encode(const QString & source,QString *issue){
	QVector<uint> str=source.toUcs4();

	if(codes_hash.isEmpty()){
		unsigned int i;

		for(i=0;i<sizeof(codes)/sizeof(codes[0]);i++){
			codes_hash.insert(codes[i].sym[0]<<8|codes[i].sym[1],codes[i].code);
		}
		for(i=0;i<sizeof(replacements)/sizeof(replacements[0]);i++){
			replacements_hash.insert(replacements[i].sym,replacements[i].code);
		}
	}

	int pos=0;
	QVector<uint> res;

	int return_point=0;
	int insert_point=0;
	QVector<uint> return_res;

	while(pos<str.size()){
		uint ll=pos==0?' ':str[pos-1];
		uint l=str[pos];
		uint r=pos==str.size()-1?' ':str[pos+1];

		unsigned short sjis;
		if(l<=0xffff && (sjis=ucs_to_sjis_table[l])!=0x0000){
			res.append(sjis);
			pos++;
			continue;
		}

		if(pos>1 && !lookup(ll,l)) return_point=-1;

		if(l==' '){
			return_point=insert_point=pos;
			return_res=res;
		} else if(r==' '){
			return_point=pos;
			insert_point=pos+1;
			return_res=res;
		}

		uint code;
		if((code=lookup(l,r))!=0){
			res.append(code);
			pos+=2;
		} else{
			uint rr=pos>=str.size()-2?' ':str[pos+2];

			if(pos>1 && return_point!=-1 && return_point!=pos && ((code=lookup(r,rr))!=0)){
				pos=return_point;
				res=return_res;
				str.insert(insert_point,' ');
				continue;
			}

			pos++;
			return_point=-1;

			if((code=replacements_hash.value(l))==0){
				if(issue) *issue=QString("Unexpected character: %1 (U+%2, %3)").arg(QChar(l)).arg(l,4,16,(QChar)'0').arg(l<=0xffff?ucs_names[l]:"NONAME");
				return NULL;
			}

			res.append(code);
		}
	}

	char *p=new char[res.size()*2],*pp=p;

	for(int i=0,s=res.size();i<s;i++){
		uint v=res[i];
		*p++=(v>>8)&0xff,*p++=(v>>0)&0xff;
	}

	QByteArray aa(pp,p-pp);
	delete[] pp;

	if(issue) *issue="";

	if(aa.length()%2!=0){
		if(issue) *issue="Internal error; length of encoded string is incorrect";
	}

	return aa;
}

QByteArray text_encode_control(const QString & source,QString *issue){
	QByteArray res;
	QRegExp rx("(%\\d*[a-z]|&[a-z]|[^%&]+)");
	int pos=0;

	while((pos=rx.indexIn(source,pos))!=-1){
		QString issue1;
		QChar ch=rx.cap(1).at(0);

		if(ch=='&' || ch=='%')	res.append(rx.cap(1));
		else					res.append(text_encode(rx.cap(1),&issue1));

		if(!issue1.isEmpty()){
			if(issue) *issue=issue1;
			return NULL;
		}

		pos+=rx.matchedLength();
	}

	return res;
}


ImasScript::ImasScript(rwops *rw){
    QString line;
    QRegExp remove_comments("#.*$");

    while(!(line=rw->readline()).isNull()){
        line.remove(remove_comments);
        line=line.trimmed();

        if(line.isEmpty()) continue;

        QStringList tokens=line.split(' ');

		QString com=tokens.at(0);

		ImasScriptNode *node=new ImasScriptNode;
		node->group=SCIPT_GROUP_NONE;
		node->text.clear();
		node->data.clear();

		if(com.mid(0,3)=="com")		node->com=com.mid(3,2).toInt(NULL,16);
		else if(com=="display")		node->com=0x00;
		else if(com=="line2")		node->com=0x01;
		else if(com=="unk02")		node->com=0x02;
		else if(com=="choice1")		node->com=0x04;
		else if(com=="choice2")		node->com=0x05;
		else if(com=="choice3")		node->com=0x06;
		else if(com=="location")	node->com=0x0a;
		else if(com=="line1")		node->com=0x0f;
		else if(com=="name")		node->com=0x10;
		else if(com=="sound")		node->com=0x12;
		else{
			delete node;
			issue=QString("Unknown command: %1").arg(com);
			return;
		}

		for(int i=1;i<tokens.count();i++){
			QString token=tokens.at(i);
			int val;
			bool ok;

			if(val=token.toInt(&ok),ok){
				if(com=="location" || com=="sound"){
					char ww[2]={(val>>8)&0xff,(val>>0)&0xff};
					node->data.append(ww,2);
					if(val==511){
						issue="";
					}
				} else{
					unsigned char qq=val;
					node->data.append((char *)&qq,1);
				}
			} else if(token.mid(0,7)=="<names:" && token.at(token.length()-1)=='>'){
				int no=token.mid(7,token.length()-8).toInt();
				node->group=SCIPT_GROUP_NAME+no-1;
			} else if(token=="<shift>"){
				node->group=SCIPT_GROUP_TEXT;
			} else{
				delete node;
				issue=QString("Unexpected token: %1").arg(token);
				return;
			}
		}

		nodes.append(node);
    }
}

QByteArray ImasScript::spit(){
	QByteArray res;
	int i;

	for(i=0;i<nodes.size();i++){
		ImasScriptNode *node=nodes.at(i);
		if(i==673){
			issue="";
		}

		res.append(0x80);
		res.append(node->com);
		res.append(node->data);
		res.append(node->text);
	}

	return res;
}

ImasScriptText::ImasScriptText(rwops *source){
	QString line;

	QRegExp remove_comments("#.*$");
	QRegExp remove_colons("^[^:]*: ?");

	int state=0;

	while(!(line=source->readline()).isNull()){
		QString trimmed=line.trimmed();
		QChar cc;
		while(line.length() && (cc=line.at(line.length()-1),
				cc=='\r' || cc=='\n')){
			line.chop(1);
		}

		if(trimmed.isEmpty()){
			if(state==1) state=2;
			continue;
		}

		if(state==0 && trimmed!="Names"){
			issue="Script does not start with ``Names''";
			return;
		} else if(state==0){
			state=1;
			continue;
		}

		if(line.at(0)=='!'){
			line.remove(0,1);
		} else{
			line.remove(remove_comments);
			line.remove(remove_colons);

			if(line.isEmpty()) continue;
		}

		if(state==1){
			names.append(line.trimmed());
			continue;
		}

		lines.append(line);
	}
}

QString ImasScriptText::name(int no){
	return names.value(no,"");
}
QString ImasScriptText::line(int no){
	return lines.value(no,"");
}



