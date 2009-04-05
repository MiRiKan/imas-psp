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

my(%map,%aliases);
for(sort{$rects[$a]->[2]*$rects[$a]->[3] <=> $rects[$b]->[2]*$rects[$b]->[3]} 0..$#rects){
	my($x,$y,$w,$h,$a,$b)=@{ $rects[$_] };
	my $key="$x|$y";
	if(defined $map{$key}){
		$aliases{$key}=$map{$key};
	} else{
		$map{$key}=$_;
	}
}

my @new_rects;

die "$resfile.png - Not found"
	unless -f "$resfile.png";

`convert $resfile.png $resfile.bmp`;
die unless -f "$resfile.bmp";

open my $bmp,"$resfile.bmp" or die "$resfile.bmp - $!";
binmode $bmp;

my(undef,$w,$h)=consume_bmp_header $bmp;

my %colors=map{
	my $sp=$startpoints[$_%@startpoints];
	my $color=$sp->[0]-(int($_/@startpoints)<<$sp->[1]);
	
	(pack "CCC",
			(($color>> 0)&0xff),
			(($color>> 8)&0xff),
			(($color>>16)&0xff))
		=> $_
}0..$#rects;

for my $y(reverse 0..$h-1){
	for my $x(0..$w-1){
		my($c,$a)=consume "a3C",$bmp;
		
		if($a==0){
			my $color=$colors{$c};
			die "$filename: Unexpected color at $x,$y" unless defined $color;
			
			$new_rects[$color]||=[0xffff,0xffff,-1,-1];
			$new_rects[$color]->[0]=min $new_rects[$color]->[0],$x;
			$new_rects[$color]->[1]=min $new_rects[$color]->[1],$y;
			$new_rects[$color]->[2]=max $new_rects[$color]->[2],$x;
			$new_rects[$color]->[3]=max $new_rects[$color]->[3],$y;
		}
	}
}

@rects=map{
	my $new=$new_rects[$_];
	my $old=$rects[$_];
	my $key="$old->[0]|$old->[1]";
	my $alias=$new_rects[$aliases{$key}];
	
	if(defined $aliases{$key} and $aliases{$key}!=$_){
		print "mapping $_:($old->[0],$old->[1]) -> ($alias->[0],$alias->[1])\n";
		[$alias->[0],$alias->[1],$old->[2],$old->[3],$old->[4],$old->[5]]
	} elsif($new){
		[$new->[0],$new->[1],$new->[2]-$new->[0]+1,$new->[3]-$new->[1]+1,$old->[4],$old->[5]]
	} else{
		print "leaving $_:($old->[0],$old->[1]) as it was\n";
		[@$old]
	}
} 0..$#new_rects;

close $bmp;
unlink "$resfile.bmp";

write_mif $miffile,@rects;
