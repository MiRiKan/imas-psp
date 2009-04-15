use strict;

sub min($$){$_[0]>$_[1]?$_[1]:$_[0]}
sub max($$){$_[0]<$_[1]?$_[1]:$_[0]}

our @startpoints=(
	[0xff0000,16],
	[0x00ff00, 8],
	[0x0000ff, 0],
	[0xff00ff, 0],
	[0x00ffff, 0],
);

sub read_mif($){
	my($miffile)=@_;
	
	open my $f,$miffile or die "$miffile - $!";
	binmode $f;

	my($count)=<$f>=~m!(?://)?MIF\s*(\d+)!;
	die "$miffile - Not a valid .mif file"
		unless defined $count;

	my($pw,$ph)=(1,1);

	my(@rects);

	for(1..$count){
		my $line=scalar <$f>;
		
		my($x,$y,$w,$h,$a,$b)=
			$line=~/^{\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+)},/;
		die "$miffile - Unexpected - $.: $line"
			unless defined $b;
		
		$pw*=2 while $pw<$x+$w;
		$ph*=2 while $ph<$y+$h;
		
		push @rects,[$x,$y,$w,$h,$a,$b];
	}
	close $f;
	
	$pw,$ph,@rects
}

sub write_mif($@){
	my($miffile,@rects)=@_;
	
	open my $f,">",$miffile or die "$miffile - $!";
	binmode $f;

	printf $f "MIF% 5d\n",scalar @rects;

	printf $f "{% 4d,% 4d,% 4d,% 4d,% 4d,% 4d},\n",@$_
		foreach @rects;
	
	close $f;
}

1;
