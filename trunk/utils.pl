use strict;
use Encode;
use Carp qw/croak/;

use utf8;

use constant DATABASE_ADDRESS	=> 'localhost';
use constant DATABASE_USERNAME	=> 'root';
use constant DATABASE_PASSWORD	=> 'qwerty';
use constant DATABASE_DATABASE	=> 'idolmaster';

BEGIN{ require "alphabet.pl" }
our($single_chars,$single_chars_list,$single_chars_hash,$doubles_list,$doubles_hash,$doubles_codes,$doubles_table);

sub mtime($){(stat $_[0])[9] or 0}

sub valid_sjis($){
	my($text)=@_;
	
	my $pos=0;
	my $length=length $text;
	while($pos<$length){
		my $first=substr $text,$pos++,1;
		next if $first=~/[\r\n\x20-\x7e\xa1-\xdf]/;
		return 0 unless $first=~/[\x81-\x9f\xe0-\xef]/;
		
		my $second=substr $text,$pos++,1;
		return 0 unless $second=~/[\x40-\x7e\x80-\xfc]/;
	}
	
	1
}

my $consume_cache;
sub consume($$){
	my($mask,$handle)=@_;
	
	my $length=
		$consume_cache->{$mask}||=length pack $mask,"";
	
	read $handle,my $buffer,$length;
	
	unpack $mask,$buffer;
}

sub bmp_header($$){
	my($width,$height)=@_;
	
	my $res="";
	
	$res.=	pack "a2ISSI","BM",$width*$height*4+0x8a,0,0,0x8a;
	$res.=	pack "I3S2I6",0x7c,$width,$height,1,32,3,$width*$height*4,2835,2835,0,0;
	$res.=	pack "C*",
		0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00,
		0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF,
		0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x56, 0xB8, 0x1E, 0xFC,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x66, 0x66, 0x66, 0xFC, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x63, 0xF8, 0x28, 0xFF,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00;
	
	$res
}

sub consume_bmp_header($){
	my($h)=@_;
	
	my($head,$bmp_size,undef,undef,$bmp_offset,undef,$bmp_w,$bmp_h)=consume "a2ISSII3",$h;
	die "Not a BMP file: $head" unless $head eq 'BM';
	
	seek $h,$bmp_offset,0;
	
	$bmp_offset,$bmp_w,$bmp_h
}

sub read_picture($$$){
	my($filename,$w,$h)=@_;
	
	die "File $filename doesn't exist"
		unless -e "$filename";

	`convert "$filename" "$filename.bmp"`;
	-e "$filename.bmp" or die;

	open my $bmp,"<","$filename.bmp" or die "$! - $filename.bmp";
	binmode $bmp;
	
	my($start,$pw,$ph)=consume_bmp_header $bmp;
	
	die "Wrong width: $pw is not divisable by $w" unless $pw % $w==0;
	die "Wrong height: $ph is not divisable by $h" unless $ph % $h==0;
	
	my $xc=$pw/$w;
	my $yc=$ph/$h;
	
	my $pitch=$pw*4;
	
	my $glyph_data=
	[map{
		my $row=$_;
		[map{
			my $col=$_;
			my $start=$start+$w*$col*4+$pitch*$h*$row;
			[map{
				seek $bmp,$start+$pitch*$_,0;
				read $bmp,my $data,$w*4;
			
				$data
			} 0..$h-1]
		} 0..$xc-1]
	}reverse (0..$yc-1)];

	close $bmp;
	
	unlink "$filename.bmp";
	
	$glyph_data
}

sub write_picture($$){
	my($filename,$data)=@_;
	
	print "$filename\n";
	
	open my $bmp,">","$filename.bmp" or die "$! - $filename.bmp";
	binmode $bmp;
	
	my $xc=@{ $data->[0] };
	my $yc=@$data;
	my $h=@{ $data->[0]->[0] };
	my $w=(length $data->[0]->[0]->[0])/4;
	
	my $pitch=$xc*$w*4;
	
	print $bmp bmp_header($w*$xc,$h*$yc);
	my $start=tell $bmp;
	
	for my $y(reverse (0..$yc-1)){
		for my $x(0..$xc-1){
			my $pic=$data->[$yc-$y-1]->[$x];
			my $start=$start+$w*$x*4+$pitch*$y*$h;
			for(0..$h-1){
				seek $bmp,$start+$pitch*$_,0;
				print $bmp $pic->[$_];
			}
		}
	}
	
	close $bmp;
	
	unlink "$filename" or die;
	`convert "$filename.bmp" "$filename"`;
	-e "$filename" or die;

	unlink "$filename.bmp";
}

sub chunk_hor_join($$){
	my($left,$right)=@_;
	
	[map{$left->[$_].$right->[$_]}0..scalar @$left-1]
}

sub sjis($$){
	my($j1,$j2)=@_;
	
	die "$j1 $j2" if $j1<33 or $j2<33 or $j1>126 or $j2>126;
	
	my $s1=int(($j1+1)/2)+($j1<=94?112:176);
	my $s2=$j2+($j1&0x01?31+($j2>=96?1:0):126);
	
	$s1,$s2
}

my $replacements={
	' '	=> '　',
	'!'	=> '！',
	'"'	=> '″',
	'#'	=> '＃',
	'$'	=> '＄',
	'%'	=> '％',
	'&'	=> '＆',
	'\''=> '′',
	'('	=> '（',
	')'	=> '）',
	'*'	=> '＊',
	'+'	=> '＋',
	','	=> '，',
	'-'	=> '‐',
	'.'	=> '．',
	'/'	=> '／',
	'0'	=> '０',
	'1'	=> '１',
	'2'	=> '２',
	'3'	=> '３',
	'4'	=> '４',
	'5'	=> '５',
	'6'	=> '６',
	'7'	=> '７',
	'8'	=> '８',
	'9'	=> '９',
	':'	=> '：',
	';'	=> '；',
	'<'	=> '＜',
	'='	=> '＝',
	'>'	=> '＞',
	'?'	=> '？',
	'A'	=> 'Ａ',
	'B'	=> 'Ｂ',
	'C'	=> 'Ｃ',
	'D'	=> 'Ｄ',
	'E'	=> 'Ｅ',
	'F'	=> 'Ｆ',
	'G'	=> 'Ｇ',
	'H'	=> 'Ｈ',
	'I'	=> 'Ｉ',
	'J'	=> 'Ｊ',
	'K'	=> 'Ｋ',
	'L'	=> 'Ｌ',
	'M'	=> 'Ｍ',
	'N'	=> 'Ｎ',
	'O'	=> 'Ｏ',
	'P'	=> 'Ｐ',
	'Q'	=> 'Ｑ',
	'R'	=> 'Ｒ',
	'S'	=> 'Ｓ',
	'T'	=> 'Ｔ',
	'U'	=> 'Ｕ',
	'V'	=> 'Ｖ',
	'W'	=> 'Ｗ',
	'X'	=> 'Ｘ',
	'Y'	=> 'Ｙ',
	'Z'	=> 'Ｚ',
	'['	=> '［',
	'\\'=> '＼',
	']'	=> '］',
	'^'	=> '＾',
	'_'	=> '＿',
	'a'	=> 'ａ',
	'b'	=> 'ｂ',
	'c'	=> 'ｃ',
	'd'	=> 'ｄ',
	'e'	=> 'ｅ',
	'f'	=> 'ｆ',
	'g'	=> 'ｇ',
	'h'	=> 'ｈ',
	'i'	=> 'ｉ',
	'j'	=> 'ｊ',
	'k'	=> 'ｋ',
	'l'	=> 'ｌ',
	'm'	=> 'ｍ',
	'n'	=> 'ｎ',
	'o'	=> 'ｏ',
	'p'	=> 'ｐ',
	'q'	=> 'ｑ',
	'r'	=> 'ｒ',
	's'	=> 'ｓ',
	't'	=> 'ｔ',
	'u'	=> 'ｕ',
	'v'	=> 'ｖ',
	'w'	=> 'ｗ',
	'x'	=> 'ｘ',
	'y'	=> 'ｙ',
	'z'	=> 'ｚ',
	'{'	=> '｛',
	'|'	=> '｜',
	'}'	=> '｝',
	'~'	=> '〜',
};

sub encode_doubletile($){
	my($line)=@_;
	
	$line.="";
	
	my $pos=0;
	my $res="";
	my $return_point=0;
	my $insert_point=0;
	my $return_res="";
	
	while($pos<length $line){
		my($ll,$l,$r,$rr)=map{substr $line,$pos+$_,1}-1,-0,1,2;
		$r=' ' if $r eq '';
		
		my $seq="$l$r";
		my $have_prev=defined $doubles_hash->{"$ll$l"};
		
		$return_point=-1
			if $pos>1 and not $have_prev;
		
		if($l eq ' '){
			$return_point=$pos;
			$insert_point=$pos;
			$return_res=$res;
		} elsif($r eq ' '){
			$return_point=$pos;
			$insert_point=$pos+1;
			$return_res=$res;
		}
		
		if(defined $doubles_hash->{$seq}){
			$res.=pack "n",$doubles_codes->{$seq};
			$pos+=2;
		} else{
			if($ll and $have_prev and $doubles_hash->{"$l "} and $return_point!=-1){
				$pos=$return_point;
				$res=$return_res;
				substr $line,$insert_point,0,' ';
				redo;
			}
			
			$l=$replacements->{$l} if $replacements->{$l};
			my $lj=encode "sjis",$l;
			
			if(2!=length $lj and $lj ne "\n"){
				die "Unexpected character: ``$l'' (".(ord $l).")"
			}
			
			$res.=$lj;
			
			$pos++;
			$return_point=-1;
		}
	}
	
	$res
}

sub encode_doubletile_control($){
	my($line)=@_;
	
	join "",map{
		(/^[%&]/?
			encode_utf8($_): # ugh
			encode_doubletile $_);
	} $line=~/(\%\d*[a-z]|\&[a-z]|[^%&]+)/g
}

our $script_commands={
	"00"	=> {
		name	=> "display",
		mode	=> "line",
	},
	"01"	=> {
		name			=> "line2",
		mode			=> "line",
		continuation	=> "1",
	},
	"02"	=> {
		name	=> "unk02",
		mode	=> "line",
	},
	"04"	=> {
		name		=> "choice1",
		mode		=> "line",
		comment		=> "Choice: ",
		multiline	=> 1,
	},
	"05"	=> {
		name		=> "choice2",
		mode		=> "line",
		comment		=> "Choice: ",
		multiline	=> 1,
	},
	"06"	=> {
		name		=> "choice3",
		mode		=> "line",
		comment		=> "Choice: ",
		multiline	=> 1,
	},
	"0a"	=> {
		name		=> "location",
		mask		=> "n",
		comment		=> "Label: ",
	},
	"0f"	=> {
		name	=> "line1",
		mode	=> "line",
	},
	"10"	=> {
		name	=> "name",
		mode	=> "line",
		mask	=> "CC",
		group	=> "names",
	},
	"12"	=> {
		name	=> "sound",
		mask	=> "n",
	},
};
our @script_groups=qw/names/;

sub maybe_slurp($;$){local $/;open my $h,"$_[0]" or return "";$_[1]?binmode $h,$_[1]:binmode $h; my $data=<$h>;close $h;$data}
sub slurp($;$){local $/;open my $h,"$_[0]" or croak "$! - $_[0]";$_[1]?binmode $h,$_[1]:binmode $h; my $data=<$h>;close $h;$data}
sub spit($$;$){open my $h,">","$_[0]" or croak "$! - $_[0]";$_[2]?binmode $h,$_[2]:binmode $h; print $h $_[1];close $h}

sub list(@){
	my @res;
	my %options;
	
	for my $mask(@_){
		push @res,$mask and next unless $mask=~/[\*\?]/;
		
		my($dirpart,$namepart)=$mask=~m!^(?:(.+)/)?(.*)$!;
		$dirpart||='.';
		
		my $regexp_text=$namepart;
		$regexp_text=~s/\./\\./g;
		$regexp_text=~s/\*/.*/g;
		$regexp_text=~s/\?/./g;
		
		my $regexp=qr/^$regexp_text$/;
		
		push @res,$mask and next unless opendir my $dir,$dirpart;
		
		my @list=map "$dirpart/$_",grep{/$regexp/ and not /^\.\.?$/} readdir $dir;
		
		push @res,$mask and next unless @list;
		
		push @res,@list;
	}

	@res
}

sub rlist(@){
	my @list=list @_;
	my @res;

	while($_=shift @list){
		if(-d $_){
			push @list,list "$_/*";
		} else{
			push @res,$_;
		}
	}
	
	@res
}


sub eatline($;$){
	my($h,$stop_on_whitespace)=@_;
	local($_);
	
	while(0==length $_){
		return undef if eof $h;
		$_=<$h>;
		chomp;
		s/^\x{feff}//;
		
		return "" if $stop_on_whitespace and 0==length $_;
		
		return $1 if /^!(.*)/;
		
		s/#.*//;
		s/^[^:]*: //;
		s/\s+$//;
	}
	
	$_
}

sub database(){
	use DBI;

	my $dbh=DBI->connect(
		"DBI:mysql:database=".DATABASE_DATABASE.";host=".DATABASE_ADDRESS,
		DATABASE_USERNAME,
		DATABASE_PASSWORD,
		{AutoCommit=>1,PrintError=>0,mysql_enable_utf8=>1},
	) or die $DBI::errstr;

	$dbh->do(<<HERE) or croak $dbh->errstr;
create table if not exists text (
	line int unsigned not null,
	filename varchar(256) not null,
	game  int unsigned not null,
	text text not null,
	type varchar(64) not null,

	primary key (line,filename),
	
	index filename_index(filename),
	index game_index(game),
	index type_index(type)
) engine=myisam;
HERE

	$dbh->do(<<HERE) or croak $dbh->errstr;
create table if not exists blobs (
	line int unsigned not null,
	filename varchar(256) not null,
	game int unsigned not null,
	text blob not null,
	type varchar(64) not null,

	primary key (line,filename),
	
	index filename_index(filename),
	index game_index(game),
	index type_index(type)
) engine=myisam;
HERE

	$dbh->do(<<HERE) or croak $dbh->errstr;
create table if not exists files (
	filename varchar(256) not null,
	game int unsigned not null,
	type varchar(64) not null,
	encoding text not null,

	primary key (filename)
) engine=myisam;
HERE
	$dbh
}

my $db;
sub query($;$@){
	my($dbh)=(shift);
	my($query);

	if(not ref $dbh){
		$query=$dbh;
		$dbh=$db||=database;
	} else{
		$query=shift;
	}
	
	my $sth=$dbh->prepare($query) or croak $dbh->errstr;
	
	$sth->execute(@_) or croak $dbh->errstr;
	
	my $ref=($sth->fetchall_arrayref() or []);

	$sth->finish;
	
	$ref
}


1;
