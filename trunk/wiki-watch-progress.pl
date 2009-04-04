use strict;
use Encode;
use MediaWiki::API;
use WWW::Mechanize; # I can't seem to edit pages with mediawiki api
use Data::Dumper;
use Getopt::Long;
use JSON;
use String::SetUTF8;


use utf8;
binmode *STDOUT,":utf8";

my($home);
BEGIN{($home)=$0=~/(.*)[\/\\].*/;$home||=".";}
use lib $home;

BEGIN{ require "utils.pl" }
my @groups=our @script_groups;

my $first=0;
my $text=maybe_slurp "wiki-progress-progress";
$first=1 unless $text;
my($stored,$aliases)=@{ $text?from_json($text):[{},{}] };
my %must_remake;
my $start=time;

my $remake;

GetOptions(
	"remake"				=> \$remake,
);

sub usage(){print <<HERE;exit;}
Usage: $0
HERE

my %categories=(
	PS	=> {
		dir		=> "YUMFILE_1",
	},
	WS	=> {
		dir		=> "YUMFILE_2",
	},
	MM	=> {
		dir		=> "YUMFILE_3",
	},
);
my $cats=join "|",keys %categories;

my $wiki = MediaWiki::API->new();
$wiki->{config}->{api_url} = 'http://www.tsukuru.info/tlwiki/api.php';
my $link="http://www.tsukuru.info/tlwiki/index.php";

sub wikierr(){
	$wiki->{error}->{code} . ': ' . $wiki->{error}->{details};
}

#$wiki->login({lgname=>'Anonymous of Russian Federation',lgpassword =>''})
#	or die wikierr;

sub wikipage($){
	my($title)=@_;
	my $retries=12;

retry:
	return "" unless $retries;
	
	$title=$aliases->{$title},goto retry if $aliases->{$title};
	my $page=$wiki->get_page({title=>"$title"})
		|| return "";
	
	if($page->{'*'}=~m!#REDIRECT \[\[(.*?)\]\]!){
		$title=$aliases->{$title}=$1;
		$retries--;
		goto retry;
	}
	
	$page->{'*'}
}

sub recents(){
	my $timestamp=maybe_slurp "wiki-progress-last-check";
	$timestamp=time-8*60*60 if $remake or not $timestamp;
	
	my $ref=$wiki->api({
		action	=> 'query',
		list	=> 'recentchanges',
		rcend	=> $timestamp,
		rclimit	=> 500,
	}) || die wikierr;
	
	@{ $ref->{query}->{recentchanges} }
}

sub differences($$){
	my($cat,$no)=@_;
	
	my $info=$categories{$cat} || return -2;
	my $original=maybe_slurp "$info->{dir}/script/$no.txt",":utf8" || return -3;
	
	my $page=wikipage "Idolmaster_SP:$cat:$no" || return -4;
	$page=~s/ <nowiki>\r?\n// || return -5;
	
	my $had_empty_line;
	my($original_lines,$page_lines)=map{
		$had_empty_line=0;
		[grep{not /^\s*$/} map{
			$had_empty_line=1 if /^$/;
			
			/^!/ or do{
				s/#.*//;
				s/^[^:]*: //;
			};
			
			$had_empty_line?$_:""
		}split /\r?\n/]
	} $original,$page;
	
	my $lines=0;
	my $differences=0;
	for(0..@$original_lines-1){
		$lines++;
		$differences++ unless $original_lines->[$_] eq $page_lines->[$_];

#		print
#			"$original_lines->[$_]",
#			($original_lines->[$_] eq $page_lines->[$_]?' == ':' != '),
#			"$page_lines->[$_]\n";
	}
	
	$differences+=@$page_lines-@$original_lines;
	$lines+=@$page_lines-@$original_lines;
	
	warn "$cat:$no: number of lines differ\n"
		if @$page_lines-@$original_lines!=0;
	
	return -6 if $lines==0;
	
	return int($differences/$lines*100);
}

my $glob_mech;
sub mech(){
	return $glob_mech if $glob_mech;
	
	my $mech=WWW::Mechanize->new();

	my $response=$mech->post(
		"$link?title=Special:Userlogin&action=submitlogin",
		Content=>[
			wpName			=> 'Anonymous of Russian Federation',
			wpPassword		=> '',
			wpRemember		=> "1",
			wpLoginAttempt	=> "Log in"
		]
	);
	die "couldn't login: ".$response->code unless $mech->content=~/You are now logged in/;
	
	$glob_mech=$mech
}

sub wiki_edit($$$){
	my($title,$text,$summary)=@_;
	my $mech=mech;

	$mech->get("$link?title=$title&action=edit");
	
	unsetUTF8($text);
	
	$mech->submit_form(
		form_name	=> 'editform',
		fields		=> {
			wpTextbox1  => $text,
			wpSummary	=> $summary,
			wpMinoredit	=> 1,
		},
		button		=> 'wpSave',
	);
}

my %titles=map{$_->{title}=>1} recents;

for(keys %titles){
	next unless /Idolmaster SP:($cats):(\d+)/;
	my($cat,$no)=($1,$2);
	
	my $difference=differences $cat,$no;
	if($difference!=$stored->{"$cat$no"} and $stored->{"$cat$no"}>=0){
		$stored->{"$cat$no"}=$difference;
		$must_remake{$cat}=1;
	}
}

%must_remake=%categories if $first;

for my $cat(keys %must_remake){
	my $page=$wiki->get_page({title=>"Idolmaster_SP:$cat"})
		|| warn wikierr;
	
	my @changes;

	my $text=$page->{'*'};
	$text=~s{(\[\[Idolmaster_SP:)($cats)(:)(\d+)(\|\d+.txt\]\]  \s*  \|\|  \s*  )(\d+)(%)}{
		my($l2,$cat,$l1,$no,$r1,$precentage,$r2)=($1,$2,$3,$4,$5,$6,$7);
		
		$stored->{"$cat$no"}=$precentage if $first and not defined $stored->{"$cat$no"};
		
		$precentage=$stored->{"$cat$no"},push @changes,"$cat:$no to $precentage%"
			if $stored->{"$cat$no"}>=0 and $stored->{"$cat$no"}!=$precentage;
		
		"$l2$cat$l1$no$r1$precentage$r2"
	}xge;
	
	
	wiki_edit "Idolmaster_SP:$cat",$text,"Changing progress: ".(join ", ",@changes) if @changes;
	print "$cat: changed ",(join ", ",@changes),"\n" if @changes;
}

spit "wiki-progress-progress",to_json([$stored,$aliases]);
spit "wiki-progress-last-check",$start;



