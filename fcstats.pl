#!/usr/bin/perl

###############################################################################
#
# fcstats.pl - Display FC host adapter stats
#
# Copyright (c) by  Oliver Falk, 2012-2013
#                   oliver@linux-kernel.at
#
# Changes are welcome, but please inform me about those!
#
###############################################################################

use strict;
use warnings;

use File::Glob ':glob';
use File::Basename;
use Time::HiRes;
use Time::HiRes qw/tv_interval gettimeofday/;
use Data::Dumper; # debug only
use Getopt::Long;

use bignum qw/hex/;

use constant PATH => '/sys/class/fc_host/host*';

my $secs = 1;
my ($abbr, $in, $out);
my $type = 'm';
my $result = GetOptions(
	"secs|s=i"	=> \$secs,
	"type|t=s"	=> \$type,
);

if($type eq 'm') {
	$in = 'fcp_input_megabytes';
	$out = 'fcp_output_megabytes';
	$abbr = 'MB';
} elsif($type eq 'w') {
	$in = 'rx_words';
	$out = 'tx_words';
	$abbr = 'words';
} elsif($type eq 'f') {
	$in = 'rx_frames';
	$out = 'tx_frames';
	$abbr = 'frames';
} else {
	die "Type '$type' unknown (possible values: 'm' (Megabyte), 'w' (Words), 'f' (Frames)";
}

my @hba = bsd_glob(PATH);

die "No FC adapters found. /sys mounted!?" unless @hba;

my $t0 = [gettimeofday];
my $hbas;
while(1) {
	my $elapsed = tv_interval ($t0);
	print "\033[2J";    #clear the screen
	print "\033[0;0H"; #jump to 0,0
	foreach(@hba) {
		my $hbaname = basename($_);

		open(FH, "$_/port_state");
		$hbas->{$hbaname}->{portstate} = <FH>;
		chomp($hbas->{$hbaname}->{portstate});
		close(FH);
		
		unless($hbas->{$hbaname}->{portstate} eq 'Linkdown') {
			open(FH, "$_/statistics/$in");
			$hbas->{$hbaname}->{rx} = <FH>;
			chomp($hbas->{$hbaname}->{rx});
			$hbas->{$hbaname}->{rx} = hex($hbas->{$hbaname}->{rx});
			close(FH);
			$hbas->{$hbaname}->{diff_rx} = $hbas->{$hbaname}->{rx} - ($hbas->{$hbaname}->{last_rx}||$hbas->{$hbaname}->{rx});
			$hbas->{$hbaname}->{last_rx} = $hbas->{$hbaname}->{rx};
			$hbas->{$hbaname}->{rx_ps} = $hbas->{$hbaname}->{diff_rx} / $elapsed;

			open(FH, "$_/statistics/$out");
			$hbas->{$hbaname}->{tx} = <FH>;
			chomp($hbas->{$hbaname}->{tx});
			$hbas->{$hbaname}->{tx} = hex($hbas->{$hbaname}->{tx});
			close(FH);
			$hbas->{$hbaname}->{diff_tx} = $hbas->{$hbaname}->{tx} - ($hbas->{$hbaname}->{last_tx}||$hbas->{$hbaname}->{tx});
			$hbas->{$hbaname}->{last_tx} = $hbas->{$hbaname}->{tx};
			$hbas->{$hbaname}->{tx_ps} = $hbas->{$hbaname}->{diff_tx} / $elapsed;

			printf("$hbaname: RX: %10d $abbr (%9.2f $abbr/s), TX: %10d $abbr (%9.2f $abbr/s)\n", $hbas->{$hbaname}->{rx}, $hbas->{$hbaname}->{rx_ps}, $hbas->{$hbaname}->{tx}, $hbas->{$hbaname}->{tx_ps});
		} else {
			printf("$hbaname: Link down\n");
		}
	}
	# print Dumper($hbas); # debug only
	exit 0 unless $secs;
	$t0 = [gettimeofday];
	print "Update interval: $secs seconds\n";
	sleep $secs;
}

1;

__END__

=head1 NAME

fcstats.pl

=head1 SYNOPSIS

  perl fcstats.pl

=head1 DESCRIPTION

Display FC host adapter stats

=head2 EXPORT

None.

=head1 AUTHOR

Oliver Falk, E<lt>oliver@linux-kernel.at<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012-2013 by Oliver Falk

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.6 or,
at your option, any later version of Perl 5 you may have available.

=cut
