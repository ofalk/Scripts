#!/usr/bin/perl

use strict;
use warnings;

use String::Random qw/random_regex/;
use Digest::MD5 qw/md5_base64/;
use Apache::Htpasswd;

my $pass = new String::Random;

die "You need to provide a filename (must exist already), a prefix for your users and optionally the number of users to be added" unless $ARGV[1];

my $file = $ARGV[0];
my $inp = $ARGV[1];
my $count = $ARGV[2] || 10;

my $ht = new Apache::Htpasswd("$file");

my $usrlist;

for my $i (0..$count) {
	my $randuser = $inp . int(rand(3456) + 1000);
	$usrlist->{$randuser} = random_regex('\w\w\w\W\d\d\w\w..');
	$usrlist->{$randuser} =~ s/0/O/;
	$usrlist->{$randuser} =~ s/1/l/;
	$usrlist->{$randuser} = md5_base64($usrlist->{$randuser});
}

foreach (keys %{$usrlist}) {
	$ht->htpasswd($_, $usrlist->{$_});
}
