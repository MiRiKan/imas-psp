# WRITTEN BY ANDREY OSENENKO.
# REDISTRIBUTION AND USE OF MY ART ARE PERMITTED PROVIDED THAT THE FOLLOWING CONDITIONS ARE MET:
# YOU MUST ATTRIBUTE !!
# DO NOT STEAL MY ART.

use strict;

our $chars=" !,-.0123456789:?ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
our $char_reg=qr/[$chars]/;
our $not_char_reg=qr/[^$chars]/;

sub consume($$){
	my($mask,$handle)=@_;
	
	my $length=length pack $mask,"";
	
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

sub sjis($$){
	my($j1,$j2)=@_;
	
	die "$j1 $j2" if $j1<33 or $j2<33 or $j1>126 or $j2>126;
	
	my $s1=int(($j1+1)/2)+($j1<=94?112:176);
	my $s2=$j2+($j1&0x01?31+($j2>=96?1:0):126);
	
	$s1,$s2
}

sub charcodetable(){
	my @charslist=split //,$chars;
	my @combinations=map{
		my $l=$_;
		map{ "$l$_" } @charslist
	} @charslist;
	
	my $x=64;
	my $y=22;
	
	my %table=map{
		my $res=pack "CC",sjis($y+32,$x+32);
		
		$x=1,$y++ if ++$x==95;
		
		$_=>$res
	} @combinations;
	
	%table
}


1;
