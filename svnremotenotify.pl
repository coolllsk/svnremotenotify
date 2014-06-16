#!/usr/bin/perl
# 
# Remote svn notifications to email
# Author: Viliam Krizan <coolll AT naplno.sk>

use strict;
use warnings;

use Switch;
use Getopt::Long;
use File::Basename;
use MIME::Lite;

use vars qw (
	$svnurl
	$to
	$do_help
	$do_log
	$log_file
	$notified_file
	$max
);

# function declarations
sub help();
sub append();
sub getLastRev;
sub lastNotifiedRev;
sub projectName;
sub countDiffLines;

# default values
$do_log        = 0;
$max           = 10;
$log_file      = 'svnnotfied.log';
$notified_file = 'notified.revs';

my $res = GetOptions(
	'url|u=s'  => \$svnurl,
	'to|t=s'   => \$to,
	'help|h'   => \$do_help,
	'log|l'    => \$do_log,
	'log-file' => \$log_file,
	'notified=s' => \$notified_file,
	'max|m=i'  => \$max,
);

if (! $res || !defined($svnurl) || !defined($to)) {
	help();
}

my $lastNotifiedRev = lastNotifiedRev();
my %logs = getRevisionLogs($svnurl, $lastNotifiedRev, $max);

if (scalar(keys(%logs)) == 0) {
	print STDERR "No logs found\n";
	exit 5;
}

my $lastSVN = getLastRev(%logs);
if (! defined $lastNotifiedRev) {
	$lastNotifiedRev = $lastSVN; # last rev from SVN as last notified
	print "Last notified revision does not exists; setting rev $lastSVN\n";
	setNotifiedRev($lastSVN);
	exit 0;
}

if ($lastNotifiedRev >= $lastSVN) {
	# no new logs
	print "No new logs; exiting\n";
	exit 0;
}

my $project = projectName($svnurl);
print "Project name:      $project\n";
print "Last SVN rev:      $lastSVN\n";
print "Last notified rev: $lastNotifiedRev\n";

foreach my $rev (sort(keys(%logs))) {
	
	if ($rev == $lastNotifiedRev) {
		next;
	}
	if ($logs{$rev}{author} eq '(no author)') {
		print "No author for r$rev (protected)\n";
		next;
	}
	if (! $logs{$rev}{changed}) {
		print "No changed files for r$rev\n";
		next;
	}
	
	print "Reporting r$rev by ". $logs{$rev}{author}."\n";
	my $subject = "SVN commit report $project r$rev";

	my $mime = MIME::Lite->new(
	    #From    => 'me@myhost.com',
	    To      => $to,
	    Subject => $subject,
	    Type    => 'multipart/mixed',
	);

	my @diff = `svn diff -c $rev --no-diff-deleted $svnurl`
			or die("svn diff failed; exiting\n");
	#my %stats = countDiffLines(@diff);
	#foreach (keys(%stats)) {
	#	printf "%s: (+%d, -%d)\n", $_, $stats{$_}{'+'}, $stats{$_}{'-'};
	#}

	my $msg = sprintf "Revision: %d\n", $rev;
	$msg .= sprintf "Author:   %s\n", $logs{$rev}{author};
	$msg .= sprintf "Date:     %s\n\n", $logs{$rev}{date};
	$msg .= $logs{$rev}{changed}."\n";
	$msg .= $logs{$rev}{log}."\n";
	#$msg .= join('', @diff);

	#$mime->set('Type', '');
	$mime->attach(
		Type     => 'text/plain',
		Data => $msg);

	$project =~ s/\//_/g;

	$mime->attach(
		Type => 'text/plain',
		Filename => "$project-r$rev.diff",
		Data => join('', @diff),
	);
	$mime->send;

	#print $msg;


}

setNotifiedRev($lastSVN);
exit 0;

# -----------
# Functions

sub getLastRev {
	my (%logs) = @_;
	(reverse(sort(keys(%logs))))[0];
}

sub lastNotifiedRev {
	if (! -f $notified_file) {
		return undef;
	}
	open NOTIFIED, '<', $notified_file 
			or die("Cannot open notified file $notified_file: $!\n");
	while (<NOTIFIED>) {
		if (/^\Q$svnurl\E:\Q$to\E:(\d+)$/) {
			close NOTIFIED;
			return $1;
		}
	}
	close NOTIFIED;
	undef;
}

sub setNotifiedRev {
	my ($rev) = @_;
	my @lines = ();
	if (-f $notified_file) {
		open NOTIFIED, '<', $notified_file 
				or die("Cannot open notified $notified_file for read: $!\n");
		@lines = <NOTIFIED>;
	}

	open NOTIFIED, '>', $notified_file 
			or die("Cannot open notified $notified_file for write: $!\n");
	my $append = 1;
	foreach (@lines) {
		if (s/^\Q$svnurl\E:\Q$to\E:(\d+)\Z/$svnurl:$to:$rev/) {
			$append = 0;
		}
		print NOTIFIED $_;
	}
	print NOTIFIED "$svnurl:$to:$rev\n" if $append;
	close NOTIFIED;
}

sub getRevisionLogs
{
	my ($url, $last, $max) = @_;
	my $range = '';
	if (! defined $last) {
		$max = 1;
	} else {
		$range = "-r $last:HEAD";
	}
	my @logLines = `svn log -l $max $range -v $url`
			or die("svn log failed; exiting\n");
	my %ret = ();

	my $state = 0;
	my $rev   = 0;
	my $lines = 0;
	foreach (@logLines) {
		switch ($state) {
			case 0 {
				if (/^r(\d+) \| ([^|]+) \| ([^|]+) \| (\d+)/) {
					#if ($2 eq '(no author)') {
					#	# protected revision
					#	next;
					#}
					$rev = $1;
					$lines = $4;
					$state = 1;
					$ret{$rev} = {
						'rev'     => $rev,
						'author'  => $2,
						'date'    => $3,
						'changed' => '',
						'log'     => '',
						'raw'     => $_,
					};
				}
			}

			case 1 {
				if (/^[\v]*\Z/) {
					$state = 2;
				} else {
					$ret{$rev}{changed} .= $_;
				}
				$ret{$rev}{raw} .= $_;
			}
			case 2 {
				if (/^-{6,}[\v]*\Z/) {
					$state = 0;
				} else {
					if ($lines) {
						$ret{$rev}{log} .= $_;
						$lines--;
					}
					$ret{$rev}{raw} .= $_;
				}
			}
		}
	}
	%ret;
}

sub countDiffLines {
	my (@diff) = @_;
	my %ret = ();

	my $state = 1;
	my $file = '';
	my $count = 0;
	foreach (@diff) {
		switch ($state) {
			case 0 {
				if (/^--- (.*\w)\s+\(revision/) {
					$file = $1;
					$ret{$file} = {
						'+' => 0,
						'-' => 0,
					};
				}
				if (! --$count) {
					$state = 1;
				}
			}
			case 1 {
				if (/^={8,}[\v]*\Z/) {
					$state = 0;
					$count = 3;
				} else {
					if (/^\+/) {
						$ret{$file}{'+'}++;
					} elsif (/^-/) {
						$ret{$file}{'-'}++;
					}
				}
			}
		}
	}
	%ret;
}

sub appendLog() {
	if ($do_log) {
		return strftime("%b %d %H:%M:%S", localtime); 
	}
}

sub projectName {
	my ($url) = @_;
	if ( $url =~ /([^\/]+\/)(trunk|tags|branches)(\/.+)?$/ ) {
		if (defined $3) {
			return $1.$2.$3;
		}
		return $1.$2;
	} else {
		return basename($url);
	}
}

sub help() {
	print "Usage: $0 -u <URL> -t <EMAIL>\n\n";
	print "Options:\n";
	print "    -u --url   <SVNURL>\n";
	print "    -t --to    <EMAIL>\n";
	#print "    -l --log\n";
	#print "    --log-file <LOG_FILEPATH>\n";
	print "    --notified <NOTFIED_FILE_PATH>\n";
	print "    -m --max   <MAX_DIFF_REVISIONS> default 10\n";
	exit 1;
}