use strict;
use warnings;
use DBI;
use Try::Tiny;
use Data::Dumper;
use Time::HiRes qw(usleep);
use Parallel::ForkManager;




sub Fork()
{
    my $pm = new Parallel::ForkManager(100);
    
    my $duration = 60; #seconds

    #my $isolation_level = ['SERIALIZABLE','REPEATABLE READ'];
    my $isolation_level = ['READ COMMITTED'];
    my $fork_count = [100];
    #my $conc_num = [1000];
    my $sleep = [5];
    #my $sleep = [1000];

    for(my $i = 0; $i < @$isolation_level; $i++)
    {
        for(my $s = 0; $s < @$sleep; $s++)
        {
            for(my $k = 0; $k < @$fork_count; $k++)
            {
                my $retry_count = 0;
                my $fail_count = 0;
                my $transactions_count = 0;

                $pm->run_on_finish(sub{
                        my ($pid,$exit_code,$ident,$exit_signal,$core_dump,$data) = @_;

                        $retry_count += $$data{retry_count};
                        $fail_count += $$data{fail_count};
                        $transactions_count += $$data{transactions_count};

                    });
                
                for(my $f = 0; $f < $$fork_count[$k]; $f++)
                {
                    $pm->start and next;
                    my $data = Transaction($$fork_count[$k], $duration, $$isolation_level[$i], $$sleep[$s]);        
                    $pm->finish(0, $data);
                }

                $pm->wait_all_children;
                
                ToCSV($$isolation_level[$i], $$fork_count[$k], $transactions_count, $fail_count, $retry_count, $$sleep[$s], $duration);
            }
        }
    }
}

sub ToCSV($$$$$)
{
    my($isolation_level, $fork_count, $transactions_num, $fails, $retries, $sleep, $duration) = @_;
    
    print "$isolation_level, $fork_count, $transactions_num, $fails, $retries, $sleep, $duration\n";
    
    my $fail_rate = $fails/( $transactions_num/100 );

    my $csv = "$isolation_level, $fork_count, $transactions_num, $fails, $retries, $sleep, $duration, $fail_rate\n";

    my $fh;
    open $fh, ">>", "results.csv";
    print $fh $csv;
    close $fh;

    return 1;
}


sub Transaction($$$)
{
    my($fork_count, $duration, $isolation_level, $sleep) = @_;
    
    my $retry_count = 0;
    my $fail_count = 0;
    my $transactions_count = 0;
    
    my $end_time = time + $duration;

    my $dbh = DBI->connect('dbi:Pg:dbname=transactionstest;host=localhost','postgres','parola123',{AutoCommit=>0,RaiseError=>1,PrintError=>0});
        
    my $query = "";
    my $query2 = "";
    while(1)
    {
        
        try
        {
            my $sth = $dbh->prepare("SET TRANSACTION ISOLATION LEVEL $isolation_level") or die;
            $sth->execute();
            
            #$sth = $dbh->prepare("select sum(a) from bar;");
            #$sth->execute();
            #my $row = $sth->fetchrow_hashref();

            if(!$query && !$query2)
            {
                my $time = time % 10000;
                my $a = int(rand($fork_count)) + 1;
                my $a2 = int(rand($fork_count)) + 1;
                my $b = "b='$time'";
                my $b2 = "b='$time'";

                if($isolation_level eq "READ COMMITTED")
                {
                    $b = "b=b+1";
                    $a = 1;
                    $b2 = "b=b+1";
                    $a2 = 1;
                }
                    
                $query = "update bar set $b where a='$a'";
                $query2 = "update bar set $b2 where a='$a2'";
            }
            else
            {
                $retry_count++;
            }
            
            $transactions_count++;

            print "$query\n\n";
            $sth = $dbh->prepare($query);
            $sth->execute(); 
            
            usleep($sleep);
            $sth = $dbh->prepare($query2);
            $sth->execute();
            
            #$sth = $dbh->prepare("select sum(a) from bar;");
            usleep($sleep);
            $dbh->commit();
            $query = "";
            $query2 = "";
            #last REDIRECT_LOOP;
            #print "bar\n";
        }
        catch
        {
            my ($err) = @_;
            $dbh->rollback();
            print $err;
            
            $fail_count++;
        };
        
        my $time = time;
        if($time > $end_time)
        {
            last;
        }

   }
   $dbh->disconnect;
   
   return {fail_count => $fail_count, transactions_count => $transactions_count, retry_count => $retry_count};
}

Fork();

=comment
my $isolation_levels = ['SERIALIZABLE','REPEATABLE READ','READ COMMITTED'];
#my $isolation_levels = ['READ COMMITTED'];
my $conc_num = [2,10,100];
#my $conc_num = [1000];
my $sleep = [0, 50, 500];
#my $sleep = [1000];

    for(my $i = 0; $i < @$isolation_levels; $i++)
    {
        for(my $s = 0; $s < @$sleep; $s++)
        {
            for(my $k = 0; $k < @$conc_num; $k++)
            {
                #$transaction_count = 1000;
                $transaction_count = $$conc_num[$k];
                Main($$retries[$r], $$isolation_levels[$i], $$sleep[$s], $$conc_num[$k]);
            }
        }
    }
=cut

