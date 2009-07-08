#ifndef MAINWINDOW_H
#define MAINWINDOW_H

#include <QtGui/QMainWindow>
#include <QtGui>
#include "patcher.h"

namespace Ui
{
    class MainWindow;
}

using namespace QtConcurrent;

#define JOB_NOTHING				0
#define JOB_REPLACE_ISO			1
#define JOB_REPLACE_YUM			2
#define JOB_REPLACE_SCRIPT		3
#define JOB_REPLACE_LINES		4

struct JobItem{
	int type;
	QString desc;
	QString source;
	QString isofile;
	int difficulty;
	int number;
	bool dup;

	QString issue;

	JobItem(int a,const QString & x,const QString & b,const QString & c, int d,int e=-1)
		:type(a),desc(x),source(b),isofile(c),difficulty(d),number(e) {}
};

class MainWindow;

#define SETTINGS() QSettings settings("Andrey Osenenko","imas-patcher")

class WorkerThread : public QThread{
	Q_OBJECT

public:
	MainWindow *window;
	bool cancelled;
	void run();

signals:
	void Range(int,int);
	void Value(int);
	void Start();
	void Finish();

public slots:
	void Cancel();
};


class MainWindow : public QMainWindow{
    Q_OBJECT

public:
    MainWindow(QWidget *parent = 0);
	~MainWindow();

    Ui::MainWindow *ui;
	QFutureWatcher<void> watcher;
	QList<JobItem *> jobs;
	QErrorMessage message;
	Iso *iso;

	WorkerThread thread;

	void carp(const QString & cause);
	void ok();

	void selectIso(const QString & path);

	void addFile(const QString & name, int level=3);

	void dragEnterEvent(QDragEnterEvent *event);
	void dropEvent(QDropEvent *event);

	void report(const QString & title,const QString & text,int success=0);


private slots:
	void on_jobs_started();
	void on_jobs_finished();

	void on_deleteFileButton_clicked();
	void on_selectIsoButton_clicked();
    void on_doItButton_clicked();
	void on_addFileButton_clicked();

	void about();
};

#endif // MAINWINDOW_H
