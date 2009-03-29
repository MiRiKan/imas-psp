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

mkdir "index";

my $spita_files;
sub spita($;@){
	my($filename)=shift;
	
	my $h=$spita_files->{$filename};
	
	if(not $h){
		open $h,">","$filename" or die "$! - $filename";
		binmode $h,":utf8";
		
		$spita_files->{$filename}=$h;
	}
	
	print $h @_;
}
sub numcmp($$){my($na)=$_[0]=~/.*\D(\d+)/;my($nb)=$_[1]=~/.*\D(\d+)/;$na<=>$nb}

my %girls;

my @games=(
	{
		name		=> "Perfet Sun",
		dir			=> "YUMFILE_1",
		girls		=> [qw/Haruka Makoto Yayoi/],
		shortcut	=> "PS",
	},
	{
		name		=> "Wandering Star",
		dir			=> "YUMFILE_2",
		girls		=> ["Ami and Mami","Iori","Yukiho"],
		shortcut	=> "WS",
	},
	{
		name		=> "Missing Moon",
		dir			=> "YUMFILE_3",
		girls		=> [qw/Azusa Chihaya Ritsuko/],
		shortcut	=> "MM",
	},
);



for(@games){
	spita "index/$_.txt",<<HERE foreach @{ $_->{girls} },$_->{shortcut};
{| border="1" cellpadding="4" class="wikitable sortable" style="border-collapse:collapse;border:1px solid #AAAAAA;"
|-
!                               Script !! Status !! Other characters
!! Comments
HERE

	spita "index/$_->{shortcut}.mail.txt",<<HERE;
{| border="1" cellpadding="4" class="wikitable sortable" style="border-collapse:collapse;border:1px solid #AAAAAA;"
|-
!                                 File !! Status !! Comments
HERE
	
	$_->{girlslist}={map{$_=>1} @{ $_->{girls} }};
}

for my $game(@games){
	
	for my $file(sort{numcmp $a,$b} list "$game->{dir}/mail.txt/*.mail.txt"){
		my($fileno)=$file=~/.*\D(\d+)/;
		
		unless(-e (my $utffile="$game->{dir}/mail.txt/$fileno.mail.utf8.txt")){
			my $text=slurp $file,":latin1"; # damn binmode
			$text=decode "sjis",$text;
			spita $utffile,$text;
		}
		
		spita "index/$game->{shortcut}.mail.txt",sprintf <<HERE,"[[Idolmaster_SP:$game->{shortcut}:M$fileno|$fileno.mail.txt]]","0%","";
|-
| % 36s || % 6s || %s
HERE
	}

	for my $file(sort{numcmp $a,$b} list "$game->{dir}/script/*.txt"){
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
		my($top,$runnerup)=grep{$game->{girlslist}->{$_}} @cast;
		$girl=$top if $usage{$top}>$usage{$runnerup}*2;
		
		@cast=grep{$_ ne $girl}@cast if $girl;
		my @usage_cast=map{$_.sprintf " (%d%%)",$usage{$_}/$total*100}@cast;
		
		@usage_cast=(@usage_cast[0..4],"...") if @usage_cast>4;
		
		my($filename)=($girl or $game->{shortcut});
		
		my($fileno)=$file=~/.*\D(\d+)/;
		spita "index/$filename.txt",sprintf <<HERE,"[[Idolmaster_SP:$game->{shortcut}:$fileno|$fileno.txt]]","0%",join ", ",@usage_cast;
|-
| % 36s || % 6s || %s
|| %s
HERE
	}
}

for(@games){
	spita "index/$_.txt",<<HERE foreach @{ $_->{girls} },$_->{shortcut};
|}
HERE

	spita "index/$_->{shortcut}.mail.txt",<<HERE;
|}
HERE
}
