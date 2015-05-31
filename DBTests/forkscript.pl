#!/usr/bin/perl

use strict;
use warnings;

use DBI;
#use DBIx::Connector;
use Parallel::ForkManager;
use Try::Tiny;

=comment
my $dsn  = "dbi:Pg:dbname=transactionstest;host=localhost";
my $user = "postgres";
my $pass = "parola123";
my $conn = DBIx::Connector->new($dsn, $user, $pass,
    {
        AutoCommit       => 0,
        PrintError       => 0,
        RaiseError       => 1,
        ChopBlanks       => 1,
        FetchHashKeyName => 'NAME_lc',
    }
);
END { unlink "transactionstest" }

#setup table
$conn->run(fixup => sub {
    my $dbh = $_;
    $dbh->do("create table foo ( id integer, name char(35) )");
    my $sth = $dbh->prepare("insert into foo (id, name) values (?, ?)");
    while (<DATA>) {
        chomp;
        $sth->execute(split /,/);
    }
});
=cut
my $pm = Parallel::ForkManager->new(3);

for my $id (1 .. 3) {
    next if $pm->start;
     
    my $dbh = DBI->connect('dbi:Pg:dbname=transactionstest;host=localhost','postgres','parola123',{AutoCommit=>0,RaiseError=>1,PrintError=>0});
    
    try 
    {
        $dbh->do("begin transaction isolation level serializable") or die;
        
        my $sth = $dbh->prepare("select * from bar where a = ?");
        $sth->execute($id);

        while (my $row = $sth->fetchrow_hashref) {
            print "$id saw $row->{a} => $row->{b}\n";
        }

        $sth = $dbh->prepare("update bar set b = ? where a = ?");
        #$sth->execute(time % 10000, int(rand(7)) + 1);
        print "Before execute update\n";
        $sth->execute(time % 10000, 1);
        print "Before commit \n";
        $dbh->commit();
        print "commited\n";   
    } 
    catch
    {
        $dbh->rollback();
    };

    $dbh->disconnect();
    $pm->finish;
}

$pm->wait_all_children;

print "done\n";
