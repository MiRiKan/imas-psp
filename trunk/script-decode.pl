use strict;
use Encode;

use utf8;

my($home);
BEGIN{($home)=$0=~/(.*)[\/\\].*/;$home||=".";}
use lib $home;

BEGIN{ require "utils.pl" }
my $commands=our $script_commands;
my @groups=our @script_groups;


sub usage(){print <<HERE;exit;}
Usage: $0 SCRIPT-FILE
HERE

sub readcom($){
	my($h)=@_;
	
	return -1 if eof $h;
	
	my($escape,$command)=consume "CC",$h;
	
	die sprintf "%02x",$escape unless $escape==0x80;
	
	my $text="";
	while(read $h,my $word,2){
		my($l,$r)=unpack "CC",$word;
		seek $h,-2,1 and last if $l==0x80 and $r<0x80;
		
		$text.=$word;
	}
	
	return ($command,$text);
}

sub xunpack($$){
	my($mask,$text)=@_;
	
	my @res=unpack $mask,$text;
	
	my $no=0;
	while($mask=~/(\w)(\W*)/g){
		my($ch,$mod)=($1,$2);
		
		$res[$no]=decode "sjis",$res[$no]
			if $res[$no] and $ch eq 'a';
		
		$no++;
	}
	
	@res
}

sub parse($){
	my($filename)=@_;
	
	my @tree;

	open my $h,$filename or die "$filename - $!";
	binmode $h;
	
	while(my($com,$text)=readcom $h){
		last if $com==-1;
		
		my $command_id=sprintf "%02x",$com;
		
		my $info=$commands->{$command_id} || {name => "com$command_id"};
		my $line=$info->{mode} eq 'line';
		
		my $mask=$info->{mask}.($line?"a*":"C*");
		
		my $hash={
			name		=> $info->{name},
			group		=> "$info->{group}",
			code		=> $com,
			comment		=> "$info->{comment}",
			multiline	=> $info->{multiline}?1:0,
			data		=> [xunpack $mask,$text],
		};
		
		$hash->{line}=pop @{ $hash->{data} }
			if $line;
		
		push @tree,$hash;
	}
	
	close $h;
	
	\@tree
}

my $filename=shift or usage;

die "File $filename must have .script extension"
	unless $filename=~/(.*)\.script$/;

my $basename=$1;

my $tree=parse $filename;

my %groups;
my %groups_done;
my @text;
my @code;

my $last;
for(@{ $tree }){
	my $code=$_->{code};
	my $group=$_->{group};
	
	my $line=$_->{line};
	$line=$last->{line}.$line if $last->{multiline};
	
	my $pushing_line=($line and not $_->{multiline} and not $group);
	
	die "Unexpected command $_->{name} after $last->{name}"
		if $last->{multiline} and $code!=1;
	
	my(@codeline)=($_->{name},@{ $_->{data} });
	
	if($pushing_line){
		if($_->{comment} and not $_->{multiline}){
			$line=$_->{comment}.$line;
		} elsif($last->{comment} and $last->{multiline}){
			$line=$last->{comment}.$line;
		}
		
		push @codeline,"<shift>";
		push @text,"$line";
	} elsif($group){
		$groups{$group}||=[];
		
		push @{ $groups{$group} },$line
			unless $groups_done{group}->{$line};
		
		$groups_done{group}->{$line}||=
			scalar @{ $groups{$group} };
		
		push @codeline,"<$group:$groups_done{group}->{$line}>";
		
		push @text,"# $line" if $group eq 'names';
	}
	
	push @code,join " ",@codeline;
} continue{
	$last=$_;
}

open my $out,">","$basename.txt" or die "$basename.txt - $!";
binmode $out,":utf8";
for(@groups){
	next unless $groups{$_};
	
	my @list=@{ $groups{$_} };
	print $out "!",(ucfirst $_),":\n",(map{"  $_\n"}@list),"\n";
}
print $out "$_\n" foreach @text;
close $out;


open my $out,">","$basename.src" or die "$basename.src - $!";
print $out "$_\n" foreach @code;
close $out;


