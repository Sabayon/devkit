#!/usr/bin/env perl
# This code is licenced GPLv2 or newer.

use warnings;
use strict;
use 5.010;

my $g_thres = shift // 3;

sub set_atoms {
	my %atoms = ();
	my $fh = shift;
	while (my $line = <$fh>) {
		chomp $line;
		my @words = split(' ', $line, 2);
		next if $words[0] eq "??"; # allow "dangling" files
		my $what = $words[1];
		@words = split(m:/:, $what);
		my $pkg;
		if (@words >= 2) {
			$pkg = join("/", @words[0..1]);
		} else {
			$pkg = $words[0]
		}
		$atoms{$pkg} = 1;
	}
	keys %atoms
}

sub num {
	my $what = shift;
	my @arr = @_;
	my $num = 0;
	for (@arr) {
		$num++ if index($_, "$what-") == 0
	}
	$num
}

sub replace {
	my $atom = shift;
	my @arr = @_;
	my @new_arr;
	for my $item (@arr) {
		if( index($item, $atom) == 0 ) {
			1;
		} else {
			push @new_arr, $item;
		}
	}
	push @new_arr, "$atom*";
	@new_arr;
}

# try to make (a*, b, c*) from (a-1, a, a-2, b, c, c-1),
# for example, if numberOf(/^a-?/) >= $thres
sub do_reduce {
	my $thres = shift;
	my @atoms = @_;
	my @processed_atoms = @atoms;
	for my $atom (@atoms) {
		@processed_atoms = replace($atom, @processed_atoms)
			if (num($atom, @processed_atoms) >= $thres);
	}
	@processed_atoms
}

#my @atoms = set_atoms(*DATA);
my @atoms = set_atoms(*STDIN);
@atoms = do_reduce($g_thres, @atoms);
say join ",", sort @atoms;

__DATA__
 M net-p2p/transmission-base/metadata.xml
 M net-p2p/transmission-cli/metadata.xml
 M net-p2p/transmission-daemon/metadata.xml
 M net-p2p/transmission-gtk/metadata.xml
 M net-p2p/transmission-qt4/metadata.xml
 M net-p2p/transmission/metadata.xml
 M cat/pkg-1
 M cat/pkg-2
 M cat/pkg
 M net-p2p/nic
?? betr.pl
