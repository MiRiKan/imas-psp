#include "pom.h"


PomFile::PomFile(rwops *a) :rw(a){try{
	char head[4];

	palettes=NULL;
	data=NULL;

	rw->read(head,4);

	TASSUME(memcmp(head,"POM",4)==0,"Not a proper POM file");

	rw->read(&height,4);
	rw->read(&width,4);
	rw->seek(26);
	rw->read(&images,2); images++;
	rw->read(&subs,2);
	rw->seek(32);
	rw->read(&ua,2);
	rw->read(&ub,2); bpp=ub&0x40?4:8;

	int data_size=width*height/(bpp==8?1:2);

	palettes=new unsigned char[images*4*(1<<bpp)];
	data=new unsigned char[data_size];

	rw->seek(64);
	unsigned char *pp=palettes;
	for(int i=0;i<images;i++){
		for(int j=0;j<(1<<bpp);j++){
			rw->read(pp,4);
			pp[3]=pp[3]==0x80?0xff:pp[3]*2;
			pp+=4;
		}
	}

	rw->read(data,data_size);

}catch(QString ss){
}}

QByteArray PomFile::spit(){
	int palettes_size=images*4*(1<<bpp);
	int data_size=width*height/(bpp==8?1:2);
	int names_size=0x10*images;
	QByteArray res(0x40+palettes_size+data_size+names_size,'\0');

	rw->seek(0);
	rw->read(res.data(),0x40+palettes_size);
	memcpy(res.data()+0x40+palettes_size,data,data_size);
	rw->seek(0x40+palettes_size+data_size);
	rw->read(res.data()+0x40+palettes_size+data_size,names_size);

	return res;
}


QImage *PomFile::get(int no){
	if(no>images || no<1){
		issue=QString("picture with number %1 does not exist in this POM").arg(no);
		return NULL;
	}

	int subh=ua==0x3c80?1:8;
	int subw=bpp==8?0x10:0x20;
	int wsubc=width/subw;

	unsigned char *palette=palettes+(no-1)*4*(1<<bpp);

	QImage *image=new QImage(width,height,QImage::Format_ARGB32);
	int index=0;
	for(int hblock=0,hblockend=height/subh;hblock<hblockend;hblock++){
		for(int wblock=0;wblock<wsubc;wblock++){
			for(int line=0;line<subh;line++){
				uchar *pp=image->scanLine(hblock*subh+line)+wblock*subw*4;
				for(int p=0;p<0x10;p++){
					if(bpp==8){
						*pp++=palette[data[index]*4+2];
						*pp++=palette[data[index]*4+1];
						*pp++=palette[data[index]*4+0];
						*pp++=palette[data[index]*4+3];
						index++;
					} else{
						int l= data[index]&0x0f;
						int r=(data[index]&0xf0)>>4;

						*pp++=palette[l*4+2];
						*pp++=palette[l*4+1];
						*pp++=palette[l*4+0];
						*pp++=palette[l*4+3];
						*pp++=palette[r*4+2];
						*pp++=palette[r*4+1];
						*pp++=palette[r*4+0];
						*pp++=palette[r*4+3];
						index++;
					}
				}
			}
		}
	}

	return image;
}

static int findColorMatch(uchar *palette,int size,uchar *color,int *ret_diff){
	int index=0;
	int range=0x7fffffff;

	int r=color[2];
	int g=color[1];
	int b=color[0];
	int a=color[3];

	for(int i=0;i<size;i++){
		uchar *p=palette+i*4;

		int alphadiff=abs(a-p[3]);

		int diff=
			alphadiff*4+
			abs(r*a-p[0]*p[3])*(0xff-alphadiff)/0xff/0xff+
			abs(g*a-p[1]*p[3])*(0xff-alphadiff)/0xff/0xff+
			abs(b*a-p[2]*p[3])*(0xff-alphadiff)/0xff/0xff;

		if(diff<range){
			range=diff;
			index=i;
		}
	}

	if(ret_diff) *ret_diff=range;
	return index;
}

PomConversionResult PomFile::set(int no,QImage *orig){
	if(no>images || no<1){
		issue=QString("picture with number %1 does not exist in this POM").arg(no);
		return PomConversionResult();
	}

	if(orig->width()!=(int)width || orig->height()!=(int)height){
		issue=QString("picture dimensions do not match -- trying to replace %1x%2 with %1x%2")
			  .arg(width)
			  .arg(height)
			  .arg(orig->width())
			  .arg(orig->height());
		return PomConversionResult();
	}

	QImage image=orig->convertToFormat(QImage::Format_ARGB32);

	int subh=ua==0x3c80?1:8;
	int subw=bpp==8?0x10:0x20;
	int wsubc=width/subw;

	PomConversionResult res={0,0};
	qint64 diff_sum=0;

	unsigned char *palette=palettes+(no-1)*4*(1<<bpp);

	int index=0;
	for(int hblock=0,hblockend=height/subh;hblock<hblockend;hblock++){
		for(int wblock=0;wblock<wsubc;wblock++){
			for(int line=0;line<subh;line++){
				uchar *pp=image.scanLine(hblock*subh+line)+wblock*subw*4;
				int diff;

				for(int p=0;p<0x10;p++){
					if(bpp==8){
						data[index++]=findColorMatch(palette,(1<<bpp),pp,&diff);

						if(res.maxDiff<diff) res.maxDiff=diff;
						diff_sum+=diff;

						pp+=4;
					} else{
						int l=findColorMatch(palette,(1<<bpp),pp,&diff); pp+=4;
						if(res.maxDiff<diff) res.maxDiff=diff;
						diff_sum+=diff;

						int r=findColorMatch(palette,(1<<bpp),pp,&diff); pp+=4;
						if(res.maxDiff<diff) res.maxDiff=diff;
						diff_sum+=diff;

						data[index++]=(r<<4)|l;
					}
				}
			}
		}
	}

	res.avgDiff=diff_sum/(width*height);

	return res;
}

PomFile::~PomFile(){
	delete palettes;
	delete data;
}
