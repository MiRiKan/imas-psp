# WRITTEN BY ANDREY OSENENKO.
# REDISTRIBUTION AND USE OF MY ART ARE PERMITTED PROVIDED THAT THE FOLLOWING CONDITIONS ARE MET:
# YOU MUST ATTRIBUTE !!
# DO NOT STEAL MY ART.

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

die "File $resfile.png doesn't exist"
	unless -e "$resfile.png";

open my $h,"+<",$filename or die "$! - $filename";
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
#		my($r,$g,$b,$a)=consume "C4",$h;pack "C4",$b,$g,$r,$a==0x80?0:(0x7f-$a)*2
		[consume "C4",$h]
	}1..2**$bpp]
} 1..$imagecount;

my @palette=@{ $palettes[0] };

`convert "$resfile.png" "$resfile.bmp"`;
-e "$resfile.bmp" or die;

open my $bmp,"$resfile.bmp" or die "$_ - $resfile.bmp";
my($head,$bmp_size,undef,undef,$bmp_offset,undef,$bmp_w,$bmp_h)=consume "a2ISSII3",$bmp;

die sprintf "Width doesn't match: pom has %d, your file has %d",$width,$bmp_w unless $width==$bmp_w;
die sprintf "Height doesn't match: pom has %d, your file has %d",$height,$bmp_h unless $height==$bmp_h;

my $subh=8;
my $subw=$bpp==8?0x10:0x20;
my $wsubc=$width/$subw;

sub find_closest_color($){
	my($color)=@_;
	my $index=0;
	my $range=0x0fffffff;
	
	for(0..$#palette){
		my $pc=$palette[$_];
		my $diff=
			abs($color->[0]-$pc->[0])+
			abs($color->[1]-$pc->[1])+
			abs($color->[2]-$pc->[2])+
			abs($color->[3]-$pc->[3])*2;
		
		if($diff<$range){
			$range=$diff;
			$index=$_;
		}
	}
	
	$index
}

for my $hblock(0..$height/$subh-1){
	for my $wblock(0..$wsubc-1){
		for my $line(1..$subh){
			seek $bmp,$bmp_offset+(($height-($hblock*$subh+$line))*$width+($wblock*$subw))*4,0;
			
			my $last_palette_color;
			for my $p(0..$subw-1){
				my($r,$g,$b,$a)=consume "C4",$bmp;
				
				my $color=[$b,$g,$r,$a==0?0x80:int((0xff-$a)/2)];
				my $palette_color=find_closest_color($color);
				
				if($bpp==8){
					print $h pack "C",$palette_color;
				} elsif($p&0x01){
					print $h pack "C",($palette_color<<4)|$last_palette_color;
				} else{
					$last_palette_color=$palette_color;
				}
			}
		}
	}
}

unlink "$resfile.bmp";


exit;

__DATA__

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


