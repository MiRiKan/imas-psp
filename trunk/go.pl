
open my $h,"57954.unk" or die $!;
binmode $h;

local $/;

my $data=<$h>;

close $h;

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

die valid_sjis $data;

