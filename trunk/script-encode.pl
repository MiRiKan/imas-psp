use strict;
use Encode;

use utf8;

my($home);
BEGIN{($home)=$0=~/(.*)[\/\\].*/;$home||=".";}
use lib $home;

BEGIN{ require "utils.pl" }
my $commands=our $script_commands;
my @groups=our @script_groups;

my $commands_names={map{
	$commands->{$_}->{name}=>{code=>hex $_,%{ $commands->{$_} }}
} keys %$commands};

sub usage(){print <<HERE;exit;}
Usage: $0 SCRIPT-FILE
HERE

my %groups;
my @lines;

sub xpack($@){
	my($mask,@list)=@_;
	
	my $res="";
	
	my $no=0;
	while($mask=~/(\w)(\W*)/g){
		my($ch,$mod)=($1,$2);
		
		if($ch eq 'a' and $list[$no]){
			my $line=$list[$no];
			
			if($line eq '<shift>'){
				$line=shift @lines;
			} elsif($line=~/^<(\w+):(\d+)>$/){
				my($group,$no)=($1,$2);
				
				$line=$groups{$group}->[$no-1];
			} else{
				die "Unknown argument: $line";
			}
			
#			my $res="";
#			while($line=~/(?:\\x(..))?([^\\]*)/g){
#				$res.=chr hex $1 if $1;
#				$res.=encode_doubletile $2 if $2;
#			}
			
			$list[$no]=encode_doubletile $line;
		}
		
		$no++;
	}
	
	pack $mask,@list;
}

sub parse($){
	my($filename)=@_;
	local $_;
	
	my @tree;

	open my $h,$filename or die "$filename - $!";
	
	while($_=<$h>){
		s/#.*//;
		s/^\s+//;
		s/\s+$//;
		
		next if (length $_)==0;
		
		my($name,@args)=split / /;
		
		my $info=$commands_names->{$name};
		
		$info||={
			code	=> hex $1
		} if $name=~/^com(..)$/;
		
		die "Unknown command: $name" unless $info;
		
		push @tree,{
			data		=> [@args],
			
			%$info
		};
	}
	
	close $h;
	
	\@tree
}

sub eatline($;$){
	my($h,$stop_on_whitespace)=@_;
	local($_);
	
	while(0==length $_){
		return "" if eof $h;
		$_=<$h>;
		chomp;
		
		return "" if $stop_on_whitespace and 0==length $_;
		
		return $1 if /^!(.*)/;
		s/^[^:]*: //;
		s/#.*//;
		s/\s+$//;
	}
	
	$_
}

my $filename=shift or usage;

die "File $filename must have .script extension"
	unless $filename=~/(.*)\.script$/;

my $basename=$1;

my $tree=parse "$basename.src";

open my $in,"<","$basename.txt" or die "$basename.txt - $!";
binmode $in,":utf8";

for my $group(@groups){
	my($line)=lc eatline $in;
	die "Expecting line ``$group:'', got ``$line''"
		unless "$group:" eq $line;
	
	while($line=eatline $in,1){
		$line=~s/^\s*//;
		
		$groups{$group}||=[];
		push @{ $groups{$group} },$line;
	}
}

push @lines,$_ while $_=eatline $in;

close $in;

open my $h,">","$filename" or die "$filename - $!";
binmode $h;

for(@{ $tree }){
	my $code=$_->{code};
	
	print $h pack "CC",0x80,$code;

	my $linemode=$_->{mode} eq 'line';
	my $mask=$_->{mask}.($linemode?"a*":"C*");
	
	print $h xpack $mask,@{ $_->{data} }
}

close $h;