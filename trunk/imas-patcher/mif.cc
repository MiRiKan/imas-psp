#include "mif.h"

MifFile::MifFile(rwops *rw){
	QString line;

	line=rw->readline();

	QRegExp first("(//)?MIF\\s*(\\d+)\\s*");
	QRegExp lines("^\\{\\s*(\\d+),\\s*(\\d+),\\s*(\\d+),\\s*(\\d+),\\s*(\\d+),\\s*(\\d+)\\},\\s*");

	ASSUME(first.exactMatch(line),"not a proper MIF file");

	int count=first.cap(2).toInt();

	for(int i=0;i<count;i++){
		line=rw->readline();
		ASSUME(lines.indexIn(line)!=-1,QString("line %1: couldn't parse").arg(rw->line()));

		MifFileNode *node=new MifFileNode;
		node->x=lines.cap(1).toInt();
		node->y=lines.cap(2).toInt();
		node->w=lines.cap(3).toInt();
		node->h=lines.cap(4).toInt();
		node->a=lines.cap(5).toInt();
		node->b=lines.cap(6).toInt();
		node->index=i;

		nodes.append(node);
	}

error:
	return;
}

QByteArray MifFile::spit(){
	QByteArray res;
	QByteArray dd;

	dd=QString("MIF%1\n").arg(nodes.count(),5).toAscii();
	res+=dd;

	for(int i=0;i<nodes.count();i++){
		MifFileNode *node=nodes.at(i);

		dd=QString("{%1,%2,%3,%4,%5,%6},\n")
			 .arg(node->x,4).arg(node->y,4).arg(node->w,4)
			 .arg(node->h,4).arg(node->a,4).arg(node->b,4)
			 .toAscii();
		res+=dd;
	}

	return res;
}

static quint32 colors_array[]={
#include "mif-colors.c.inc"
};
static QHash<quint32,int> colors;

static bool mifSortBySize(const MifFileNode *a,const MifFileNode *b){
	int sd=a->w*a->h-b->w*b->h;
	if(sd!=0) return sd<0;

	return a->index<b->index;
}

MifConversionResult MifFile::read(QImage picture){
	QList<MifFileNode *> remap=nodes;
	qSort(remap.begin(),remap.end(),mifSortBySize);
	QHash<quint64,MifFileNode *> map,aliases;
	int i;

	MifConversionResult res={0,0};

	QList<MifFileNode *> new_nodes;

	if(colors.isEmpty()){
		for(uint i=0;i<sizeof(colors_array)/sizeof(colors_array[0]);i++){
			colors.insert(colors_array[i],i);
		}
	}

	for(i=0;i<nodes.count();i++){
		MifFileNode *node=nodes.at(i);

		MifFileNode *new_node=new MifFileNode;
		new_node->x=new_node->y=0x7fffffff;
		new_node->w=new_node->h=-1;
		new_node->index=node->index;
		new_nodes.append(new_node);
	}

	QImage image=picture.convertToFormat(QImage::Format_ARGB32);

	for(int y=0,h=image.height();y<h;y++){
		uchar *d=image.scanLine(y);
		for(int x=0,w=image.width();x<w;x++){
			if(d[x*4+3]!=0xff) continue;

			quint32 color=*(quint32 *)(d+x*4)&0x00ffffff;

			int index=colors.value(color,-1);

			ASSUME(index!=-1 && index<new_nodes.count(),QString("Unexpected color #%1 at (%2,%3)")
				   .arg(color,8,16,QChar('0')).arg(x).arg(y));

			MifFileNode *new_node=new_nodes.at(index);
			if(new_node->x>x) new_node->x=x;
			if(new_node->y>y) new_node->y=y;
			if(new_node->w<x) new_node->w=x;
			if(new_node->h<y) new_node->h=y;
		}
	}

	for(i=0;i<nodes.count();i++){
		remap.append(nodes.at(i));
	}
	for(i=0;i<remap.count();i++){
		MifFileNode *node=remap.at(i);
		quint64 key=(((quint64)node->x)<<32)+(node->y);

		if(map.contains(key)){
			aliases.insert(key,map.value(key));
		} else{
			map.insert(key,node);
		}
	}

	for(i=0;i<new_nodes.count();i++){
		MifFileNode *new_node=new_nodes.at(i);
		MifFileNode *node=nodes.at(i);

		quint64 key=(((quint64)node->x)<<32)+(node->y);
		MifFileNode *alias=aliases.value(key);

		if(alias && alias!=node && alias->x!=0x7fffffff){
			node->x=alias->x; node->y=alias->y;
			res.remapped++;
		} else if(new_node->w!=0){
			node->x=new_node->x; node->y=new_node->y;
			node->w=new_node->w-new_node->x+1;
			node->h=new_node->h-new_node->y+1;
		} else{
			res.skipped++;
		}

		delete new_node;
	}

error:
	return res;
}

MifFile::~MifFile(){
	CLEAR_LIST(nodes);
}
