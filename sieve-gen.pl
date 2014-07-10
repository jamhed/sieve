#!/usr/bin/perl -w
use strict;
use DBI;

our $path = '/var/spool/virtual';
our $db = '/var/spool/virtual/auto.db';

my ($box) = @ARGV;

my $dbh = DBI->connect("dbi:SQLite:dbname=$db","","");

my $ref = $dbh->selectall_arrayref("SELECT DISTINCT folder FROM auto WHERE box=?", {}, $box);
my @folders = map { $_->[0] } @$ref;

foreach my $folder (@folders) {
	print $folder, "\n";
	gen_sieve($box, $folder);
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
