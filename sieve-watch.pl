#!/usr/bin/perl -w
use strict;
use File::Tail;
use DBI;

our $log_name = '/var/log/dovecot.log';
our $path = '/var/spool/virtual';
our $db = '/var/spool/virtual/auto.db';


my $dbh = DBI->connect("dbi:SQLite:dbname=$db","","");

my $file=File::Tail->new(name=>$log_name, maxinterval=>1, adjustafter=>1);
while (my $line = $file->read) {
	if ($line =~ /copy.*?box=INBOX\.auto/) {
		my ($box, $from, $to, $mailfrom) = parse_line($line);
		unless ($box) {
			print "FAIL parse: $line\n";
			next;
		}
		if (! check_exists($box, $to, $mailfrom)) {
			$dbh->do("INSERT INTO auto (box, folder, mailfrom) values (?, ?, ?)", {}, $box, $to, $mailfrom);
			print "add $box $to $mailfrom\n";
			gen_sieve($box, $to);
		}
	}
	elsif ($line =~ /from\s+INBOX\.auto/) {
		my ($box, $from, $to, $mailfrom) = parse_line($line);
		unless ($box) {
			print "FAIL parse: $line\n";
			next;
		}
		if (check_exists($box, $from, $mailfrom)) {
			$dbh->do("DELETE FROM auto WHERE box=? AND folder=? AND mailfrom=?", {}, $box, $from, $mailfrom);
			print "del $box $from $mailfrom\n";
			gen_sieve($box, $from);
		} else {
			print "no match: $box, $from, $mailfrom\n";
		}
	} else {
#		print "NO: ", $line, "\n";
	}
}

sub check_exists {
	my ($box, $folder, $mailfrom) = @_;
	my $ref = $dbh->selectall_arrayref("SELECT mailfrom FROM auto WHERE box=? AND folder=? AND mailfrom=?", {}, $box, $folder, $mailfrom);
	if ($ref->[0] && $ref->[0]->[0]) {
		return 1;
	} else {
		return undef;
	}
}

sub gen_sieve {
	my ($id, $folder) = @_;
	return unless $id;
	my ($user, $domain) = split /\@/, $id;
	my $fullpath = sprintf("%s/%s/%s/%s.sieve", $path, $domain, $user, $folder);
	my $workfolder = sprintf("%s/%s/%s", $path, $domain, $user);

	my @from = map { $_->[0] } @{ $dbh->selectall_arrayref("SELECT mailfrom FROM auto WHERE box=? AND folder=?", {}, $id, $folder) };

	open(my $f, ">$fullpath");

# require ["fileinto"];
print $f <<H;
if address :is "from" [
H
print $f join ", ", map { '"' . $_ . '"' } (sort @from);
print $f <<S;
] {
	fileinto "$folder";
	stop;
}
S
	close $f;

	qx( cd $workfolder; cat CUSTOM.sieve > default.sieve ; cat INBOX*sieve >> default.sieve ; chown nobody:nogroup *.sieve );
}

sub parse_from ($) {
	my ($line) = @_;
	if ($line =~ /\<(.*?)\>/) {
		return $1;
	} else {
		return $line;
	}
}


sub parse_line {
	my ($line) = @_;
	if ($line =~ /imap\((.*?)\).*?from\s+(.*?)\:.*?box=(.*?)\,.*?from=(.*)$/) {
		return ($1, $2, $3, parse_from $4);
	}
	return undef;
}


1;

__END__
Jul 10 15:49:33 imap(ip@ncom-ufa.ru): Info: copy from INBOX: box=INBOX.office, uid=2374, msgid=<415077387.20140521143458@rbbf.ru>, size=117275
