use strict;
use warnings;
 
use DBI;
use Try::Tiny;
#use threads;
#use threads::shared;
use Data::Dumper;
 
#my $fail_counter :shared;
my $fail_counter = 0;
 
sub DBWork()
{
    print "Thread\n";
    my $dbh = DBI->connect('dbi:Pg:dbname=transactionstest;host=localhost','postgres','parola123',{AutoCommit=>1,RaiseError=>1,PrintError=>0});
    for(my $i = 0; $i < 100; $i++)
    {
        try
        {
            $dbh->begin_work;
            my $sth = $dbh->prepare("select * from bar;");
            $sth->execute();
            my $row = $sth->fetchrow_hashref();
            $sth = $dbh->prepare("update bar set b = ? where a = 1");
            $sth->execute(time % 10000);
            $sth = $dbh->prepare("select * from bar;");
            $dbh->commit();
        }
        catch
        {
            my ($err) = @_;
            $dbh->rollback();
            print $err;
            {
                lock ($fail_counter);
                $fail_counter++;
            }    
        };
    }  
    $dbh->disconnect;
}

sub Main()
{

    for(my $i = 0; $i < 50; $i++)
    {  

        my $thread = threads->new(sub{DBWork();});
    }  
    while(1)
    {  
        print "Fail counter: $fail_counter \n";
        sleep 10;
    }
}


Main();
