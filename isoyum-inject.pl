# WRITTEN BY ANDREY OSENENKO.
# REDISTRIBUTION AND USE OF MY ART ARE PERMITTED PROVIDED THAT THE FOLLOWING CONDITIONS ARE MET:
# YOU MUST ATTRIBUTE !!
# DO NOT STEAL MY ART.

use strict;
use bytes;

$|++;

sub usage(){die <<HERE}
Usage: $0 ISO-FILE FILENAME
Replace a file inside yum archive inside iso image with file FILENAME.
This file must have been extracted from yum archive first (Don't just add
files at random: extract, edit, and put back)
HERE

sub dirent($){
	my($buffer)=@_;
	
	my($LEN_DR,$LEN_EAR,$location,$size,$time,$flags,$unitsize,$gapsize,$volseqnum,$name)=
		unpack 'C C Vx[N] Vx[N] a7 C C C vx[n] C/a',$buffer;
	
	[uc $name,$location,$size,$time,$flags]
}

sub readdirent($$;$$){
	my($handle,$dir,$res,$path)=(@_);
	my @list;
	
	seek $handle,$dir->[1]*0x800,0;
	while(1){
		my($ch,$len,$buf);
		
		read $handle,$ch,1;
		$len=unpack 'C',$ch or last;
		
		read $handle,$buf,$len-1;
		my $info=dirent($ch.$buf);
		$info->[0]=~s/\.;.*$//;
		
		next if $info->[0]=~/^(\c@|\cA)$/;
		
		$res->{"$path/$info->[0]"}=$info;
		push @list,$info;
	}
	
	for my $ref(@list){
		$ref->[4]&2 or next;
		$ref->[5]=readdirent($handle,$ref,$res,"$path/$ref->[0]");
	}

	if($path){
		\@list
	} else{
		$res->{""}=["",0,0,0,2,\@list];
		$res
	}
}

sub consume($$){
	my($mask,$handle)=@_;
	
	my $length=length pack $mask,"";
	
	read $handle,my $buffer,$length;
	
	unpack $mask,$buffer;
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
	
	unlink qw/lzss-left-11111 lzss-right-11111/;
	
	$data
}

sub lzssd($){lzss(1,$_[0])}
sub lzsse($){lzss(0,$_[0])}
sub slurp($){local $/;open my $h,"$_[0]" or die "$! - $_[0]";binmode $h;my $data=<$h>;close $h;$data}

my $isofile=shift or usage;
my $filename=shift or usage;
my $fileno=shift;

defined $fileno or ($fileno)=$filename=~/(?:.*\D|^)(\d+)/
	or die "Couldn't figure out where to put file in archive";
	
open my $h,"+<",$isofile or die "$! - $isofile";
binmode $h;

seek $h,0x800*16+156,0;
read $h,my $dirent,34;

my $files=readdirent $h,dirent $dirent;

my $file=$files->{'/PSP_GAME/USRDIR/YUMFILE_1.BIN'}
	or die "Couldn't find file YUMFILE_1.BIN inside iso";
	
my $yumstart=$file->[1]*0x800;

seek $h,$yumstart,0;

my($head,$packs,$files,$off,$data_off,undef,undef)=consume "a8I6",$h;
$head eq "YUM\0\0\0\0\0" or die "Not a yum file";

$fileno>=$files
	and die "File number is too high";
	
my $entryloc=$yumstart+32+$packs*16+$fileno*12;

seek $h,$entryloc,0;
my($start,$size,$compressed)	= consume "I3",$h;
my($nextstart)					= consume "I3",$h;
my $space=$nextstart-$start;

my $data=slurp $filename;
my $plainsize=$compressed?length $data:0;

$data=lzsse $data if $compressed;

my $length=length $data;

die sprintf "%d bytes short: need %d bytes, have %d",$length-$space,$length,$space
	if $length>$space;

seek $h,$yumstart+$start,0;
print $h $data;
print $h "\xff"x($space-$length);

seek $h,$entryloc,0;
print $h pack "I3",$start,$length,$plainsize;

close $h;
