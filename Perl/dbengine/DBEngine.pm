package DBEngine;

use strict;
#use warnings;
use IO::File;
use Try::Tiny;
use Text::Trim qw(trim);
use Data::Dumper;
use Term::ANSIColor;
use Time::HiRes qw( time );
use Clone 'clone';
use Math::BigInt;
use Fcntl qw(:flock SEEK_END);
use Exporter;
#use File::stat;

our @ISA = qw(Exporter);
our @EXPORT = qw(&PrintRow);

our $dataTypes = {
    int => 1,
    text => 2
};

our $indexCache = {};


sub new {
  	my $class = shift;
    my $self  = {};         # allocate new hash for object
  	bless($self, $class);
  	return $self;
}

sub BigIntUnpack($)
{
    my ($int1,$int2)=unpack('NN',shift());
    my $sign=($int1&0x80000000);
    if($sign) {
        $int1^=-1;
        $int2^=-1;
        ++$int2;
        $int2%=2**32;
        ++$int1 unless $int2;
    }
    my $i=new Math::BigInt $int1;
    $i*=2**32;
    $i+=$int2;
    $i=-$i if $sign;

    return $i;
}


sub BigIntPack($)
{
    my $i = new Math::BigInt shift();
    my($int1,$int2)=do {
        if ($i<0) {
            $i=-1-$i;
            (~(int($i/2**32)%2**32),~int($i%2**32));
        } else {
            (int($i/2**32)%2**32,int($i%2**32));
        }
    };
    my $packed = pack('NN',$int1,$int2);
    return $packed;
}


sub lock_ex
{
    my ($fh) = @_;
    flock($fh, LOCK_EX) or die "Cannot lock $!\n";
    #print "Locked\n";
    # and, in case someone appended while we were waiting...
    seek($fh, 0, SEEK_END) or die "Cannot seek - $!\n";
}

sub lock_sh
{
    my ($fh) = @_;
    flock($fh, LOCK_SH) or die "Cannot lock";
    #seek($fh, 0, SEEK_END) or die "Cannot seek - $!\n";
}

sub unlock {
    my ($fh) = @_;
    flock($fh, LOCK_UN) or die "Cannot unlock - $!\n";
    #print "Unlocked\n";
}


sub CheckTableExists($$)
{
    my ($self, $table_name) = @_;

    if(-e "$table_name.bin")
    {
        return "";
    }

    return 1;
}

sub CreateTable($$$)
{
    my ($self, $table_name, $columns) = @_;

    if(!$self->CheckTableExists($table_name))
    {
        die "Table already exist";
    }

    my @bin_data;

    my @cols = split /,/, $columns;

    my $meta_data_length;

    for(my $i = 0; $i < @cols; $i++)
    {
        my $col = trim($cols[$i]);
        my @meta = split / /, $col;

        if($meta[1] ne "int" && $meta[1] ne "text")
        {
            die "Invalid type";
        }

        my $column_length = length $meta[0];

        push @bin_data, pack("i i a$column_length", $$dataTypes{ $meta[1] }, $column_length, $meta[0]);

        $meta_data_length += 4+4+$column_length;
    }

    my $fh;
    open $fh, ">>:raw", "$table_name.bin" or die $!;
    binmode($fh);

    my $meta_data = pack("i", $meta_data_length);

    print $fh $meta_data;

    for(my $i = 0; $i < @bin_data; $i++)
    {
        my $text = $bin_data[$i];
        print $fh $bin_data[$i];
    }

    close($fh);

    return 1;
}


sub GetTableColumns($)
{
    my ($table_name) = @_;

    my $fh;

    open $fh, "<", "$table_name.bin";

    my $read_to;
    read($fh, $read_to, 4) or die $!;
    $read_to = unpack("i", $read_to);

    my @columns;

    my $readed_bytes = 0;

    while(1)
    {
        my $bytes;

        $readed_bytes += read $fh, $bytes, 4;

        my $type = unpack("i", $bytes);

        $readed_bytes += read($fh, $bytes, 4);

        my $col_length = unpack("i", $bytes);

        my $col_name;
        $readed_bytes += read($fh, $col_name, $col_length);

        push @columns, {col_name => unpack("a$col_length", $col_name), col_type => $type};

        if($readed_bytes >= $read_to)
        {
            last;
        }
    }

    close($fh) or die $!;

    return @columns;
}

sub CreateIndex($$$;$)
{
    my ($self, $table_name, $col_name, $filter) = @_;

    if(!$filter)
    {
        $filter = "*";
    }

    my $index_file_name = $table_name.$col_name."index";

    #if(!$self->CheckTableExists($index_file_name))
    #{
    #    die "Table already exist";
    #}

    my @indexed_values;

    my $indexRow = sub {
        my($self, $fh, $row, $table_name, $filter, @index_data) = @_;

        my $col_val;

        for(my $i = 0; $i < @{ $$row{row} }; $i++)
        {
            if($$row{row}[$i]{col_name} eq $index_data[0])
            {
                $col_val = $$row{row}[$i]{content};
                last;
            }
        }

        push @indexed_values, [ $col_val, $$row{row_start_position} ];
    };

    $self->Select($table_name, $filter, $indexRow, $col_name);

    @indexed_values = sort { $$a[0] <=> $$b[0] } @indexed_values;
    

    my $fh;
    open $fh, ">", "$index_file_name.bin" or die $!;

    lock_ex($fh);

    while(my $index = shift @indexed_values)
    {
        my $success = 0;
        $success += print $fh pack 'i', $$index[0];
        $success += print $fh BigIntPack( $$index[1] );

        die "Failed index" unless $success == 2;
    }
    
    close $fh or die $!;

    return 1;
}


sub SearchIndex($$$$)
{
    my ($self, $table_name, $col_name, $term) = @_;
    my $index_record_size = 12;

    my $index_file_name = $table_name.$col_name."index";

    if($self->CheckTableExists($index_file_name))
    {
        return;
    }
    
    if(IsIndexOld($table_name, $col_name))
    {
        $self->CreateIndex($table_name, $col_name);    
    }

    my $fh;
    open $fh, "<", "$index_file_name.bin" or die $!;

    #my @filestat = stat("$index_file_name.bin");
    #print Dumper @filestat;
    #print $filestat[9]." ||| ".time."\n";
    #die;

    my $size = (stat($fh))[7];
    my $num_records = $size / $index_record_size;

    my $min_pos = 0;
    my $max_pos = $size;

    #print $size, " ", $num_records, " ", $min_pos, " ", $max_pos, "\n";

    my $position;

    my $blocks = ($max_pos / $index_record_size);

    $max_pos = $blocks;

    my $mid = int($blocks / 2) * 12;
    my $last_mid = 0;

    my $is_found = 0;
    my $positions = [];

    while($min_pos <= $max_pos)
    {

        $mid = int(($min_pos + $max_pos) / 2);


        seek $fh, $mid*12, 0;

        my $val;
        read $fh, $val, 4;
        $val = unpack("i", $val);


        read $fh, $position, 8;
        $position = BigIntUnpack($position);

        #print $val, " ", $position, " ", $term, "\n";

        if($val > $term)
        {
            #$mid = int(($mid / 12) / 2) * 12;
            $max_pos = $mid - 1;
        }
        elsif($val < $term)
        {
            #$mid += int(($mid / 12) / 2) * 12;;
            $min_pos = $mid + 1;
        }
        elsif($val == $term)
        {
            $is_found = 1;
            push @$positions, $position;
        }

        if($is_found)
        {
            my $fh_pos = tell $fh;
            my $direction = 1;

            while(1)
            {

                if($direction == 1)
                {
                    my $val;

                    read $fh, $val, 4;
                    $val = unpack("i", $val);

                    read $fh, $position, 8;
                    $position = BigIntUnpack($position);

                    if($val == $term)
                    {
                        push @$positions, $position;
                    }
                    else
                    {
                        $direction = 0;
                        $fh_pos = $fh_pos - 12;
                        seek $fh, $fh_pos, 0;
                    }
                }
                else
                {
                    $fh_pos = $fh_pos - 12;
                    seek $fh, $fh_pos, 0;

                    my $val;
                    read $fh, $val, 4;
                    $val = unpack("i", $val);

                    read $fh, $position, 8;
                    $position = BigIntUnpack($position);

                    if($val == $term)
                    {
                        push @$positions, $position;
                    }
                    else
                    {
                        last;
                    }
                }

            }
            last;
        }
        #$last_mid = $mid;
    }

    close($fh) or die $!;
    
    if(@$positions < 1 && IsIndexOld($table_name, $col_name))
    {
        return undef;
    }
    
    return $positions;
}


sub IsIndexOld($$)
{
    my ($table_name, $col_name) = @_;
    
    my $index_file_name = $table_name.$col_name."index.bin";

    if(-e $index_file_name && -e "$table_name.bin")
    {
        my @filestat_table = stat("$table_name.bin");
        my @filestat_index = stat($index_file_name);

        if($filestat_table[9] > $filestat_index[9])
        {
            return 1;
        }
    }

    return 0;
}

sub CheckForIndex($$$$)
{
    my ($self, $table_name, $col_name, $col_val) = @_;

    my $index_file_name = $table_name.$col_name."index";

    if($self->CheckTableExists($index_file_name))
    {
        return "";
    }

    if(!defined $$indexCache{$index_file_name})
    {
        $$indexCache{$index_file_name} = {};
    }

    if(defined $$indexCache{$index_file_name}{$col_val})
    {
        return $$indexCache{$index_file_name}{$col_val};
    }

    my $position = ($col_val-1)*12;
    #my $position;

    my $fh;

    open $fh, "<", "$index_file_name.bin";

    seek $fh, $position, 0;

    my $bytes;

    my @return = ();

    $$indexCache{$index_file_name} = {};

    while(1)
    {
        if(eof)
        {
            last;
        }

        $position += read $fh, $bytes, 4;

        my $unpacked = unpack("i", $bytes);


        my $row_position;
        $position += read $fh, $row_position, 8;

        $row_position = BigIntUnpack($row_position);

        if(!defined $$indexCache{$index_file_name}{$unpacked})
        {
            $$indexCache{$index_file_name}{$unpacked} = [];
        }

        #push @{ $$indexCache{$index_file_name}{$unpacked} }, $new_val;
        $$indexCache{$index_file_name}{$unpacked}[0] = $row_position;

    }

    close($fh) or die $!;

    if(defined $$indexCache{$index_file_name}{$col_val})
    {
        return $$indexCache{$index_file_name}{$col_val};
    }

    return "";
}


sub InsertIntoTable($$$@)
{
    my ($self, $fh, $table_name, @data) = @_;

    my $return_hash = {};

    if($self->CheckTableExists($table_name))
    {
        die "Table doesn't exist";
    }

    my @columns = GetTableColumns($table_name);

    my $data_hash = {};

    for(my $i = 0; $i < @data; $i++)
    {
        my @col_data = split /=/, $data[$i];

        $$data_hash{$col_data[0]} = $col_data[1];
    }

    my $is_insert = 0;

    if(!$fh)
    {
        $is_insert = 1;
        open $fh, "+<", "$table_name.bin" or die $!;

        #UNBUFF
        # my $old_fh = select($fh);
        # select($old_fh);
        #UNBUFF

        lock_ex($fh);
        
        seek $fh, 0, 2;
    }

    my $start_position = tell $fh;
    
    print $fh pack("i", 1);

    my $insert_data;

    my $row_arr = [];

    for(my $i = 0; $i < @columns; $i++)
    {
        if(!defined $$data_hash{$columns[$i]{col_name}})
        {
            die "Column doensn't exists";
        }

        my $col_name_length = length $columns[$i]{col_name};
        my $content_length = length $$data_hash{$columns[$i]{col_name}};

        my $content = $$data_hash{$columns[$i]{col_name}};
        my $pack_template;

        if($$dataTypes{int} == $columns[$i]{col_type})
        {
            $pack_template = "i";
            $content_length = 4;
            $content = $content+0;
        }
        elsif($$dataTypes{text} == $columns[$i]{col_type})
        {
            $pack_template = "a$content_length";
        }

        print $fh pack("i a$col_name_length i $pack_template", $col_name_length, $columns[$i]{col_name}, $content_length, $content);

        push @$row_arr, {col_name => $columns[$i]{col_name}, content => $content};
    }

    my $end_position = tell $fh;

    seek $fh, $start_position, 0;
    print $fh pack("i", 0);

    $return_hash = {row => $row_arr, row_start_position => $start_position, row_end_position => $end_position};

    if($is_insert)
    {
       seek $fh, $end_position, 0;
       close($fh) or die $!;
    }

    return $return_hash;
}


sub Select($$$;$@)
{
    my ($self, $table_name, $filter, $callback, @callback_data) = @_;

    my $return_hash = {};

    my @filt;
    if($filter ne "*")
    {
        @filt = split /=/, $filter;
    }

    my @columns = GetTableColumns($table_name);

    my $fh;
    open $fh, "+<", "$table_name.bin";


    ##UNBUFF

    # my $old_fh = select($fh);
    # $| = 1;
    # select($old_fh);

    ###UNBUFF

    lock_sh($fh);

    my $bytes;

    read($fh, $bytes, 4);
    my $meta_data_length = unpack("i", $bytes);
    my $offset = $meta_data_length + 4;

    my $has_index = 0;

    if(@filt > 0)
    {
        $has_index = $self->SearchIndex($table_name, $filt[0], $filt[1]);

        if($has_index && @$has_index > 0)
        {
            $has_index = clone($has_index);
        }
    }

    seek $fh, $offset, 0;

    my $readed_bytes = $offset;

    #$$return_hash{table_info} = [];

    my $index = 0;

    my $filesize = -s "$table_name.bin";

    while(1)
    {
        if($readed_bytes >= $filesize)
        {
            last;
        }

        if($has_index && @$has_index > 0)
        {
            if(!defined $$has_index[$index])
            {
                last;
            }
            $readed_bytes = $$has_index[$index];
            seek $fh, $readed_bytes, 0;
        }

        # print "Has index $has_index !!!!!";
        my $row;

        my $print_row = 0;

        my $readed_bytes_row = 0;

        my $is_deleted;
        $readed_bytes_row += read($fh, $is_deleted, 4);
        $is_deleted = unpack("i", $is_deleted);

        my $row_arr = [];

        #if($index > 10500)
        #{
        #    die;
        #}

        for(my $i = 0; $i < @columns; $i++)
        {
            my $col_name_length;

            $readed_bytes_row += read($fh, $col_name_length, 4);

            $col_name_length = unpack("i", $col_name_length);

            my $col_name;

            $readed_bytes_row += read($fh, $col_name, $col_name_length);
            $col_name = unpack("a$col_name_length", $col_name);

            my $cont_length;

            $readed_bytes_row += read($fh, $cont_length, 4);

            $cont_length = unpack("i", $cont_length);

            my $cont;
            my $data_type;
            $readed_bytes_row += read($fh, $cont, $cont_length);

            if($$dataTypes{int} == $columns[$i]{col_type})
            {
                $data_type = "int";
                $cont = unpack("i", $cont);
            }
            elsif($$dataTypes{text} == $columns[$i]{col_type})
            {
                $data_type = "text";
                $cont = unpack("a$cont_length", $cont);
            }

            if($columns[$i]{col_name} ne $col_name)
            {
                die "INTERR";
            }

            if($filter ne "*")
            {
                if($data_type eq "text" && $col_name eq $filt[0] && $cont eq $filt[1])
                {
                    $print_row = 1;
                }
                elsif($data_type eq "int" && $col_name eq $filt[0] && $cont == $filt[1])
                {
                    $print_row = 1;
                }
            }
            else
            {
                $print_row = 1;
            }

            push @$row_arr, {col_name => $col_name, content => $cont};

        }

        $readed_bytes += $readed_bytes_row;

        my $start_position = $readed_bytes - $readed_bytes_row;

        if($print_row == 1 && $is_deleted == 0)
        {

            my $fh_pos = tell $fh;

            $callback->($self, $fh, {row => $row_arr, row_start_position => $start_position, row_end_position => $readed_bytes}, $table_name, $filter, @callback_data);

            seek $fh, $fh_pos, 0;
        }

        $index++;

    }
    close($fh);

    return $return_hash;
}


sub Delete($$$)
{
    my ($self, $table_name, $filter) = @_;

    my $deleteRows = $self->Select($table_name, $filter, \&DeleteRow);

}


sub Update($$$@)
{

    my ($self, $table_name, $filter, @update_data) = @_;
    my $updateRows = $self->Select($table_name, $filter, \&UpdateRow, @update_data);
    #TODO - Index-a da se update-va
}


sub UpdateRow($$$$$@)
{
    my($self, $fh, $row, $table_name, $filter, @update_data) = @_;

    lock_ex($fh);

    my $data_hash = {};

    for(my $i = 0; $i < @update_data; $i++)
    {
        my @col_data = split /=/, $update_data[$i];

        $$data_hash{$col_data[0]} = $col_data[1];
    }

    #seek $fh, $$row{start_position}, 0;

    #Delete($table_name, $filter, $fh);

    $self->DeleteRow($fh, $row, $table_name);

    my @update;

    for(my $k = 0; $k < @{ $$row{row} }; $k++)
    {
        my $col = $$row{row}[$k];

        if(!defined $$data_hash{ $$col{col_name} })
        {
            push @update, "$$col{col_name}=$$col{content}";
        }
        else
        {
            push @update, "$$col{col_name}=$$data_hash{ $$col{col_name} }";
        }
    }

    seek $fh, 0, 2;

    $self->InsertIntoTable($fh, $table_name, @update);

    # print "Wake Up\n\n";


    #sleep 5;

    #unlock($fh);

    return 1;
}


sub DeleteRow($$$$;$@)
{
    my($self, $fh, $row, $table_name) = @_;

    lock_sh($fh);
    #my $fh;
    #open $fh, "+<", "$table_name.bin";

    seek $fh, $$row{row_start_position}, 0;
    print $fh pack("i", 1);

    #close($fh) or die $!;
    return 1;
}


sub PrintRow($$$;@)
{
    my($self, $fh, $row) = @_;

    for(my $k = 0; $k < @{ $$row{row} }; $k++)
    {
        print color "green";
        print "$$row{row}[$k]{col_name}: ";
        print color "reset";
        print $$row{row}[$k]{content};
        print "\n";
    }

    print color "red";
    print "----------------------------------------------\n";
    print color "reset";

}

1;
