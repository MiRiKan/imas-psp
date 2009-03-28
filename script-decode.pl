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
Decodes a script to human readable from. Will produce two files, .src with
script logic and .txt with text.
HERE

my %translations=(
	あずさ			=> "Azusa",
	おじさん			=> "Old man",
	やよい			=> "Yayoi",
	アナウンス			=> "Announcement",
	ゴシップ記者		=> "Reporter",
	スタイリスト			=> "Stylist",
	主人公			=> "Protagonist",
	亜美				=> "Ami",
	伊織				=> "Iori",
	千早				=> "Chihaya",
	名無しさん			=> "Anonymous",
	周りのアイドル		=> "Idols",
	審査員			=> "Judges",
	小鳥				=> "Kotori",
	律子				=> "Ritsuko",
	敏腕記者			=> "Ace Reporter",
	新社長			=> "New President",
	春香				=> "Haruka",
	"春香・響"		=> "Haruka's voice",
	真				=> "Makoto",
	"真・響"			=> "Makoto's voice",
	真美				=> "Mami",
	社長				=> "President",
	美希				=> "Miki",
	記者				=> "Reporter",
	貴音				=> "Takane",
	雪歩				=> "Yukiho",
	響				=> "Echo",
	黒井社長			=> "President Kuroi",
	"？？？"			=> "???",
	
	番組スタッフ		=> "Staff",
	スタッフ			=> "Staff",
	"亜美・真美"		=> "Ami and Mami",
	"▼美"			=> "??mi",
	犬				=> "Dog",
	警備員			=> "Guard",
	管理人			=> "Manager",
	ファン				=> "Fan",
	
	女				=> "Woman",
	司会者			=> "Chairman",
	ＡＤ				=> "Ad",
	"千早・美希"		=> "Chihaya and Miki",
	"律子・美希"		=> "Ritsuko and Miki",
	女の子			=> "Girl",
	友達Ａ			=> "Friend A",
	友達Ｂ			=> "Friend B",
	女の子Ａ			=> "Girl A",
	女の子Ｂ			=> "Girl B",
	編成部長			=> "Director",
	編成部長の弟		=> "Director's brother",
	電話の声			=> "Voice",

);

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
			continuation=> "$info->{continuation}",
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
for(0..@{ $tree }-1){
	my $next=$tree->[$_+1];
	$_=$tree->[$_];
	
	my $code=$_->{code};
	my $group=$_->{group};
	
	my $line=$_->{line};
	$line.=$next->{line},$next->{line}="" if $_->{multiline} and $next->{continuation};
	
	my $pushing_line=($line and not $group);
	
	my(@codeline)=($_->{name},@{ $_->{data} });
	
	my $tlline=($translations{$line} or $line);
	
	if($pushing_line){
		$line=$_->{comment}.$line if($_->{comment});
		
		push @codeline,"<shift> # $tlline";
		push @text,"# $line";
		push @text,"$line";
	} elsif($group){
		$groups{$group}||=[];
		
		push @{ $groups{$group} },$tlline
			unless $groups_done{group}->{$line};
		
		$groups_done{group}->{$line}||=
			scalar @{ $groups{$group} };
		
		push @codeline,"<$group:$groups_done{group}->{$line}>  # $tlline";
		
		if($group eq 'names'){
			push @text,"";
			push @text,"# [$tlline]";
		}
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
	print $out (ucfirst $_),"\n",(map{"  $_\n"}@list),"\n";
}
print $out "$_\n" foreach @text;
close $out;


open my $out,">","$basename.src" or die "$basename.src - $!";
binmode $out,":utf8";
print $out "$_\n" foreach @code;
close $out;


