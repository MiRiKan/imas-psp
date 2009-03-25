# WRITTEN BY ANDREY OSENENKO.
# REDISTRIBUTION AND USE OF MY ART ARE PERMITTED PROVIDED THAT THE FOLLOWING CONDITIONS ARE MET:
# YOU MUST ATTRIBUTE !!
# DO NOT STEAL MY ART.

use strict;
use Encode;

use utf8;

my($home);
BEGIN{($home)=$0=~/(.*)[\/\\].*/;$home||=".";}
use lib $home;

BEGIN{ require "utils.pl" }

our $chars;
our $char_reg;
our $not_char_reg;

my %charcodes=charcodetable;

sub usage(){print <<HERE;exit;}
Uasge: $0 d INFILE OUTFILE
Uasge: $0 e INFILE OUTFILE
HERE

sub readcom($){
	my($h)=@_;
	
	read $h,my $byte,1 or return -1;
	die sprintf "%02x",ord $byte unless $byte eq "\x80";
	
	read $h,my $com,1 or die;
	$com=unpack "C",$com;
	
	my $res="";
	my($b,$last);
	while(read $h,$b,1){
		if($last eq "\x80"){
			my $no=unpack "C",$b;
			if($no<0x80){
				seek $h,-2,1;
				
				return ($com,$res);
			}
		}
		
		$res.=$last if defined $last;
		$last=$b;
	}
	
	$res.=$last if defined $last;
	return ($com,$res);
}

sub xunpack($$){
	my($mask,$text)=@_;
	
	my @res=unpack $mask,$text;
	
	my $no=0;
	while($mask=~/(\w)(\W*)/g){
		my($ch,$mod)=($1,$2);
		
		if($ch=~/a/){
			my $line=decode "sjis",$res[$no];
			
			$line=~s/\\/\\\\/g;
			$line=~s/\n/\\n/g;
			$line=~s/"/\\"/g;
			$line=~s/([\x00-\x1f])/"\\".(ord $1)/ge;
			
			$line=~s/^「//;
			$line=~s/」$//;
			
			$res[$no]=qq{"$line"};
		}
		
		$no++;
	}
	
	pop @res while $res[$#res] eq '""';
	
	@res
}

sub emit($@){
	my($mask,@list)=@_;
	
#	print "[",(map "{$_}",@list),"|",
#	pack $mask,@list;
#	print "]\n";

	my $res="";
	
	my $no=0;
	while($mask=~/(\w)(\W*)/g){
		my($ch,$mod)=($1,$2);
		
		if($ch=~/a/){
			my $line=$list[$no];
			$line=~s/^"(.*)"$/$1/;
			my $resline="";
			
			while($line=~/($char_reg*)($not_char_reg*)/g){
				my($ascii,$jis)=($1,$2);
				
				$ascii.=" " if (length $ascii)&0x01;
				
				$resline.=join "",map{$charcodes{$_} or die $_} $ascii=~/(..)/g;
				$resline.=encode "sjis",$jis;
			}
			
			$resline=~s/\\([123]?\d|.)/
				my $res=$1;
				
				if($res eq 'n')				{$res="\n"}
				elsif($res=~m!^[123]?\d$!)	{$res=chr $res}
				
				$res
			/ge;

			$list[$no]=$resline;
			
		}
		
		$no++;
	}
	
	pack $mask,@list;
}

use constant COM =>{
	"0f"	=> ["line1",				"a*"],
	"01"	=> ["line2",				"a*"],
	"10"	=> ["name",					"CCa*"],
	"05"	=> ["unk05",				"a*"],
	"04"	=> ["unk04",				"a*"],
	"06"	=> ["unk06",				"a*"],
	"02"	=> ["unk02",				"a*"],
};

my $com=COM;
my $comnames = {map {
	COM->{$_}->[0]=>$_
} keys %$com};

my $filename;

my $mode=shift or usage;

if($mode eq 'd'){
	open my $in,(($filename=shift) or usage) or die "$filename - $!";
	binmode $in;

	open my $out,">",(($filename=shift) or usage) or die "$filename - $!";
	binmode $out,":utf8";

#	local $/;
#	my $text=<$in>;

#	while($text=~/\x80([\x00-\x7f].*?)(?=\x80[\x00-\x7f]|$)/g){
	while(my($com,$text)=readcom $in){
		last if $com==-1;
		
		my $comid=sprintf "%02x",$com;
		
#		printf "%s [$text]\n",$comid;
		my $opts=(COM->{$comid} or [
			"com$comid","C*"
		]);

		print $out $opts->[0]," ",(join " ",xunpack $opts->[1],$text),"\n";
	}
} elsif($mode eq 'e'){
	open my $in,(($filename=shift) or usage) or die "$filename - $!";
	binmode $in,":utf8";

	open my $out,">",(($filename=shift) or usage) or die "$filename - $!";
	binmode $out;

	while(defined($_=<$in>)){
		s/\r?\n$//;
		
		next if /^#/;
		
		my($com,$args)=/([-\w\d]+)\s+(.*)/;
		$com or next;
		
		my(@args)=(length $args>200)?
			$args=~/(\d+|"[^"]*")(?: |$)/gs:
			$args=~/(\d+|"(?:(?:\\\\)*\\"|[^"])*")(?: |$)/gs;
		
#		print "$com => ";
		my($comno,$opts);
		if($comnames->{$com}){
			$comno=hex $comnames->{$com};
			$opts=COM->{$comnames->{$com}};
		} else{
			$opts=[$com,"C*"];
			$com=~s/^com// or die $com;
			$comno=hex $com;
		}
		
#-		printf "%02x $opts->[1] [@args]\n",$comno;
		print $out emit "CC".$opts->[1],0x80,$comno,@args;
	}
} else{
	usage;
}