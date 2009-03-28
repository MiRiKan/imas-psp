use strict;
use bytes;

my($home);
BEGIN{($home)=$0=~/(.*)[\/\\].*/;$home||=".";}
use lib $home;

BEGIN{ require "utils.pl" }

$|++;

sub usage(){die <<HERE}
Usage:
	$0 POM-FILE [PNG-FILE]
Converts a PNG picture to .pom file. Because of specifics of .pom format, you
can only convert pictures you previously converted from .pom files, and
original .pom must present in the same place. If there were many pictures
inside .pom file, you may specify which one to use to use by supplying
addition argument (if you don't, first picture will be used). Be advised that
.pom files have palettes in them -- they have only a limited set of colors,
and this particular program does not change the palette. What this really
means, though, is that if original .pom only had red color, even if you change
PNG to green, it will turn up as red in game. When editing PNGs, try to
preserve colors.
HERE

my $filename=shift or usage;
my $pngname=shift;

die "File must have .pom extension"
	unless $filename=~/(.*)\.pom$/;

my $resfile=$1;

open my $h,"+<",$filename or die "$! - $filename";
binmode $h;

my($head,$height,$width,$unk1,$unk2,$unk3,$unk4,$aliases,$subs,$unk6,$ua,$ub,$uc,$ud,$uu1,$uu2,$uu3,$uu4,$uu5,$uu6)=consume "a4I5S4S4I6",$h;

die "Not a pom file - $filename"
	unless $head eq "POM\0";

my $imagecount=$aliases+1;

my @filenames=$imagecount==1?
	"$resfile":
	map{"$resfile-$_"}1..$imagecount;

$pngname||="$filenames[0].png";

die "File $pngname doesn't exist"
	unless -e "$pngname";

my $bpp=$ub&0x40?4:8;

my @palettes=map{
	[map{
#		my($r,$g,$b,$a)=consume "C4",$h;pack "C4",$b,$g,$r,$a==0x80?0:(0x7f-$a)*2
		[consume "C4",$h]
	}1..2**$bpp]
} 1..$imagecount;

my $paletteno=-1;
$pngname eq "$filenames[$_].png" and $paletteno=$_
	foreach 0..$#filenames;

die "$pngname can't be used to build $filename"
	if $paletteno==-1;

my @palette=@{ $palettes[$paletteno] };

`convert "$pngname" "$resfile.bmp"`;
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
			abs($color->[3]-$pc->[3])*2;
			
		$diff+=
			abs($color->[0]-$pc->[0])+
			abs($color->[1]-$pc->[1])+
			abs($color->[2]-$pc->[2])
			unless $color->[3]==0 and $pc->[3]<0x08;
		
#		printf "%02x%02x%02x%02x <=> %02x%02x%02x%02x $diff",
#			$color->[0],$color->[1],$color->[2],$color->[3],
#			$pc->[0],$pc->[1],$pc->[2],$pc->[3] if $color->[3]==0;
		
		if($diff<$range){
			$range=$diff;
			$index=$_;
#			print " *\n"if $color->[3]==0;
		} else{
#			print "\n"if $color->[3]==0;
		}
	}
	
#	print "====\n"if $color->[3]==0;
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
