#include <QtGui>

#include "mainwindow.h"
#include "ui_mainwindow.h"
#include "ui_report.h"
#include "about.h"

#include "patcher.h"
#include "text.h"

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
	settings.setValue("main-window-iso",ui->isoEdit->text());

	QStringList items;
	for(int i=0,l=ui->listWidget->count();i<l;i++){
		items.append(ui->listWidget->item(i)->text());
	}

	settings.setValue("main-window-patch-files",items);

    delete ui;
}

void mapfunc(JobItem *job,MainWindow *window){
	QString issue;

	if(job->type==JOB_NOTHING) return;
	if(job->dup) return;

	rwops *isofile=window->iso->open(job->isofile);
	if(isofile==NULL){
		job->issue=QString("%1 (inside iso) - %2").arg(job->isofile).arg(window->iso->issue);
		return;
	}

	rwfile file(job->source);
	if(!job->source.isEmpty() && !file.issue.isEmpty()){
		delete isofile;
		job->issue=QString("%1 - %2").arg(job->source).arg(file.issue);
		return;
	}

	switch(job->type){
	case JOB_REPLACE_ISO:{
		char buff[0x400];
		int count;
		while((count=file.read(buff,sizeof(buff)))!=0){
			int written=isofile->write(buff,count);
			if(written!=count){
				job->issue="Not enough space";
				return;
			}
		}

		break;}
	case JOB_REPLACE_LINES:{
		QString line;
		QRegExp reg("([0-9a-fA-F]{8})\\s+(\\d+) ([^\r\n]*)\r?\n?");
		QRegExp remove_comments("\\s*#.*$");

		while(!(line=file.readline()).isNull()){
			if(!reg.exactMatch(line)) continue;

			bool ok;
			ulong address=reg.cap(1).toULong(&ok,16);
			ASSUME(ok,QString("Expected address, got ``%1''").arg(reg.cap(1)));

			long size=reg.cap(2).toLong(&ok,10);
			ASSUME(ok,QString("Expected size, got ``%1''").arg(reg.cap(2)));

			QString reline=reg.cap(3);
			reline.remove(remove_comments);

			QByteArray bytes=text_encode_control(reline,&issue);
			CHECK();

			ASSUME(bytes.count()<=size,QString("%1: Can't insert: short by %2 bytes -- have %3 need %4")
											 .arg(address,8,16,QChar('0'))
											 .arg(bytes.count()-size)
											 .arg(size)
											 .arg(bytes.count()));

			isofile->seek(address);
			isofile->write(bytes.data(),bytes.count());
			for(int i=0,c=size-bytes.size();i<c;i++)
				isofile->write((char *)"",1);
		}

		break;}
	case JOB_REPLACE_YUM:{
		Yum y(isofile,job->number);
		if(!y.issue.isEmpty()){
			job->issue=y.issue;
			break;
		}

		size_t c;
		char *data=file.slurp(&c);
		y.spit(data,c);
		delete[] data;

		break;}
	case JOB_REPLACE_SCRIPT:{
		rwfile rw(QString("scripts/%1.src").arg(job->number));
		ASSUME(rw.issue.isEmpty(),rw.issue);

		ImasScript script(&rw);
		ASSUME(script.issue.isEmpty(),script.issue);

		ImasScriptText text(&file);
		ASSUME(text.issue.isEmpty(),text.issue);

		int lineno=0;
		for(int i=0;i<script.nodes.count();i++){
			ImasScriptNode *node=script.nodes.value(i);

			if(node->group==SCIPT_GROUP_TEXT)
				node->text=text_encode(text.line(lineno++),&issue);
			else if(node->group>=SCIPT_GROUP_NAME)
				node->text=text_encode(text.name(node->group-SCIPT_GROUP_NAME),&issue);

			ASSUME(issue.isEmpty(),issue);
		}

		QByteArray bytes=script.spit();
		ASSUME(script.issue.isEmpty(),script.issue);

		Yum y(isofile,job->number);
		ASSUME(y.issue.isEmpty(),y.issue);

		y.spit(bytes.data(),bytes.size());
		ASSUME(y.issue.isEmpty(),y.issue);

		break;}
	}

/*	if(job->number!=-1){
		QFile out(QString("%1.txt").arg(job->number));
		out.open(QIODevice::WriteOnly);

		isofile->seek(0);
		Yum y(isofile,job->number);

		char *data;
		size_t c=y.slurp(&data);

		out.write(data,c);
		delete[] data;
	}*/

	if(isofile) delete isofile;

	return;
error:
	if(isofile) delete isofile;
	job->issue=issue;
}


void WorkerThread::run(){
	emit Start();
	
	emit Range(0,window->jobs.count()-1);
	emit Value(0);

	cancelled=false;

	for(int i=0;i<window->jobs.count();i++){
		emit Value(i);

		mapfunc(window->jobs.at(i),window);
	}

	emit Finish();
}

void WorkerThread::Cancel(){
	cancelled=true;
}


void MainWindow::on_doItButton_clicked(){
	int len=ui->listWidget->count();

	if(len==0) return;

	ui->doItButton->setEnabled(false);

	iso=new Iso(ui->isoEdit->text());
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
	};

	QHash<QString,int> dups;
	JobItem *item;

	for(int i=0;i<len;i++){
		QString file=ui->listWidget->item(i)->text();
		QString name=filename(file);
		QString ext=fileext(file);
		int no=isanumberfile(name);

		if(name.toUpper()=="EBOOT.BIN"){
			jobs.append(item=new JobItem(
				JOB_REPLACE_ISO,	"EBOOT.BIN",
				file,				"/PSP_GAME/SYSDIR/EBOOT.BIN",
				1
			));
		} else if(file.right(10)==".lines.txt"){
			jobs.append(item=new JobItem(
				JOB_REPLACE_LINES,	name,
				file,				"/PSP_GAME/SYSDIR/EBOOT.BIN",
				1
			));
		} else if(no!=-1 && ext=="txt"){
			jobs.append(item=new JobItem(
				JOB_REPLACE_SCRIPT,	QString("%1").arg(no),
				file,				yum,
				1,
				no
			));
		} else if(no!=-1){
			jobs.append(item=new JobItem(
				JOB_REPLACE_YUM,	QString("%1.%2").arg(no).arg(ext),
				file,				yum,
				1,
				no
			));
		} else{
			jobs.append(item=new JobItem(
				JOB_NOTHING,		name,
				"",					"",
				0
			));

			item->issue="Don't know what to do with this file";
		}

		if((item->dup=dups.contains(file)))
			item->issue="Skipped: already in the list";
		dups.insert(file,1);
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

	QString text="<table style='border-c0ollapse: collapse;'>";

	int errors=0,successes=0;

	for(int i=0;i<jobs.count();i++){
		JobItem *j=jobs.at(i);

		QString comment=j->issue,color="#fee";
		if(j->issue.isEmpty())
			comment="ok!",color="#efe",successes++;
		else if(j->dup)
			color="#eee";
		else
			errors++;

		text+=QString("<tr style='background: %3;'><td style='padding:0 0.1em 0 0.1em;'>%1</td><td style='padding:0 0.1em 0 0.1em;border-left=1px dotted;'>%2</td>").arg(j->desc).arg(comment).arg(color);
	}

	text+="</table>";

	QString title;
	if(errors==0){
		title="All ok!";

		text.prepend("<h1>All jobs completed succesfully.</h1><hr />");
	} else{
		title=QString("Completed with %1 errors").arg(errors);

		text.prepend(QString("<h1><span style='color: red'>Errors!</span> Completed %1 out of %2 jobs.</h1><hr />").arg(successes).arg(jobs.count()));
	}

	report(title,text,errors==0);

	CLEAR_LIST(jobs);

	ui->doItButton->setEnabled(true);
}

void MainWindow::carp(const QString & cause){
	if(cause.isEmpty()){
		ok();
		return;
	}

	ui->statusBar->showMessage(cause,5000);
}
void MainWindow::ok(){
	ui->statusBar->clearMessage();
}

void MainWindow::selectIso(const QString & path){
	if(path.isEmpty()) return;

	Iso iso(path);

	if(!iso.issue.isEmpty()){
		carp(iso.issue);
		return;
	}

	ui->isoGroupBox->setTitle(QString("ISO: %1").arg(iso.volume));

	ui->isoEdit->setText(path);
	ok();
}

void MainWindow::on_selectIsoButton_clicked(){
    QString path;

    path=QFileDialog::getOpenFileName(
        this,
        "Choose ISO",
		ui->isoEdit->text(),
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

void MainWindow::addFile(const QString & name, int level){
	if(level<0) return;

	QDir dir(name);

	if(dir.exists()){
		dir.setFilter(QDir::Files);
		QStringList list=dir.entryList();
		for(int i=0;i<list.size();++i){
			addFile(list.at(i),level-1);
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

void MainWindow::report(const QString & title,const QString & text,int success){
	SETTINGS();
	bool noshowonsuccess=settings.value("report-window-don't-show-on-success")==true;
	if(success==1 && noshowonsuccess) return;

	Ui_Dialog dui;
	QDialog *dialog=new QDialog(this);
	dui.setupUi(dialog);
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

