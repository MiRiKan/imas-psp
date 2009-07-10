#include <QtGui>

#include "mainwindow.h"
#include "ui_mainwindow.h"
#include "ui_report.h"
#include "about.h"

#include "patcher.h"
#include "text.h"
#include "pom.h"

extern "C"{
#include "lzss.h"
}

QString filename(const QString & path){
	QByteArray arr=path.toUtf8();
	char *p=arr.data(),*q=p;

	while(*p){
		if(*p=='/') q=p+1;
		p++;
	}

	return QString::fromUtf8(q);
}

QString fileext(const QString & path){
	return path.right(path.length()-path.lastIndexOf('.')-1);
}

int isanumberfile(const QString & name){
	QByteArray arr=name.toUtf8();
	char *p=arr.data(),*q=p;

	while(*p>='0' && *p<='9')
		p++;

	if(*p!='.') return -1;

	*p='\0';

	int res=-1;
	sscanf(q,"%d",&res);

	return res;
}

MainWindow::MainWindow(QWidget *parent)
		:QMainWindow(parent),
		ui(new Ui::MainWindow),
		message(this){
    ui->setupUi(this);
	ui->progressBar->hide();

	thread.window=this;
	QObject::connect(&thread, SIGNAL(Start()), this, SLOT(on_jobs_started()));
	QObject::connect(&thread, SIGNAL(Finish()), this, SLOT(on_jobs_finished()));
	QObject::connect(&thread, SIGNAL(Range(int, int)), ui->progressBar, SLOT(setRange(int, int)));
	QObject::connect(&thread, SIGNAL(Value(int)), ui->progressBar, SLOT(setValue(int)));

	QObject::connect(ui->actionAbout,SIGNAL(triggered()),this,SLOT(about()));
	QObject::connect(ui->actionExit,SIGNAL(triggered()),this,SLOT(close()));

	SETTINGS();
	restoreGeometry(settings.value("main-window-geometry").toByteArray());
	selectIso(settings.value("main-window-iso").toString());

	QStringList items=settings.value("main-window-patch-files").toStringList();
	for(int i=0;i<items.count();i++){
		addFile(items.at(i));
	}
}

MainWindow::~MainWindow(){
	SETTINGS();
	settings.setValue("main-window-geometry",saveGeometry());
	settings.setValue("main-window-iso",isoFilename);

	QStringList items;
	for(int i=0,l=ui->listWidget->count();i<l;i++){
		items.append(ui->listWidget->item(i)->text());
	}

	settings.setValue("main-window-patch-files",items);

    delete ui;
}

void GenericJob::process(){
}

void GenericJob::close(){
	delete file;	file=NULL;
	delete isofile;	isofile=NULL;
}

GenericJob::~GenericJob(){
	close();
}

void IsoFileJob::process(){
	char buff[0x400];
	int count;
	while((count=file->read(buff,sizeof(buff)))!=0){
		ASSUME(isofile->write(buff,count)==count,"Not enough space");
	}

	state=JOB_STATE_OK;
	return;

error:
	state=JOB_STATE_FAILED;
}

void ExecutableLinesJob::process(){
	QString line;
	QRegExp reg("(\\s*[0-9a-fA-F]{8})\\s+(\\d+) ([^\r\n]*)\r?\n?");
	QRegExp remove_comments("\\s*#.*$");
	QString issue;

	int succ=0,noise=0,skipped=0;

	while(!(line=file->readline()).isNull()){
		line.remove(remove_comments);

		if(!reg.exactMatch(line)){
			if(!line.trimmed().isEmpty()){
				output.append(QString("line %1: couldn't parse").arg(file->line()));
				noise++;
			}
			continue;
		}

		ulong address=reg.cap(1).toULong(NULL,16);
		long size=reg.cap(2).toLong(NULL,10);
		QString reline=reg.cap(3);

		QByteArray bytes=text_encode_control(reline,&issue);
		if(!issue.isEmpty()){
			skipped++;
			output.append(QString("line %1: couldn't encode text: %2")
						  .arg(file->line())
						  .arg(issue));
			continue;
		}

		if(bytes.count()>size){
			skipped++;
			output.append(QString("line %5: %1 Can't insert: short by %2 bytes -- have %3 need %4")
						  .arg(address,8,16,QChar('0'))
						  .arg(bytes.count()-size)
						  .arg(size)
						  .arg(bytes.count())
						  .arg(file->line()));
			continue;
		}

		isofile->seek(address);
		isofile->write(bytes.data(),bytes.count());
		for(int i=0,c=size-bytes.size();i<c;i++)
			isofile->write((char *)"",1);

		succ++;
	}

	if(noise==0 && skipped==0){
		if(succ==0)
			output.append(QString("File was empty")),
			state=JOB_STATE_WARNINGS;
		else
			output.append(QString("Successfully inserted %1 lines").arg(succ)),
			state=JOB_STATE_OK;
	} else if(succ!=0){
		state=JOB_STATE_WARNINGS;
	} else{
		state=JOB_STATE_FAILED;
	}
}

void YumFileJob::process(){
	size_t c;
	char *data;

	Yum y(isofile,number);
	ASSUME(y.issue.isEmpty(),y.issue);

	data=file->slurp(&c);
	y.spit(data,c);
	delete[] data;

	ASSUME(y.issue.isEmpty(),y.issue);

	state=JOB_STATE_OK;
	return;

error:
	state=JOB_STATE_FAILED;
}

void YumScriptJob::process(){try{
	rwfile rw(QString("scripts/%1.src").arg(number));
	TASSUME(rw.issue.isEmpty(),rw.issue);

	ImasScript script(&rw);
	TASSUME(script.issue.isEmpty(),QString("scripts/%1.src: %2").arg(number).arg(script.issue));

	ImasScriptText text(file);
	TASSUME(text.issue.isEmpty(),text.issue);

	int lineno=0;
	for(int i=0;i<script.nodes.count();i++){
		QString errstr;
		ImasScriptNode *node=script.nodes.value(i);

		if(node->group==SCIPT_GROUP_TEXT){
			if(text.lines.count()<=lineno){
				issue="Not enough lines in script file you supplied";
				state=JOB_STATE_FAILED;
				return;
			}

			node->text=text_encode(text.line(lineno),&errstr);
			if(!errstr.isEmpty()){
				output.append(QString("line %1: couldn't encode text: %2")
						.arg(text.lineno(lineno))
						.arg(errstr));
			}

			lineno++;
		} else if(node->group>=SCIPT_GROUP_NAME){
			int nameno=node->group-SCIPT_GROUP_NAME;

			if(text.names.count()<nameno){
				issue="Not enough names in script file you supplied";
				state=JOB_STATE_FAILED;
				return;
			}

			node->text=text_encode(text.name(nameno),&errstr);
			if(!errstr.isEmpty()){
				output.append(QString("Couldn't encode name ``%1'': %2")
						.arg(text.name(nameno))
						.arg(errstr));
			}
		}
	}

	if(text.lines.count()!=lineno)
		output.append("Too many lines in script file you supplied");

	QByteArray bytes=script.spit();
	TASSUME(script.issue.isEmpty(),script.issue);

	Yum y(isofile,number);
	TASSUME(y.issue.isEmpty(),y.issue);

	y.spit(bytes.data(),bytes.size());
	TASSUME(y.issue.isEmpty(),y.issue);

	if(output.isEmpty()){
		state=JOB_STATE_OK;
	} else{
		state=JOB_STATE_WARNINGS;
	}
} catch(QString ss){
	state=JOB_STATE_FAILED;
}}

void YumMailJob::process(){try{
	state=JOB_STATE_OK;

	QByteArray bytes;

	QRegExp leaveUntouched("^##");

	QString line;
	while(!(line=file->readline()).isNull()){
		QChar c;
		while(!line.isEmpty() && (c=line.at(line.length()-1),c=='\r' || c=='\n'))
			line.chop(1);

		if(leaveUntouched.indexIn(line)==-1){
			QByteArray arr=line.toAscii();
			bytes.append(arr);
			bytes.append("\r\n",2);
			continue;
		}

		QString errstr;
		QByteArray arr=text_encode_control(line,&errstr);
		if(!errstr.isEmpty()){
			state=JOB_STATE_WARNINGS;
			output+=QString("line %1: could not encode text: %2")
					.arg(file->line())
					.arg(errstr);
		}

		bytes.append(arr);
		bytes.append("\r\n",2);
	}

	Yum y(isofile,number);
	TASSUME(y.issue.isEmpty(),y.issue);

	y.spit(bytes.data(),bytes.size());
	TASSUME(y.issue.isEmpty(),y.issue);

} catch(QString ss){
	state=JOB_STATE_FAILED;
}}


#define SHOW_ORIGINAL_FILE
void YumPomJob::process(){try{
	Yum y(isofile,number);
	TASSUME(y.issue.isEmpty(),y.issue);

	PomFile pom(y.torw());
	TASSUME(pom.issue.isEmpty(),QString("File %1 inside yum archive - %2").arg(number).arg(pom.issue));

	QString picname=QString("%1-%2(%3)")
					.arg(number)
					.arg(subnumber)
					.arg(qrand());

	QImage replacementImage(source);
	TASSUME(!replacementImage.isNull(),"Could not load picture (Is it corrupted?)");

#ifdef SHOW_ORIGINAL_FILE
	ResourceData *resource=new ResourceData();
	resource->data=QVariant(replacementImage);
	resource->type=QTextDocument::ImageResource;
	resource->name=QUrl(QString("imas-pictures://%1-orig.png").arg(picname));
	resources.append(resource);
#else
	QImage *originalImage=pom.get(subnumber);
	TASSUME(originalImage,pom.issue);

	ResourceData *resource=new ResourceData();
	resource->data=QVariant(*originalImage);
	resource->type=QTextDocument::ImageResource;
	resource->name=QUrl(QString("imas-pictures://%1-orig.png").arg(picname));
	resources.append(resource);
	delete originalImage;
#endif

	PomConversionResult conv=pom.set(subnumber,&replacementImage);
	TASSUME(pom.issue.isEmpty(),pom.issue);

	QByteArray res=pom.spit();
	y.spit(res.data(),res.size());
	TASSUME(y.issue.isEmpty(),y.issue);

	QImage *replacedImage=pom.get(subnumber);
	TASSUME(replacedImage,pom.issue);
	resource=new ResourceData();
	resource->data=QVariant(*replacedImage);
	resource->type=QTextDocument::ImageResource;
	resource->name=QUrl(QString("imas-pictures://%1.png").arg(picname));
	resources.append(resource);
	delete replacedImage;

	int difference=conv.avgDiff*100/(0x400-4);
	int maxdifference=conv.maxDiff*100/(0x400-4);
#ifdef SHOW_ORIGINAL_FILE
	if(difference>=2){
#else
	if(difference>=0){
#endif
		output.append(QString::fromUtf8(
			"<span style='color:#9f4a3c'>(%2% average difference in pictures due to lack of colors in palette; peak difference - %3%)</span>"
			"<p style='vertical-align:middle;'>"
				"<img src='imas-pictures://%1-orig.png' />"
				" <span style='font-size:28pt;'>→</span> "
				"<img src='imas-pictures://%1.png' />"
			"</p>")
				  .arg(picname)
				  .arg(difference)
				  .arg(maxdifference));
		state=JOB_STATE_WARNINGS;
	} else{
		output.append(QString::fromUtf8(
			"<p style='vertical-align:middle;'>"
				"<img src='imas-pictures://%1.png' />"
			"</p>")
				  .arg(picname));
		state=JOB_STATE_OK;
	}


} catch(QString ss){
	state=JOB_STATE_FAILED;
}}

void YumCopyJob::process(){try{
	TASSUME(number!=target,QString("Trying to copy file %1 into itself").arg(number));

	Yum y(isofile,number);
	TASSUME(y.issue.isEmpty(),y.issue);

	QByteArray bytes=y.slurp();
	TASSUME(y.issue.isEmpty(),y.issue);

	Yum yy(isofile,target);
	TASSUME(yy.issue.isEmpty(),yy.issue);

	if(yy.size()!=0){
		yy.spit(bytes.data(),bytes.size());
		TASSUME(yy.issue.isEmpty(),yy.issue);
	}

	state=JOB_STATE_AUTO;
} catch(QString ss){
	state=JOB_STATE_FAILED;
}}



void WorkerThread::run(){
	emit Start();

	emit Range(0,window->jobs.count()-1);
	emit Value(0);

	cancelled=false;


	for(int i=0;i<window->jobs.count();i++){
		emit Value(i);

		GenericJob *job=window->jobs.at(i);

		if(!job->source.isEmpty()){
			job->file=new rwfile(job->source);
			if(!job->file->issue.isEmpty()){
				job->fail(job->file->issue);
				continue;
			}
		} else job->file=NULL;

		if(!job->iso_filename.isEmpty()){
			job->isofile=window->iso->open(job->iso_filename);
			if(job->isofile==NULL){
				job->fail(QString("%1 (inside iso) - %2").arg(job->iso_filename).arg(window->iso->issue));
				continue;
			}
		} else job->isofile=NULL;

		job->process();

		window->resources.append(job->resources);

		job->close();
	}

	emit Finish();
}

void WorkerThread::Cancel(){
	cancelled=true;
}

struct dup_entry{unsigned short no;const char *dups;};

dup_entry yum_dups_list[]={
#include "dups.c.inc"
};

static QHash<unsigned short,const char *> yum_dups_hash;
static QList<unsigned short> yum_dups(unsigned short no){
	if(yum_dups_hash.isEmpty()){
		for(uint i=0;i<sizeof(yum_dups_list)/sizeof(yum_dups_list[0]);i++){
			yum_dups_hash.insert(yum_dups_list[i].no,yum_dups_list[i].dups);
		}
	}

	QList<unsigned short> res;

	const unsigned short *dd=(const unsigned short *)yum_dups_hash.value(no);
	if(dd==NULL) return res;

	unsigned short number;
	while((number=*dd++)!=0xffff)
		res.append(number);

	return res;
}

void MainWindow::on_doItButton_clicked(){
	int len=ui->listWidget->count();

	if(len==0) return;

	ui->doItButton->setEnabled(false);

	iso=new Iso(isoFilename);
	if(!iso->issue.isEmpty()){
		carp(iso->issue);
		delete iso;
		ui->doItButton->setEnabled(true);
		return;
	}

	QString yum;
	rwops *rwyum=NULL;

	if((rwyum=iso->open("/PSP_GAME/USRDIR/YUMFILE_1.BIN"))!=NULL){
		yum="/PSP_GAME/USRDIR/YUMFILE_1.BIN";
	} else if((rwyum=iso->open("/PSP_GAME/USRDIR/YUMFILE_2.BIN"))!=NULL){
		yum="/PSP_GAME/USRDIR/YUMFILE_2.BIN";
	} else if((rwyum=iso->open("/PSP_GAME/USRDIR/YUMFILE_3.BIN"))!=NULL){
		yum="/PSP_GAME/USRDIR/YUMFILE_3.BIN";
	}

	if(rwyum){
		delete rwyum;
	} else{
		delete iso;
		ui->doItButton->setEnabled(true);
		carp("None of YUMFILE_1.BIN YUMFILE_2.BIN or YUMFILE_3.BIN were found in iso");
		return;
	}

	QHash<QString,int> dups;
	GenericJob *job;

	QRegExp imageFile("(\\d+)(-(\\d+)|)\\.(png|gif|jpe?g|bmp)$");
	QRegExp emailFile("(\\d+)\\.mail\\.txt$");

	for(int i=0;i<len;i++){
		QString file=ui->listWidget->item(i)->text();
		QString name=filename(file);
		QString ext=fileext(file);
		int no=isanumberfile(name);

		if(dups.contains(file)){
			job=new GenericJob();
			job->issue="Skipped: already in the list";
			job->state=JOB_STATE_SKIPPED;
			job->difficulty=0;
			job->type="NONE";
			no=-1;
		} else if(name.toUpper()=="EBOOT.BIN"){
			job=new IsoFileJob();
			job->difficulty=1;
			job->iso_filename="/PSP_GAME/SYSDIR/EBOOT.BIN";
			job->type="ISO-FILE";
		} else if(file.right(10)==".lines.txt"){
			job=new ExecutableLinesJob();
			job->difficulty=1;
			job->iso_filename="/PSP_GAME/SYSDIR/EBOOT.BIN";
			job->type="EXEC-LINES";
		} else if(emailFile.indexIn(name)!=-1){
			YumMailJob *yjob=new YumMailJob();
			yjob->number=no=emailFile.cap(1).toInt();
			job=yjob;
			job->difficulty=1;
			job->iso_filename=yum;
			job->type="EMAIL";
		} else if(no!=-1 && ext=="txt"){
			YumScriptJob *yjob=new YumScriptJob();
			yjob->number=no;
			job=yjob;
			job->difficulty=3;
			job->iso_filename=yum;
			job->type="SCRIPT";
		} else if(imageFile.indexIn(name)!=-1){
			YumPomJob *yjob=new YumPomJob();
			yjob->number=no=imageFile.cap(1).toInt();
			bool ok;
			yjob->subnumber=imageFile.cap(3).toInt(&ok);
			if(!ok) yjob->subnumber=1;
			job=yjob;
			job->difficulty=3;
			job->iso_filename=yum;
			job->type="POM";
		} else if(no!=-1){
			YumFileJob *yjob=new YumFileJob();
			yjob->number=no;
			job=yjob;
			job->difficulty=1;
			job->iso_filename=yum;
			job->type="YUM-FILE";
		} else{
			job=new GenericJob();
			job->difficulty=0;
			job->state=JOB_STATE_SKIPPED;
			job->type="NONE";
			job->issue="Don't know what to do with this file";
		}

		dups.insert(file,1);
		job->source=file;
		if(job->desc.isEmpty()) job->desc=name;

		jobs.append(job);

		if(no!=-1){
			QList<unsigned short> d=yum_dups(no);
			for(int i=0;i<d.count();i++){
				int n=d.at(i);

				YumCopyJob *yjob=new YumCopyJob();
				yjob->number=no;
				yjob->target=n;
				yjob->difficulty=1;
				yjob->type="COPY";
				yjob->desc=QString("%1.pom").arg(n);
				yjob->output+=QString("Duplicate of %1").arg(name);
				yjob->source=job->source;
				yjob->iso_filename=job->iso_filename;


				jobs.append(yjob);
			}
		}
	}

	thread.start();

	ok();
}


void MainWindow::on_jobs_started(){
	ui->progressBar->show();
}

void MainWindow::on_jobs_finished(){
	ui->progressBar->hide();

	delete iso;

	QString text=
		"<table style='border-collapse: collapse;'>"
			"<tr style='background: #efefef;'>"
				"<td style='padding:0 0.1em 0 0.1em;'>File name</td>"
				"<td style='padding:0 0.1em 0 0.1em;'>Job type</td>"
				"<td style='padding:0 0.1em 0 0.1em;'>Result</td>"
			"</tr>";

	int counts[5]={0,};
	const char *colors[]={
		"#efe",		// JOB_STATE_OK
		"#fee",		// JOB_STATE_FAILED
		"#ffe",		// JOB_STATE_WARNINGS
		"#eee",		// JOB_STATE_SKIPPED
		"#f2f8f2"	// JOB_STATE_AUTO
	};

	int succ=0,failed=0;

	for(int i=0;i<jobs.count();i++){
		GenericJob *j=jobs.at(i);

		counts[j->state]++;
		if(j->state!=JOB_STATE_OK && j->state!=JOB_STATE_AUTO) failed++;
		else succ++;

		QString comment=j->issue;
		if(comment.isEmpty()){
			if(!j->output.isEmpty())
				comment=j->output.join("<br />");
			else switch(j->state){
			case JOB_STATE_OK:			comment="ok!"; break;
			case JOB_STATE_FAILED:		comment="failed!"; break;
			case JOB_STATE_WARNINGS:	comment="completed with warnings"; break;
			case JOB_STATE_SKIPPED:		comment="skipped"; break;
			case JOB_STATE_AUTO:		comment="auto"; break;
			default:					comment="MISSINGNO"; break; // fuck yeah stack broken by counts array!
			}
		}

		text+=QString(
			"<tr style='background: %1;'>"
				"<td style='padding:0 0.1em 0 0.1em;'>%2</td>"
				"<td style='padding:0 0.1em 0 0.1em;'>%3</td>"
				"<td style='padding:0 0.1em 0 0.1em;'>%4</td>"
			"</tr>"
		).arg(colors[j->state])
		 .arg(j->desc)
		 .arg(j->type)
		 .arg(comment);
	}

	text+="</table>";

	QString title;
	if(failed==0){
		title="All ok!";

		text.prepend("<h1>All jobs completed succesfully.</h1><hr />");
	} else{
		title=QString("%1 jobs completed successfully; ").arg(succ);
		QStringList list;
		if(counts[JOB_STATE_FAILED]!=0)
			list.append(QString("%1 errors").arg(counts[JOB_STATE_FAILED]));
		if(counts[JOB_STATE_WARNINGS]!=0)
			list.append(QString("%1 warnings").arg(counts[JOB_STATE_WARNINGS]));
		if(counts[JOB_STATE_SKIPPED]!=0)
			list.append(QString("%1 skipped").arg(counts[JOB_STATE_SKIPPED]));

		title.append(list.join(", "));

		text.prepend(QString("<h1>%1</h1><hr />").arg(title));

		title=QString("Completed %1 out of %2 jobs.").arg(succ).arg(succ+failed);
	}

	report(title,text,&resources,failed==0);

	CLEAR_LIST(resources);

	CLEAR_LIST(jobs);

	ui->doItButton->setEnabled(true);
}

void MainWindow::carp(const QString & cause){
	if(cause.isEmpty()){
		ok();
		return;
	}

	ui->statusBar->showMessage(QString("Error: %1").arg(cause),5000);
}
void MainWindow::ok(){
	ui->statusBar->clearMessage();
}

void MainWindow::selectIso(const QString & path){
	if(path.isEmpty()) return;

	isoFilename=path;
	ui->selectIsoButton->setDescription(QString("Currently selected: %1")
		.arg(isoFilename.isEmpty()?"None":isoFilename));

	ok();
}

void MainWindow::on_selectIsoButton_clicked(){
    QString path;

    path=QFileDialog::getOpenFileName(
        this,
        "Choose ISO",
		isoFilename,
        QString::null);

    if(path=="") return;

   selectIso(path);
}

void MainWindow::on_addFileButton_clicked(){
	QFileDialog dialog;

	SETTINGS();

	QStringList files=dialog.getOpenFileNames(
		this,
		QString("Choose files to add"),
		settings.value("main-window-add-files").toString(),
		QString::null
	);

	if(files.empty()) return;

	settings.setValue("main-window-add-files",files.at(0));

	for(int i=0;i<files.count();i++){
		addFile(files.at(i));
	}
}

void MainWindow::on_deleteFileButton_clicked(){
	for(int i = 0, len = ui->listWidget->count();i < len; ++i){
		delete ui->listWidget->takeItem(0);
	}
}

void MainWindow::on_removeFileButton_clicked(){
	for(int i=0;i<ui->listWidget->count();++i){
		if(!ui->listWidget->item(i)->isSelected()) continue;

		delete ui->listWidget->takeItem(i);
		i--;
	}
}

void MainWindow::addFile(const QString & name, int level){
	if(level<0) return;

	QDir dir(name);

	if(dir.exists()){
		dir.setFilter(QDir::Files);
		QStringList list=dir.entryList();
		for(int i=0;i<list.size();++i){
			addFile(QString("%1/%2").arg(name).arg(list.at(i)),level-1);
		}

		return;
	}

	new QListWidgetItem(name,ui->listWidget);
}


void MainWindow::dragEnterEvent(QDragEnterEvent *event){
	event->accept();
}

void MainWindow::dropEvent(QDropEvent *event){
	event->acceptProposedAction();

	QList<QUrl> list=event->mimeData()->urls();

	for(int i=0;i<list.count();i++){
		addFile(list[i].toLocalFile());
	}
}

void MainWindow::report(const QString & title,const QString & text,QList<ResourceData *> *resources,int success){
	SETTINGS();
	bool noshowonsuccess=settings.value("report-window-don't-show-on-success")==true;
	if(success==1 && noshowonsuccess) return;

	Ui_Dialog dui;
	QDialog *dialog=new QDialog(this);
	dui.setupUi(dialog);

	if(resources)
	for(int i=0;i<resources->count();i++){
		ResourceData *data=resources->at(i);
		dui.textBrowser->document()->addResource(data->type,data->name,data->data);
	}

	dui.textBrowser->setHtml(text);
	dui.showOnSuccessBox->setChecked(noshowonsuccess);
	dialog->setWindowTitle(title);

	if(success==-1) dui.showOnSuccessBox->setVisible(false);


	dialog->restoreGeometry(settings.value("report-window-geometry").toByteArray());
	dialog->exec();
	settings.setValue("report-window-geometry",dialog->saveGeometry());
	settings.setValue("report-window-don't-show-on-success",dui.showOnSuccessBox->isChecked());

	delete dialog;
}

void MainWindow::about(){
	About about(this);
	about.exec();
}
