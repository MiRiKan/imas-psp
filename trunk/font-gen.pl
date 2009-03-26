use strict;
use bytes;

my($home);
BEGIN{($home)=$0=~/(.*)[\/\\].*/;$home||=".";}
use lib $home;

BEGIN{ require "utils.pl" }

our $chars;

$|++;

sub usage(){die <<HERE}
Usage:
	$0 PNG-FILE
HERE

use constant GLYPH_WIDTH =>		8;
use constant GLYPH_HEIGHT =>	16;

my @charslist=split //,$chars;
my @combinations=map{
	my $l=$_;
	map{ [$l,$_] } 0..$#charslist
} 0..$#charslist;

my $filename=shift;

die "File $filename doesn't exist"
	unless -e "$filename";

`convert "$filename" "$filename.bmp"`;
-e "$filename.bmp" or die;

open my $bmp,"<","$filename.bmp" or die "$! - $filename.bmp";
binmode $bmp;

my($start,$w,$h)=consume_bmp_header $bmp;

die "Wrong width: must be ".GLYPH_WIDTH*@charslist.", is $w in your file" unless $w==GLYPH_WIDTH*@charslist;
die "Wrong height: must be ".GLYPH_HEIGHT.", is $h in your file" unless $h==GLYPH_HEIGHT;

my @glyph_data=map{
	my $start=$start+GLYPH_WIDTH*$_*4;
	[map{
		seek $bmp,$start+$w*4*$_,0;
		read $bmp,my $data,GLYPH_WIDTH*4;
		
		$data
	} 0..GLYPH_HEIGHT-1]
} 0..$#charslist;

close $bmp;

open $bmp,">","$filename-1.bmp" or die "$! - $filename-1.bmp";
binmode $bmp;

my $index;
my $bmp;
my($x,$y)=(32,32);
my $picno=32;
my $pos;

while($index<@combinations || $index%1024!=1){
	if($y==32){
		if($bmp){
			close $bmp;
			`convert "$picno.bmp" "$picno.png"`;
			$picno++;
		}
		
		last if $index>=@combinations;
		
		open $bmp,">","$picno.bmp" or die "$! - $picno.bmp";
		
		print $bmp bmp_header(GLYPH_WIDTH*2*32,GLYPH_HEIGHT*32);
		$pos=tell $bmp;
		
		$x=$y=0;
	}
	
	if(($index+(188-94))%188==0){
		for(0..GLYPH_HEIGHT-1){
			seek $bmp,$pos+GLYPH_WIDTH*2*$x*4+GLYPH_WIDTH*2*32*4*(GLYPH_HEIGHT*(31-$y)+$_),0;
			
			print $bmp $glyph_data[0]->[$_],$glyph_data[0]->[$_];
		}
		$x=0,$y++ if ++$x==32;
	}
	
	my($l,$r)=@{ $combinations[$index<@combinations?$index:0] };
	for(0..GLYPH_HEIGHT-1){
		seek $bmp,$pos+GLYPH_WIDTH*2*$x*4+GLYPH_WIDTH*2*32*4*(GLYPH_HEIGHT*(31-$y)+$_),0;
		
		print $bmp $glyph_data[$l]->[$_],$glyph_data[$r]->[$_];
	}
	
	$x=0,$y++ if ++$x==32;
	$index++;
}

__DATA__

for my $x(0..$#charslist){
for my $y(0..$#charslist){
	my($l,$r)=@{ $combinations[$x+$y*@charslist] };
	my $ny=$#charslist-$y;
	
	for(0..GLYPH_HEIGHT-1){
		seek $bmp,$pos+GLYPH_WIDTH*2*$x*4+$w*2*4*(GLYPH_HEIGHT*$ny+$_),0;
		
		print $bmp $glyph_data[$l]->[$_],$glyph_data[$r]->[$_];
	}
}
}

close $bmp;

`convert "$filename-1.bmp" "$filename-1.png"`;


