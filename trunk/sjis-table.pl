use strict;
use Encode;
use Data::Dumper;

binmode *STDOUT,":utf8";

my $mode=shift;

sub print_html;
sub print_count;
sub print_code;

sub nothing{};
sub my_print{print @_};
*print_html=$mode eq 'html'?\&my_print:\&nothing;
*print_count=$mode eq 'count'?\&my_print:\&nothing;
*print_code=$mode eq 'code'?\&my_print:\&nothing;

print_html '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd"><html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en" dir="ltr"><head><meta http-equiv="Content-Type" content="text/html; charset=utf8" /><style>table,tr,td,th{border-collapse:collapse;border:1px solid #AAAAAA;text-align:center;}</style></head><body><table>';

print_code <<HERE;
use utf8;

HERE

my @list=map{my $l=$_;
	map{
		($l<<8)+$_;
	}0x40..0xfc;
}0x81..0x9f,0xe0..0xef;

my @protected;
#my @protected=(0x8740..0x8775,0x877e,0x8780..0x879c,0xec81..0xec8a,0xec96..0xec98,0xec9d..0xecbf,0xecc1..0xed80,0xed84..0xedc2,0xedc4..0xee83,0xee87..0xee92);

my $count=0;

my $lc="abcdefghijklmnopqrstuvwxyz";
my $uc=uc $lc;
my $di="0123456789";

my %chars_used;

sub mix(;$$$){
	my($left,$both,$right)=@_;
	
	my @left=split //,$left;
	my @both=split //,$both;
	my @right=split //,$right;
	
	@left=sort(@left,@both);
	@right=sort(@right,@both);
	
	$chars_used{$_}=1 foreach @left,@right;
	
	map{
		my $l=$_;
		map{
			"$l$_"
		}@right;
	}@left;
}

#
# 
#

my %duprem=map{$_=>1;}(
	(mix "",		"$lc '-",	""),
	(mix "$uc",		"$lc ",		"-"),
	(mix "I",		"'",		""),
	(mix " (\"",	"",			"$uc"),
	(mix "-",		"$di ",		",."),
	(mix "$lc",		"",			".),!"),
	(mix '("',		"",			"$lc"),
	(mix ',.!?:");',"",			" "),
	(mix "",		".",		""),
	(mix "",		"!",		""),
	(mix ')"',		"",			".,"),
);

my @doubles=sort keys %duprem;
my %doubles=map{$doubles[$_]=>$_;} 0..$#doubles;
my %doubles_codes;
my $doubles_table;
my %table_locations;

my @single_chars=sort keys %chars_used;
my %single_chars=map{$single_chars[$_]=>$_} 0..$#single_chars;
my $single_chars=join "",@single_chars;

my @more_doubles=@doubles;

for(0..$#list){
	print_html sprintf "<tr><td><tt>%04x</tt></td>",$list[$_] if ($_%32)==0;
	
	my $leave=0;
	while(@protected and $protected[0]<=$list[$_]){
		$leave=1;
		shift @protected;
	}
	
	my $jchar=pack "n",$list[$_];
	$table_locations{$list[$_]}=$_;
	my $uchar="";
	eval{$uchar=decode "sjis",$jchar,Encode::FB_CROAK};
	if($uchar eq "" and not $leave){
		$count++;
		
		my $letter=shift @more_doubles;
		if($letter){
			$doubles_codes{$letter}					= $list[$_];
			$doubles_table->[int($_/32)]->[$_%32]	= $letter;
		}
	}

	print_html sprintf "<td title='[0x%04x]'>$uchar</td>",$list[$_];
	print_html "</tr>" if (($_+1)%32)==0;
}

die sprintf "Not enough code points! Need %d more",scalar @more_doubles if @more_doubles;

print_html "</table></body></html>";

$Data::Dumper::Indent = 1;
print_code(Data::Dumper->Dump(
	[	$single_chars,	\@single_chars,		\%single_chars,			\@doubles,		\%doubles,		\%doubles_codes,	$doubles_table,	\%table_locations],
	[qw(single_chars	single_chars_list	single_chars_hash		doubles_list	doubles_hash	doubles_codes		doubles_table	table_locations)]
));

print_count "Total of $count spare characters\n";
print_count "Used ".@doubles."\n";

