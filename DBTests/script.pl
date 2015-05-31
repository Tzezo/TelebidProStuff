use strict;
use warnings;

use DBI;
use Try::Tiny;
use threads;
use threads::shared;
use Data::Dumper;
use Time::HiRes qw(usleep);

my $fail_counter :shared;
$fail_counter = 0;
my $retry_counter :shared;
$retry_counter = 0;
my $transaction_count;

sub Thread($$$)
{
    my($retries, $isolation_level, $sleep) = @_;
    print $isolation_level, $sleep, $transaction_count;
    
    my $dbh = DBI->connect('dbi:Pg:dbname=transactionstest;host=localhost','postgres','parola123',{AutoCommit=>0,RaiseError=>1,PrintError=>0});
        
    my $query = "";
    REDIRECT_LOOP: while(1)
    {
        my $is_last = 0;
        try
        {
            #print "foo\n";
            #$dbh->do("begin transaction isolation level $isolation_level") or die;
            my $sth = $dbh->prepare("SET TRANSACTION ISOLATION LEVEL $isolation_level") or die;
            $sth->execute();
            
            $sth = $dbh->prepare("select sum(a) from bar;");
            $sth->execute();
            my $row = $sth->fetchrow_hashref();

            if(!$query)
            {
                my $time = time % 10000;
                my $a = int(rand(7)) + 1;
            
                $query = "update bar set b = '$time' where a = '$a'";
            }
            elsif($retries eq "yes")
            {
                {
                    lock($retry_counter);
                    $retry_counter++;
                }
            }
            print "$query\n\n";
            $sth = $dbh->prepare($query);
            $sth->execute(); 

            $sth = $dbh->prepare("select sum(a) from bar;");
            usleep($sleep);
            $dbh->commit();
            $query = "";
            #last REDIRECT_LOOP;
            $is_last = 1;
            #print "bar\n";
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

            if($retries eq "no")
            {
                $query = "";
                #last REDIRECT_LOOP;
                $is_last = 1;
            }
        };

        if($is_last)
        {
            $dbh->disconnect;
            last REDIRECT_LOOP;
        }
   }
   #}
}

sub Main($$$$)
{
    my ($retries, $isolation_level, $sleep, $conc_num) = @_;
    for(my $m = 0; $m < $conc_num; $m++)
    {
        my $thread = threads->new(sub{Thread($retries, $isolation_level, $sleep)});
    }

    my $c = 0;
    while(1)
    {
        print "Fail counter: $fail_counter \n Retires: $retry_counter \n Isolation Level: $isolation_level \n Sleep: $sleep \n Threads: $conc_num\n";
        sleep 4;
        print "----------------------------\n";
        if($c >= 3)
        {
          my $csv = "$isolation_level, $conc_num, $conc_num, $fail_counter, $retry_counter, $sleep, $retries\n";
          #Isolation lvl, Threads, Transactions, Fails, Retries, Sleep, Retry(Yes/No)
          my $fh;
          open $fh, ">>", "results.csv";
          print $fh $csv;
          close $fh;

          last;
        }
        $c++;
    }
}

my $retries = ['no', 'yes'];
my $isolation_levels = ['SERIALIZABLE','REPEATABLE READ','READ COMMITTED'];
#my $isolation_levels = ['READ COMMITTED'];
my $conc_num = [2,10,100,1000];
#my $conc_num = [1000];
my $sleep = [0, 50, 500, 1000];
#my $sleep = [1000];


for(my $r = 0; $r < @$retries; $r++)
{
    for(my $i = 0; $i < @$isolation_levels; $i++)
    {
        for(my $s = 0; $s < @$sleep; $s++)
        {
            $fail_counter = 0;
            for(my $k = 0; $k < @$conc_num; $k++)
            {
                #$transaction_count = 1000;
                $transaction_count = $$conc_num[$k];
                Main($$retries[$r], $$isolation_levels[$i], $$sleep[$s], $$conc_num[$k]);
            }
        }
    }

}

