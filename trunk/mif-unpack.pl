use strict;
use bytes;

my($home);
BEGIN{($home)=$0=~/(.*)[\/\\].*/;$home||=".";}
use lib $home;

BEGIN{ require "utils.pl" }
BEGIN{ require "mif-common.pl" }
our(@startpoints);

$|++;

sub usage(){die <<HERE}
Usage:
	$0 MIF-FILE
	$0 NUMBER
Converts a .mif file to PNG you may edit. If you specify NUMBER as
argument, progam will work with ../mif/NUMBER.mif.
HERE

my $filename=shift or usage;
my $resfile;
my $miffile;

if($filename=~/(.*)\.mif$/){
	$miffile=$filename;
	($resfile)=$filename=~/^(.*)\.(?:pom|mif)$/;
	$resfile.=".mif";
} elsif ($filename=~m!^(\d+)$!){
	$miffile="../mif/$1.mif";
	$resfile="$1.mif";
} else{
	usage
}

my($pw,$ph,@rects)=read_mif $miffile;

open my $bmp,"+>","$resfile.bmp" or die "$! - $resfile.bmp";
binmode $bmp;

print $bmp bmp_header $pw,$ph;
my $bmpstart=tell $bmp;

sub bmp_rect($$$$$$){
	my($h,$color,$x1,$y1,$x2,$y2)=@_;
	
	for my $y($y1..$y2){
		seek $h,$bmpstart+($ph-$y-1)*4*$pw+$x1*4,0;
	
		for($x1..$x2){
			print $h pack "I",$color;
		}
	}
}
sub bmp_hline($$$$$){
	my($h,$color,$x1,$x2,$y)=@_;
	
	bmp_rect($h,$color,$x1,$y,$x2,$y)
}
sub bmp_vline($$$$$){
	my($h,$color,$x,$y1,$y2)=@_;
	
	bmp_rect($h,$color,$x,$y1,$x,$y2)
}
sub bmp_is_empty($$$$$){
	my($h,$x1,$y1,$x2,$y2)=@_;
	for my $y($y1..$y2){
		seek $h,$bmpstart+($ph-$y-1)*4*$pw+$x1*4,0;
		
		for($x1..$x2){
			my $color=consume "I",$h;
			return 0 if $color!=0xff000000;
		}
	}
	
	return 1;
}

bmp_rect $bmp,0xff000000,0,0,$pw-1,$ph-1;

my %map;

for(sort{$rects[$a]->[2]*$rects[$a]->[3] <=> $rects[$b]->[2]*$rects[$b]->[3]} 0..$#rects){
	my($x,$y,$w,$h,$a,$b)=@{ $rects[$_] };
	my $key="$x|$y";

	my $linew=min int($w/6)+1,4;
	my $lineh=min int($h/6)+1,4;
	
	my $len=min $linew,$lineh;
	
	my $x1=$x;
	my $y1=$y;
	my $x2=$x+$w-1;
	my $y2=$y+$h-1;
	
	if(not bmp_is_empty $bmp,$x1,$y1,$x2,$y2){
		print "Skipping rect at $x1,$y1 $x2,$y2\n"
			unless $map{$key};
		next;
	}
	
	$map{$key}=$_;

	my $sp=$startpoints[$_%@startpoints];
	my $colorv=$sp->[0]-(int($_/@startpoints)<<$sp->[1]);
	
	bmp_rect $bmp,$colorv|(0xa0<<24),$x1,$y1,$x2,$y2;
	
	bmp_hline $bmp,$colorv,$x1,$x1+$len,$y1;
	bmp_vline $bmp,$colorv,$x1,$y1,$y1+$len;

	bmp_hline $bmp,$colorv,$x2-$len,$x2,$y1;
	bmp_vline $bmp,$colorv,$x2,$y1,$y1+$len;

	bmp_hline $bmp,$colorv,$x1,$x1+$len,$y2;
	bmp_vline $bmp,$colorv,$x1,$y2-$len,$y2;

	bmp_hline $bmp,$colorv,$x2-$len,$x2,$y2;
	bmp_vline $bmp,$colorv,$x2,$y2-$len,$y2;
}

close $bmp;

`convert $resfile.bmp $resfile.png`;
unlink "$resfile.bmp" if -e "$resfile.png";
























