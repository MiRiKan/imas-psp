use strict;
use utf8;
use Cwd 'abs_path';
use Getopt::Long;
use Encode;
use Data::Dumper;

$|++;

my($home);
BEGIN{($home)=$0=~/(.*)[\/\\].*/;$home||=".";}
use lib $home;

BEGIN{ require "utils.pl" }

my $type="";
my $binary;
my $encoding="";
my $game;

GetOptions(
	"type=s"		=> \$type,
	"binary"		=> \$binary,
	"decode=s"		=> \$encoding,
	"game=s"		=> \$game,
);

my $gameno;

if(defined $game){
	   if($game eq 'ps'){$gameno=1}
	elsif($game eq 'ws'){$gameno=2}
	elsif($game eq 'mm'){$gameno=3}
	else                {die "Game must be one of the following: ps ws mm\n"};
}

sub usage(){print <<HERE;exit;}
Usage: $0 FILES
    
HERE

my @files=list(shift or usage);
for(@files){
	next if -d $_;
	
	my $filename=abs_path($_);
	
	unless(defined $game){
		$gameno=undef;
		   if($filename=~/YUMFILE_1/){$gameno=1}
		elsif($filename=~/YUMFILE_2/){$gameno=2}
		elsif($filename=~/YUMFILE_3/){$gameno=3}
		else                         {die "Could not determine game for file $filename\n"};
	}
	
	query "delete from text where filename=?",$filename;
	query "replace files values (?,?,?,?)",$filename,$gameno,$type,$encoding;
	
	open my $h,"<",$filename or die "$! - $filename";
	
	if($binary){
		binmode $h;
		
	} else{
		binmode $h,":utf8" unless $encoding;
		while($_=<$h>){
			$_=decode $encoding,$_ if $encoding;
			
			query "replace text values (?,?,?,?,?)",$.,$filename,$gameno,$_,$type;
		}
	}
	
	close $h;
}
