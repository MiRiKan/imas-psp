use strict;
use bytes;

$|++;

my($home);
BEGIN{($home)=$0=~/(.*)[\/\\].*/;$home||=".";}
use lib $home;

BEGIN{ require "utils.pl" }

sub usage(){die <<HERE}
Usage: $0 ISO-FILE FILENAME FILENAME-INSIDE-ISO
Replaces a file inside iso image with file FILENAME.
This is intended for applying small changes to boot.bin
and will not change file size.
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

my $isofile=shift or usage;
my $filename=shift or usage;
my $archfile=shift or usage;

my $contents=slurp $filename;

open my $h,"+<",$isofile or die "$! - $isofile";
binmode $h;

seek $h,0x800*16+156,0;
read $h,my $dirent,34;

my $files=readdirent $h,dirent $dirent;

$archfile=uc $archfile;
my $file=$files->{$archfile}
	or die "Couldn't find file $archfile inside iso; have files: ".join " ",keys %$files;

my $start=$file->[1]*0x800;

seek $h,$start,0;

print $h $contents;

close $h;
