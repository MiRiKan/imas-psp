use strict;
use bytes;
use Data::Dumper;

my($home);
BEGIN{($home)=$0=~/(.*)[\/\\].*/;$home||=".";}
use lib $home;

BEGIN{ require "utils.pl" }
BEGIN{ require "alphabet.pl" }
our($single_chars,$single_chars_list,$single_chars_hash,$doubles_list,$doubles_hash,$doubles_codes,$doubles_table);

$|++;

sub usage(){die sprintf <<HERE,length $single_chars}
Usage:
	$0 PNG-FILE
Creates font for game from a .png file. Files 30.png - 38.png extracted from
YUM archive and converted with pom-unpack.pl must present in current directory.
Your picture must have height of 16 and have %d characters in it of width 8.
Characters should be (disregard first and last square brackets): 
[$single_chars]
HERE

my $filename=shift or usage;

my $font=read_picture($filename,8,16);

@{ $font->[0] } == @$single_chars_list or die "Need picture with ".(scalar @$single_chars_list)." characters, $filename has ".scalar @{ $font->[0] };

my $no=30;
my $voff=0;
my $data;

sub flush(;$){
	my($last)=@_;
	if($data){
		write_picture("$no.png",$data);
		$no++;
	}
	$data=(eval{read_picture("$no.png",16,16)} or "");
	
	die unless $last or $data;
}

flush;

for my $row(@$doubles_table){
	next unless $row;

	for(0..@$row-1){
		my $sym=$row->[$_];
		next unless defined $sym;
		
		my($lc,$rc)=map{$single_chars_hash->{$_}} $sym=~/(.)(.)/;
		
		$data->[$voff]->[$_]=chunk_hor_join($font->[0]->[$lc],$font->[0]->[$rc]);
	}

} continue{
	$voff++;
	flush,$voff=0 if $voff==32;
}

flush 1;
