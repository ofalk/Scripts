#!/usr/bin/perl

#
# Copyright (c) Oliver Falk, 2011
#               oliver@linux-kernel.at
#
# License: See perldoc
#
# This script is based on a shell script, used to dump
# our MySQL databases.
# 
# Changes are welcome, but please inform me about those!
#

use strict;
use warnings;

use DateTime;
use File::Path;
use File::Copy;
use File::Glob qw/glob/;
use File::Basename;

# BEGIN of user part
use constant DIR => '/BACKUP/mysql-dump';
use constant MYSQL_DIR => '/var/lib/mysql';
use constant USER => 'root';
use constant PASS => '';
use constant DRYRUN => 0;
use constant DIR_AGE_WARN => 7;
use constant MYSQL_DATA_EXTENSION => '.MYD';
use constant MAX_THREADS => 3;
# DEBUG is up to 3 - but produces a lot of debugging information
# Especially thread related stuff
use constant DEBUG => 1;
# Because it is fancy...
use constant USE_ASCIITable => 1;
# Path to mysqldump command line tool
use constant MYSQLDUMP => '/usr/bin/mysqldump';
# This is recommended!
use constant USE_DBI => 1;
# END of user part

use threads (
        'yield',
        'exit' => 'threads_only',
        'stringify'
);

sub find_jobs {
	my @backup_tasks;
	my $yd = DateTime->now->ymd . '-' . DateTime->now->hms;

	if(-d DIR) {
		# Check old directory
		my $dest = DIR . '-' . $yd;
		print "Moving away " . DIR . " to $dest ..";
		
		unless(DRYRUN) {
			move(DIR, $dest);
			print '.. DONE';
		} else {
			print '.. DRYRUN - nothing DONE';
		}
		print "\n";

		# Check old backups - warn if there are directories older than
		# constant DIR_AGE_WARN
		foreach my $dir (glob(DIR . '*')) {
			next if $dir eq DIR;
			
			if(-M ($dir) > DIR_AGE_WARN) {
				print "Old directory: $dir - should be deleted!\n";
			}

		}
	}

	mkpath(DIR) unless DRYRUN;

	if(USE_DBI) {
		use DBI;

		my @databases;
		my $dsn = "DBI:mysql:host=localhost";
		my $dbh = DBI->connect($dsn, USER, PASS);
		my $sth = $dbh->prepare("SHOW DATABASES");
		$sth->execute();
		while(my $ref = $sth->fetchrow_hashref()) {
			push @databases, $ref->{Database};
		}
		$sth->finish();

		foreach(@databases) {
			$sth = $dbh->prepare("SHOW TABLES FROM $_");
			$sth->execute();
			while(my $ref = $sth->fetchrow_hashref()) {
				# Skip these tables - you cannot dump them
				next if $ref->{'Tables_in_'.$_} eq 'general_log';
				next if $ref->{'Tables_in_'.$_} eq 'slow_log';
				push @backup_tasks, { dbn => $_, tbn => $ref->{'Tables_in_'.$_} };
			}
			$sth->finish();
		}

	# If for some reason(s) you cannot use DBI/DBD::MySQL, you will need to do it this
	# way. However, it's not guaranteed that you will really get *all* your tables!!!
	} else {
		foreach my $entry (glob(MYSQL_DIR . '/*')) {
			next unless -d $entry;
			my $dbn = basename($entry);
			foreach my $tb (glob($entry . '/*' . MYSQL_DATA_EXTENSION)) {
				my $tbn = basename($tb, MYSQL_DATA_EXTENSION);
				
				print "Found: $dbn - $tbn\n" if DEBUG >= 2;
				push @backup_tasks, { dbn => $dbn, tbn => $tbn };
			}
		}
	}
	return @backup_tasks;
}

# For lots of logging, you want to speed up loggin and want to
# create a seperate logging thread (think of Thread::Queue...
sub logger($) {
	my $line = shift;
	my $tid = threads->tid();
	select STDERR; $| = 1;
	select STDOUT; $| = 1;

	printf("[%s %s] %5i (%3i): %s", DateTime->now->ymd, DateTime->now->hms, $$, $tid, $line);
}

sub dump_data_base($) {
	my $dbntbn = shift;
	my $database = $dbntbn->{dbn};
	my $table = $dbntbn->{tbn};
	my $destination_path = DIR . '/' . $database;
	my $destination_file = $destination_path . '/' . $table . '.dump.bz2';
	$dbntbn->{start_time} = DateTime->now->ymd . '-' . DateTime->now->hms;
	logger("'dump_data_base' thread " . threads->tid() . " started - $database - $table\n") if DEBUG >= 2;

	mkpath($destination_path) unless DRYRUN;
	logger(sprintf("Dumping %-60s -> %s\n", "$database - $table", $destination_file)) if DEBUG >= 2;

	my $cmd;
	unless(PASS) {
		$cmd = sprintf('%s         -u"%s"           %s         %s | bzip2 -c > %s',
		                   MYSQLDUMP,    USER,         $database, $table,       $destination_file);
	} else {
		$cmd = sprintf('%s         -u"%s"  -p"%s"  %s         %s | bzip2 -c > %s',
		                   MYSQLDUMP,    USER,   PASS, $database, $table,       $destination_file);
	}
	unless(DRYRUN) {
		open(DUMP, "$cmd|");
		while(<DUMP>) {
			logger($_);
		}
	}

	logger("'dump_data_base' thread " . threads->tid() . " stopping - $database - $table\n") if DEBUG >= 2;
	$dbntbn->{end_time} = DateTime->now->ymd . '-' . DateTime->now->hms;
	return $dbntbn;
}

sub join_thread($) {
	my $tid = shift;
	logger("Joining in one thread\n") if DEBUG >= 3;
	return {
		tid => $tid->tid(),
		data => $tid->join(),
		date => DateTime->now->ymd . '-' . DateTime->now->hms,
	};
}

sub main {
	my @backup_tasks = find_jobs(); # Populate @backup_tasks
	my $max_threads = MAX_THREADS;
	my (@dumpers, @tasks_done);

	if (DEBUG >= 2) {
		if(USE_ASCIITable) {
			use Text::ASCIITable;
			my $t = Text::ASCIITable->new();
			$t->setCols('DB', 'table');
			foreach (@backup_tasks) {
				$t->addRow($_->{dbn}, $_->{tbn});
			}
			print $t;
		}
	}

	# If there are less tasks than max threads, reduce the max_threads
	# If this is the case, you might not need this script anyway...
	$max_threads = scalar @backup_tasks if(scalar @backup_tasks < MAX_THREADS);

	logger("Start...\n");
	while(@backup_tasks) {
		while(((scalar threads->list(threads::running)||0) < $max_threads) && @backup_tasks) {
			push @dumpers, threads->create('dump_data_base', pop @backup_tasks);
		}
		foreach(threads->list(threads::joinable())) {
			push @tasks_done, join_thread($_);
		}
		sleep 1 if((scalar @backup_tasks > 0) &&
			(((scalar threads->list(threads::running)||0)) >= $max_threads));
	}
	while((scalar threads->list(threads::running)||0)) {
		logger("Waiting for running thread\n") if DEBUG > 1;
		sleep 1;
	}
	foreach(threads->list(threads::joinable())) {
		push @tasks_done, join_thread($_);
	}
	logger("Done...\n");

	# Everything should be fine, threads should be joined
	# Display (if enabled) a nice ASCII table
	if(USE_ASCIITable) {
		use Text::ASCIITable;
		my $t = Text::ASCIITable->new();
		$t->setCols('DB', 'table', 'TID', 'Started', 'Finished');
		foreach (@tasks_done) {
			$t->addRow($_->{data}->{dbn}, $_->{data}->{tbn}, $_->{tid}, $_->{data}->{start_time}, $_->{data}->{end_time});
		}
		print $t;
	}
}

main();

1;

__END__

=head1 NAME

mysql_dump_all_by_table_threaded.pl - Dump your MySQL - threaded

=head1 SYNOPSIS

TODO

=head1 DESCRIPTION

This is a simple Perl script that dumps your MySQL data using mysqldump, but
with a defineable amount of threads.

=head1 AUTHOR

Oliver Falk, E<lt>oliver@linux-kernel.atE<gt>

=head1 COPYRIGHT
Copyright (C) 2011 by Oliver Falk

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10 or,
at your option, any later version of Perl 5 you may have available.

=cut
