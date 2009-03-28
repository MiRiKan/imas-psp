use strict;

# perl wiki-make-page.pl -f "YUMFILE_1/script/*.txt" -m "/.*\D(\d+)/;qq{Idolmaster_SP:PS:$1}" -u "Anonymous of Russian Federation" -p "" -a  " <nowiki>\n"

use WWW::Mechanize;
use Getopt::Long;
use Data::Dumper;

$|++;

my $files="*.script";
my $append="";
my $mogrify="";
my $user="";
my $pass="";
my $link="http://www.tsukuru.info/tlwiki/index.php";

GetOptions(
	"files=s"		=> \$files,
	"append=s"		=> \$append,
	"mogrify=s"		=> \$mogrify,
	"user=s"		=> \$user,
	"pass=s"		=> \$pass,
	"link=s"		=> \$link,
);

sub usage(){die <<HERE}
Usage: $0
Will create pages on wiki.
  -f, --files FILES         files you want to upload.
  -a, --append TEXT         prepend file content with this text.
  -m, --mogrify CODE        perl code used to generate titles. \$_ is file
                            name. Leave empty to have titles same as file
                            names.
  -u, --user TEXT           use this name to log into wiki.
  -p, --pass TEXT           use this password to log into wiki.
  -l, --link TEXT           link to wiki's index.php script. Default is
                            http://www.tsukuru.info/tlwiki/index.php
HERE


sub slurp($){local $/;open my $h,"$_[0]" or die "$! - $_[0]";binmode $h; my $data=<$h>;close $h;$data}

sub unescape($){
	local($_)=@_;
	
	s/\\(.)/
		my $ch=$1;
		
		$ch="\n" if $ch eq 'n';
		
		$ch;
	/ge;
	
	$_
}

sub list($){
	my($mask)=@_;

	my($dirpart,$namepart)=$mask=~m!^(?:(.+)/)?(.*)$!;
	$dirpart||='.';

	my $regexp_text=$namepart;
	$regexp_text=~s/\./\\./g;
	$regexp_text=~s/\*/.*/g;
	$regexp_text=~s/\?/./g;

	my $regexp=qr/^$regexp_text$/;

	opendir my $dir,$dirpart or die "$! - $dirpart";
	
	map "$dirpart/$_",grep /$regexp/,readdir $dir;
}

sub mogrify($;@){
	my($code,@list)=@_;
	
	my $sub=eval 'sub{ no strict; $_=shift; '.$code.' }';
	
	map{$_ => $sub->($_)} @list
}

my @files=list $files;
my %pages=mogrify $mogrify,@files;

my $mech=WWW::Mechanize->new();

my $response=$mech->post(
	"$link?title=Special:Userlogin&action=submitlogin",
	Content=>[
		wpName=>$user,
		wpPassword=>$pass,
		wpRemember=>"1",
		wpLoginAttempt=>"Log in"
	]
);

die "couldn't login: ".$response->code unless $mech->content=~/You are now logged in/;

for(@files){
	my $title=$pages{$_};
	my $text=(unescape $append).slurp $_;
	
	print "$_ -> $title.. ";
	
	$mech->get("$link?title=$title&action=edit");
	
	print "posting changes.. ";

	$mech->submit_form(
		form_name	=> 'editform',
		fields		=> {
			wpTextbox1  => $text,
			wpSummary	=> "I am uploading scripts!",
		},
		button		=> 'wpSave',
	);

	print "ok!\n";
}








