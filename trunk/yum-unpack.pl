use strict;
use bytes;
use Getopt::Long;

$|++;

my($home);
BEGIN{($home)=$0=~/(.*)[\/\\].*/;$home||=".";}
use lib $home;

BEGIN{ require "utils.pl" }

my %padfiles=(
	script		=> "0x2000",
);
my $nocom=0;

GetOptions(
	"pad=s"				=> \%padfiles,
	"nocompress"		=> \$nocom,
);

sub usage(){die <<HERE}
Usage: $0 FILENAME
Usage: $0 DIRECTORY
First form will unpack a YUM archive. If you have a file YUMFILE_1.BIN,
this will create directory YUMFILE_1 with all files, and file YUMFILE_1.index
with listing that is needed to recreate archive.
Second form will create a YUM archive from a directory. File DIRECTORY.index
must be present in the same directory for this to work.
  -p TYPE=AMOUNT        will insert at least AMOUNT of padding after files
                        of type TYPE when creating archive. This is useful if
                        you plan to replace these files without remaking an
                        archive in future. Default value is 0x2000 for files
                        of type script, and 0 for others.
  -n, --nocompress      do not compress files that were originally compressed.
                        Might speed up archive creation process. Might break
                        the game. Compression in .cso images is clearly
                        superior. 
HERE

sub consume($$){
	my($mask,$handle)=@_;
	
	my $length=length pack $mask,"";
	
	read $handle,my $buffer,$length;
	
	unpack $mask,$buffer;
}

sub pad($){
	my($v)=@_;
	if(($v&0x7ff)!=0){
		$v&=0xfffff800;
		$v+=0x800;
	}
	$v
}

sub smallpad($){
	my($v)=@_;
	if(($v&0xf)!=0){
		$v&=0xfffffff0;
		$v+=0x10;
	}
	$v
}

sub lzss($$){
	my($dc,$data)=@_;
	my $flag=$dc?'d':'e';
	
	open my $hh,">lzss-left-11111";
	binmode $hh;
	print $hh $data;
	close $hh;
	
	(system "lzss $flag lzss-left-11111 lzss-right-11111 1>NUL")==0
		or die "lzss failed: $?";
	
	open my $hh,"lzss-right-11111";
	binmode $hh;
	local $/;
	$data=<$hh>;
	close $hh;
	
	unlink qw/lzss-left-11111 lzss-right-11111 NUL/;
	
	$data
}

sub lzssd($){lzss(1,$_[0])}
sub lzsse($){lzss(0,$_[0])}

my $h;
my $exceptions=(open $h,"exceptions" and {
	grep{$_} map{
		s/#.*//;
		/^([\w\d]+):\s+(.*)/ or next;
		my($type,$nums)=($1,$2);
		
		map{$_=>$type} split /\s+/,$nums;
	} <$h>
} or {});

my $filename=shift or usage;

if(-f $filename){
	my($dirname)=$filename=~/(^.*)\.bin/i;
	
	open my $h,$filename or die "$! - $filename";
	binmode $h;
	
	mkdir $dirname;
	open my $indeksu,">$dirname.index" or die "$! - $dirname.index";
	
	my($head,$count,$packs,$off,$data_off,undef,undef)=consume "a8I6",$h;
	
	$head eq "YUM\0\0\0\0\0" or die "Not a yum file - $filename";
	
	my @files=map{
		[consume "I4",$h]
	}1..$count;
	
	my @packs=map{
		[consume "I3",$h]
	}1..$packs;
	
	seek $h,0,2;
	my $filesize=tell $h;

	my $packno=0;
	my $fileno=0;
	my $lasttype="";
	for(@packs){
		seek $h,$_->[0],0;
		read $h,my $data,$_->[1];
		
		$data=lzssd $data if $_->[2];
		
		my $type;
		
		if		($exceptions->{$packno})		{$type=$exceptions->{$packno}}
		elsif	($data=~m!^/?/?MIF!)			{$type="mif"}
		elsif	($data=~m!^POM\0!)				{$type="pom"}
		elsif	($data=~m!^BOM\0!)				{$type="bom"}
		elsif	($data=~m!^MDL!)				{$type="mdl"}
		elsif	($data=~m!^\x89PNG!)			{$type="png"} # just few pictures
		elsif	($data=~m!^RIFF!)				{$type="at3"} # music only
		elsif	($data=~m!^pBAV!)				{$type="pbav"}
		elsif	($data=~m!^CMSP!)				{$type="cmsp"} # Character model SP?
		elsif	($data=~m!^ACT\0!)				{$type="act"} # Seems to go with cmsp files
		elsif	($data=~m!^ANM\0!)				{$type="anm"}
		elsif	($data=~m!^\0PBP!)				{$type="pbp"}
		elsif	($data=~m!^STG\0!)				{$type="stg"}
		elsif	($data=~m!^\x80[\x00-\x7f].*\x80\x01.*\x80[\x00\x20].*!sx)
												{$type="script"}
		elsif	($data=~m!^\x80.\x00!sx)
												{$type="script-sup"}
		elsif	(valid_sjis $data)
												{$type=$data=~/##000/?"mail.txt":"txt"}
		else									{$type="unk"}
		
		$lasttype=$type;
		mkdir "$dirname/$type";
		
		my $filename="$dirname/$type/$packno.$type";
		
		if((length $data)!=0){
			open my $o,">$filename" or die "$! - $filename";
			binmode $o;
			print $o $data;
			close $o;
		}
		
		print $indeksu ($_->[2]?"C":"")."\t$filename\n";
		
		if(--$files[$fileno]->[2]==0){
			$fileno++;
			print $indeksu "%%\n";
		}
		$packno++;
		
		printf "\r                           \r%d/%d",$packno,scalar @packs;
	}
	
} elsif(-f "$filename.index"){
	open my $index,"$filename.index" or die "$! - $filename.index";
	
	open my $h,">$filename.bin" or die "$! - $filename";
	binmode $h;

	my @files;
	my @packs;
	
	my $packsize=0;
	
	while($_=<$index>){
		s/\r?\n//s;
		
		if(/^%%$/){
			push @packs,$packsize if $packsize;
			$packsize=0;
		} elsif(/(\w*)\s+(.*)/){
			my($mode,$file)=($1,$2);
			
			push @files,[$file,$mode];
			$packsize++;
		} else{
			die "$filename.index, line $.: wrong file format";
		}
	}
	
	my $start=32+16*@packs+12*@files;
	my $off=pad($start);

 	print $h "YUM\0\0\0\0\0",pack "I6",scalar @packs,scalar @files,0x20,$off,0x800,0x10;
	
	seek $h,$start,0;
	print $h "\xff"x($off-$start);
	
	my $fileno=0;
	my $totalpacked=0;
	my $totalfiles=@files;
	for my $packno(0..$#packs){
		my $packcount=$packs[$packno];
		
		my $startoff=$off;
		
		for(1..$packcount){
			my $file=shift @files;
			
			my($filename,$flags)=@$file;
			$flags=~s/C//g if $nocom;
			
			my($type,$shortname)=$filename=~m!.*/([\w\d]+)/(.*)$!;
			
			my $data=-e $filename?slurp $filename:"";
			$data=lzsse $data if $flags=~/C/;
			
			my $length=length $data;
			
			seek $h,32+16*@packs+12*$fileno,0;
			print $h pack "I3",$off,$length,$flags=~/C/?-s $filename:0;
			
			seek $h,$off,0;
			print $h $data;
			$off+=$length+(oct $padfiles{$type});
			print $h "\xff"x((smallpad $off)-$off);
			$off=smallpad $off;
			
			$fileno++;
			printf "\r                     \r%d/%d",$fileno,$totalfiles;
		}
		
		seek $h,$off,0;
		print $h "\xff"x((pad $off)-$off);
		$off=pad $off;
		
		seek $h,32+16*$packno,0;
		print $h pack "I4",$startoff,$off-$startoff,$packcount,$totalpacked;
		$totalpacked+=$packcount;
	}
	
	close $h;
	close $index;
}

