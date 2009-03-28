use strict;
use bytes;
use Getopt::Long;
use Term::ANSIColor;
eval{require Win32::Console::ANSI};

$|++;

my($home);
BEGIN{($home)=$0=~/(.*)[\/\\].*/;$home||=".";}
use lib $home;

BEGIN{ require "utils.pl" }

sub usage(){print <<HERE;exit;}
Usage: $0 PATTERN [FILE]...
Search for PATTERN in each FILE.
This program differs from that other grep I have installed on my machine
in a way that it outputs reults in hex and allows you to search for binary
characters you might not normally be able to input (at least I can't with
my shitty windows terminal) by using escape sequences: \x00 or \0
  -r, --recursive       process files inside subdirectories
  -m, --match           PATTERN is a perl regular expression
  -h, --hex             PATTERN is a whiespace separated list of hex numbers
                        (for example, "a1 b2 c3" is same as "\xa1\xb2\xc3"
                        without the flag)
HERE

my $regmode=0;
my $recursive=0;
my $hexline=0;

GetOptions(
	"recursive"	=> \$recursive,
	"match"		=> \$regmode,
	"hex"		=> \$hexline,
);

my $pattern=(shift or usage);
my @files=list @ARGV;

if($hexline){
	$pattern=join "",map{chr hex $_}split /\s+/,$pattern;
} else{
	$pattern=~s!\\(.)(?:(.)(.)?)?!
		my($m,$n,$p)=($1,$2,$3);
		my $res;
		
		if($m eq 'x' and $n=~/[0-9a-fA-F]/ and $p=~/[0-9a-fA-F]/)
			{chr hex "$n$p"}
		elsif("$m$n$p"=~/^(\d+)(.*)/)
			{(chr $1).$2}
		else
			{"\\$m$n$p"}
	!ge;
}

my $regexp=qr/$pattern/;

sub ansitext($){map{(ord $_>=0x1f and ord $_<=0x7e)?$_:'.'} split //,$_[0]}
sub hextext($){map{sprintf "%02x",ord $_} split //,$_[0]}

sub hexdump($$$){
	my($l,$m,$r)=@_;
	
	my $line=colored join("",ansitext $m),'bold red';
	my $hexline=colored join(" ",hextext $m),'bold red';
	
	my $length=6;
	my $lpad=$length-length $l;
	my $rpad=$length-length $r;
	
	$line=join "",
		(map " ",1..$lpad),"|",(ansitext $l),
		$line,
		(ansitext $r),(map " ",1..$rpad),"|";
	$hexline=join " ",
		(map "  ",1..$lpad),(hextext $l),
		$hexline,
		(hextext $r),(map "  ",1..$rpad);

	"$hexline $line"
}

while(@files){
	my $file=shift @files;
	
	if(-d $file){
		push @files,list "$file/*" if $recursive;
		next;
	}
	
	open my $h,$file or warn "$! - $file\n" and next;
	binmode $h;
	
	local $/;
	my $data=<$h>;
	
	if($regmode==0 and (my $pos=index $data,$pattern)!=-1){
		print "$file: ",(hexdump substr($data,$pos-6,6),$pattern,substr($data,$pos+length $pattern,6)),"\n";
	} elsif($regmode==1 and $data=~/(.{0,6})($regexp)(.{0,6})/g){
		print "$file: ",(hexdump $1,$2,$3),"\n";
	}
	
	close $h;
}





