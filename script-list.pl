use strict;
use Encode;

use utf8;

my($home);
BEGIN{($home)=$0=~/(.*)[\/\\].*/;$home||=".";}
use lib $home;

BEGIN{ require "utils.pl" }
my @groups=our @script_groups;

sub usage(){print <<HERE;exit;}
Usage: $0 SCRIPT-FILE
HERE

my $game=shift;
my $files=shift;

my %girls;

if($game eq "WS"){
	%girls=(
		"Ami and Mami"	=> 1,
		Iori			=> 1,
		Yukiho			=> 1,
	);
} elsif($game eq "PS"){
	%girls=(
		Haruka			=> 1,
		Makoto			=> 1,
		Yayoi			=> 1,
	);
} elsif($game eq "MM"){
	%girls=(
		Azusa			=> 1,
		Chihaya			=> 1,
		Ritsuko			=> 1,
	);
} else{
	usage
}

print <<HERE;

{| border="1" cellpadding="4" class="wikitable sortable" style="border-collapse:collapse;border:1px solid #AAAAAA;"
|-
!                               Script !! Status !!         Girl !! Other characters                                                                                 !! Comments
HERE

for my $file(sort{my($na)=$a=~/.*\D(\d+)/;my($nb)=$b=~/.*\D(\d+)/;$na<=>$nb} list $files){
	my %groups;
	my @lines;

	open my $in,"<","$file" or die "$file - $!";
	binmode $in,":utf8";

	for my $group(@groups){
		my($line)=lc eatline $in;
		die "Expecting line ``$group'', got ``$line'' in $file"
			unless "$group" eq $line;
		
		while($line=eatline $in,1){
			$line=~s/^\s*//;
			
			$groups{$group}||=[];
			push @{ $groups{$group} },$line;
		}
	}

	chomp,push @lines,$_ while defined($_=<$in>);

	close $in;
	
	my @names=@{ $groups{names} };
	my %names=map{$_=>1}@names;
	my %usage;
	my $total;

	for(@lines){
		next unless /# \[(.*)\]/;
		next unless $names{$1};
		next if $1 eq 'Protagonist';
		
		my $name=$1;
		
		$name="Ami and Mami" if $name=~/^[m\?]?[a\?]mi$/i;
		
		$usage{$name}++;
		$total++;
	}
	
	my @cast=sort{$usage{$b} <=> $usage{$a}} keys %usage;
	
	my $girl="";
	my($top,$runnerup)=grep{$girls{$_}} @cast;
	$girl=$top if $usage{$top}>$usage{$runnerup}*2;
	
#	$girls{$_} and $usage{$_}>$total*0.4 and $girl=$_,last foreach @cast;
	
	@cast=grep{$_ ne $girl}@cast if $girl;
	my @usage_cast=map{$_.sprintf " (%d%%)",$usage{$_}/$total*100}@cast;
	
	@usage_cast=(@usage_cast[0..4],"...") if @usage_cast>4;
	
	my($fileno)=$file=~/.*\D(\d+)/;
	printf <<HERE,"[[Idolmaster_SP:$game:$fileno|$fileno.txt]]","0%",$girl,join ", ",@usage_cast;
|-
| % 36s || % 6s || % 12s || % -96s ||
HERE
}

print <<HERE;
|}
HERE
