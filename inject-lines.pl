use strict;
use Encode;
use Getopt::Long;

use utf8;

my($home);
BEGIN{($home)=$0=~/(.*)[\/\\].*/;$home||=".";}
use lib $home;

BEGIN{ require "utils.pl" }

sub usage(){print <<HERE;exit;}
Usage: $0 ELF-FILE TEXT-FILE
Inserts lines into file. You must supply a text file generated
by elf-extract-lines.pl
HERE

my $filename=shift or usage;
my $lines=shift or usage;

sub getline($){
	my($h)=@_;
	my $line="";
	my $nulls=0;
	
	my $data;
	while(read $h,$data,1 and $data ne "\0"){
		$line.=$data;
	}
	
	$nulls++ if $data eq "\0";
	
	while(read $h,$data,1 and $data eq "\0")
		{$nulls++}
	
	seek $h,-1,1 unless eof $h;
	
	($line,length $line,$nulls)
}

open my $h,"+<",$filename or die "$! - $filename";
binmode $h;
open my $src,$lines or die "$! - $lines";
binmode $src,":utf8";

while($_=<$src>){
	next if /^\s*$/;
	chomp;
	
	my($loc,$relength,$reline)=/^([0-9a-fA-F]{8})\s+(\d+) (.*)$/;
	next unless defined $reline;
	
	$loc=hex $loc;
	
	seek $h,$loc,0;
	my($line,$length,$nulls)=getline $h;
	
	my $utfline=decode "MS932",$line;
	$reline=~s/\\(.)/
		if($1 eq 'n')		{"\n"}
		elsif($1 eq 'r')	{"\r"}
		elsif($1 eq '\\')	{"\\"}
		else				{"$1"}
	/ge;
	
	next if $reline eq $utfline;
	
	my $newline=encode_doubletile_control $reline;
	
	next if $newline eq $line;
	
	printf "%08x: Can't insert: short by %d bytes -- have %d need %d ($line <- $newline)\n",
			$loc,length $newline-$relength,$relength,length $newline and next
		if length $newline>$relength;
	
	seek $h,$loc,0;
	print $h $newline,"\0"x($relength-length $newline);
	
	printf "%08x ok $line $newline\n",$loc;
}

close $src;
close $h;
