use strict;
use bytes;

my($home);
BEGIN{($home)=$0=~/(.*)[\/\\].*/;$home||=".";}
use lib $home;

BEGIN{ require "utils.pl" }

$|++;

sub usage(){die <<HERE}
Usage:
	$0 POM-FILE
HERE

my $filename=shift or usage;

die "File must have .pom extension"
	unless $filename=~/(.*)\.pom$/;

my $resfile=$1;

open my $h,$filename or die "$! - $filename";
binmode $h;

my($head,$height,$width,$unk1,$unk2,$unk3,$unk4,$aliases,$subs,$unk6,$ua,$ub,$uc,$ud,$uu1,$uu2,$uu3,$uu4,$uu5,$uu6)=consume "a4I5S4S4I6",$h;

die "Not a pom file - $filename"
	unless $head eq "POM\0";
	
my $imagecount=$aliases+1;

my @filenames=$imagecount==1?
	"$resfile":
	map{"$resfile-$_"}1..$imagecount;

my $bpp=$ub&0x40?4:8;

my @palettes=map{
	[map{
		my($r,$g,$b,$a)=consume "C4",$h;pack "C4",$b,$g,$r,$a==0x80?0:(0x7f-$a)*2
	}1..2**$bpp]
} 1..$imagecount;

my @bmps=map{
	open my $res,">","$_.bmp" or die "$! - $_.bmp";
	binmode $res;

	print $res pack "a2ISSI","BM",$width*$height*4+0x8a,0,0,0x8a;
	print $res pack "I3S2I6",0x7c,$width,$height,1,32,3,$width*$height*4,72,72,0,0;
	print $res pack "C*",
		0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00,
		0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF,
		0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x56, 0xB8, 0x1E, 0xFC,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x66, 0x66, 0x66, 0xFC, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x63, 0xF8, 0x28, 0xFF,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00;
	
	$res
} @filenames;

my $subh=8;
my $subw=$bpp==8?0x10:0x20;
my $wsubc=$width/$subw;

my @color_data=$bpp==8?(map{
	consume "C",$h;
} 1..$width*$height):(map{
	my($color)=consume "C",$h;
	my($l,$r)=($color&0x0f,($color&0xf0)>>4);
	
	$l,$r
} 1..$width*$height);

for my $no(0..$#bmps){
	my $index=0;
	my $handle=$bmps[$no];
	my @palette=@{ $palettes[$no] };
	for my $hblock(0..$height/$subh-1){
		for my $wblock(0..$wsubc-1){
			for my $line(1..$subh){
				seek $handle,0x8a+(($height-($hblock*$subh+$line))*$width+($wblock*$subw))*4,0;
				
#				printf "% 2d % 2d % 4d % 8d\n",$hblock,$wblock,$line,($height-($hblock*$subh+$line))*$width+($wblock*$subw);
				
				for my $p(0..$subw-1){
					print $handle $palette[$color_data[$index++]];
				}
			}
		}
	}
}

close $_ foreach @bmps;
close $h;

for(@filenames){
	`convert "$_.bmp" "$_.png"`;
	unlink "$_.bmp" if -e "$_.png";
}


