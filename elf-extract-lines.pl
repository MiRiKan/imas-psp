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
Extracts lines from elf executable
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

open my $h,$filename or die "$! - $filename";
binmode $h;
open my $res,">",$lines or die "$! - $lines";
binmode $res,":utf8";

my($head,undef,$type,$machine,$version,$entry,$phoff,$shoff,$flags,$ehsize,$phentsize,$phnum,$shentsize,$shnum,$shstrndx)=
	consume "a4a12SSIIIIISSSSSS",$h;

die "Not an ELF file - $filename\n"
	unless $head eq "\x7fELF";

my %sections;

my $symtab=-1;
my @sec;

seek $h,$shoff,0;
for(1..$shnum){
	read $h,my $data,$shentsize;
	my($name,$type,$flags,$addr,$offset,$size,$link,$info,$addralign,$entsize)=
		unpack "I10",$data;
	
	push @sec,[$name,$type,$flags,$addr,$offset,$size,$link,$info,$addralign,$entsize];
	
	$symtab=$#sec if $type==3;
}
die "Couldn't find strings table - $filename\n"
	if $symtab==-1;

foreach(@sec){
	seek $h,$sec[$symtab]->[4]+$_->[0],0;
	my($line)=getline($h);

	push @$_,$line;	
	
	$sections{$line}=$_;
}

#for(sort{$a->[4] <=> $b->[4]} @sec){
#	printf "%08x - %08x $_->[10]\n",$_->[4],$_->[4]+$_->[5];
#}

for($sections{".rodata"},$sections{".data"}){
	seek $h,$_->[4],0;
	
	my $end=$_->[4]+$_->[5];

	while(tell $h<$end){
		my $pos=tell $h;
		my($line,$length,$nulls)=getline $h;
		
		next if $line=~/[\x00-\x09\x0b\x0c\x0d-\x1f]/;
		next if $line=~/\xff\xff/;
		next if length $line<4;

		my $utfline=decode "MS932",$line;
		my $jisline=encode "MS932",$utfline;
		
		next if $jisline ne $line;
		next unless $utfline=~/(\p{Han}|\p{Katakana}|\p{Hiragana}|[Ａ-Ｚａ-ｚ])/;
		
		$utfline=~s/\\/\\\\/g;
		$utfline=~s/\n/\\n/g;
		$utfline=~s/\r/\\r/g;
		
#		die sprintf "%08x $line < $utfline > $jisline",$_ unless $line eq $jisline;
		
		printf $res "%08x % 5d %s\n",$pos,$length,$utfline;
	}
}

#printf "%08x %d",$sections{".rodata"}->[4],$sections{".rodata"}->[5];

#$sections{$sec[$_]->[0]}


close $res;
close $h;








