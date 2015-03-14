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
use Search::Binary;

our @ARGV;

 
our $dataTypes = {
    int => 1,
    text => 2
};

our $indexCache = {};


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
    print "Unlocked\n";
}

 
sub CheckTableExists($)
{
    my ($table_name) = @_;
    
    if(-e "$table_name.bin")
    {  
        return ""; 
    }
    
    return 1;
}
 
sub CreateTable($$)
{
    my ($table_name, $columns) = @_;
    
    if(!CheckTableExists($table_name))
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

# sub CreateIndex($$;$)
# {
#     my ($table_name, $col_name, $filter) = @_;

#     if(!$filter)
#     {
#         $filter = "*";
#     }

#     my $index_file_name = $table_name.$col_name."index";

#     if(!CheckTableExists($index_file_name))
#     {
#         die "Table already exist";
#     }

#     my $fh; 
#     open $fh, ">>:raw", "$index_file_name.bin" or die $!;
#     binmode($fh);
#     close($fh) or die $!;

#     Select($table_name, $filter, \&IndexRow, $col_name);
# }


sub CreateIndex($$;$)
{
    my ($table_name, $col_name, $filter) = @_;

    if(!$filter)
    {
        $filter = "*";
    }

    my $index_file_name = $table_name.$col_name."index";

    if(!CheckTableExists($index_file_name))
    {
        die "Table already exist";
    }

    my @indexed_values;

    my $indexRow = sub {
        my($fh, $row, $table_name, $filter, @index_data) = @_;

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

    Select($table_name, $filter, $indexRow, $col_name);

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

    return 1;
}


sub SearchIndex($$$)
{
    my ($table_name, $col_name, $term) = @_;
    my $index_record_size = 12;
    
    my $index_file_name = $table_name.$col_name."index";

    if(CheckTableExists($index_file_name))
    {
        return;
    }

    my $fh;
    open $fh, "<", "$index_file_name.bin" or die $!;


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

    #print "Found Position: $position\n";
   
    # my $position = binary_search(0, $num_records, $term, sub { 
    #     my ($fh, $term, $pos) = @_;
    #     my $seek_to = $pos * $index_record_size; 
    #     my $raw;
  
    #     seek($fh, $seek_to, 0);

    #     my $bytes_read = read $fh, $raw, $index_record_size;

    #     die "Oooppss" unless $bytes_read == $index_record_size;

    #     my ($value, $address) = unpack "iA*", $raw;
    #     $address = BigIntUnpack($address);

    #     print $value, " ", $address, " ", $term, "\n"; 

    #     #print "ADDRESS: $address \n";

    #     return ($value <=> $term, tell $fh / 12);
    # }, $fh, 12);

    close($fh) or die $!;

    # print $position;

    #print Dumper $positions;
    #exit;

    return $positions;
}


# sub IndexRow($$$@)
# {
#     my($row, $table_name, $filter, @index_data) = @_;

#     my $index_file_name = $table_name.$index_data[0]."index";

#     my $fh;
#     open $fh, "+<", "$index_file_name.bin" or die $!;

#     my $col_val;

#     for(my $i = 0; $i < @{ $$row{row} }; $i++)
#     {
#         if($$row{row}[$i]{col_name} eq $index_data[0])
#         {
#             $col_val = $$row{row}[$i]{content};
#             last;
#         }
#     }

#     #print "$col_val $table_name $filter, $index_data[0]\n";
    
#     my $packed_start_position = BigIntPack($$row{row_start_position});

#     my $index_row = pack("i", $col_val).$packed_start_position;

#     seek $fh, ($col_val * 12), 0;

#     #print $fh pack("i i i", $col_val, substr($$row{row_start_position}, 0, 8), substr($$row{row_start_position}, 8, 8));
#     print $fh $index_row;

#     close($fh) or die $!;

#     if(!defined $$indexCache{$index_file_name}{$col_val})
#     {
#         $$indexCache{$index_file_name}{$col_val} = [];
#     }
#     #push @{ $$indexCache{$index_file_name}{$col_val} }, $$row{row_start_position};
#     $$indexCache{$index_file_name}{$col_val}[0] = $$row{row_start_position};

#     return 1;
# }

sub UpdateIndex($$;$$)
{
    # my ($row, $table_name, $filter) = @_;

    # if(!$filter)
    # {
    #     $filter = "*";
    # }


    # for(my $i = 0; $i < @{ $$row{row} }; $i++)
    # {
    #     my $col_name = $$row{row}[$i]{col_name};

    #     my $index_file_name = $table_name.$col_name."index";

    #     if(CheckTableExists($index_file_name))
    #     {
    #         next;
    #     }

    #     IndexRow($row, $table_name, "*", $col_name);
    # }
}


sub CheckForIndex($$$)
{
    my ($table_name, $col_name, $col_val) = @_;

    my $index_file_name = $table_name.$col_name."index";

    if(CheckTableExists($index_file_name))
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


sub InsertIntoTable($$@)
{
    my ($fh, $table_name, @data) = @_;
    
    my $return_hash = {};

    if(CheckTableExists($table_name))
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
        open $fh, ">>", "$table_name.bin" or die $!;

        my $old_fh = select($fh);
        $| = 1;
        select($old_fh);


        lock_ex($fh);
    }

    my $start_position = tell $fh;

    print $fh pack("i", 0);

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

    $return_hash = {row => $row_arr, row_start_position => $start_position, row_end_position => $end_position};

    if($is_insert)
    {
       close($fh) or die $!;
    }

    UpdateIndex($return_hash, $table_name);
    
    return $return_hash;
}


sub Select($$;$@)
{
    my ($table_name, $filter, $callback, @callback_data) = @_;
    
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

    my $old_fh = select($fh);
    $| = 1;
    select($old_fh);

    ###UNBUFF

    lock_sh($fh);
    
    my $bytes; 
 
    read($fh, $bytes, 4);
    my $meta_data_length = unpack("i", $bytes);
    my $offset = $meta_data_length + 4;

    my $has_index = 0;

    # if(@filt > 0)
    # {
    #     $has_index = CheckForIndex($table_name, $filt[0], $filt[1]);

    #     if($has_index && @$has_index > 0)
    #     {
    #         $has_index = clone($has_index);
    #     }
    # }

    if(@filt > 0)
    {
        $has_index = SearchIndex($table_name, $filt[0], $filt[1]);

        if($has_index && @$has_index > 0)
        {
            $has_index = clone($has_index);
        }
        
    }
    
    seek $fh, $offset, 0;

    my $readed_bytes = $offset;

    $$return_hash{table_info} = [];

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
        
        my $row;
    
        my $print_row = 0;
        
        my $readed_bytes_row = 0;

        my $is_deleted;
        $readed_bytes_row += read($fh, $is_deleted, 4);
        $is_deleted = unpack("i", $is_deleted); 
    
        my $row_arr = [];

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
            #push @{ $$return_hash{table_info} }, {row => $rowArr, row_start_position => $start_position, row_end_position => $readedBytes};
            $callback->($fh, {row => $row_arr, row_start_position => $start_position, row_end_position => $readed_bytes}, $table_name, $filter, @callback_data);
            
            seek $fh, $fh_pos, 0;
        }

        $index++;
    }
    close($fh);

    return $return_hash;
}


sub Delete($$)
{
    my ($table_name, $filter, $fh) = @_;
    
    my $deleteRows = Select($table_name, $filter, \&DeleteRow);

}
 

sub Update($$@)
{

    my ($table_name, $filter, @update_data) = @_;

    my $updateRows = Select($table_name, $filter, \&UpdateRow, @update_data);
    
}


sub UpdateRow($$$$@)
{
    my($fh, $row, $table_name, $filter, @update_data) = @_;

    lock_ex($fh);

    my $data_hash = {};

    for(my $i = 0; $i < @update_data; $i++)
    {
        my @col_data = split /=/, $update_data[$i];
        
        $$data_hash{$col_data[0]} = $col_data[1];
    }
    
    #seek $fh, $$row{start_position}, 0;

    #Delete($table_name, $filter, $fh);

    DeleteRow($fh, $row, $table_name);

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

    InsertIntoTable($fh, $table_name, @update);


    # if($ARGV[1] eq "sleep")
    # {
    #     print "Sleeping\n";
    #     sleep 10;
    #     print "Wake Up\n\n";
    # }

    #sleep 5;

    #unlock($fh);

    return 1;
}


sub DeleteRow($$$;$@)
{
    my($fh, $row, $table_name) = @_;

    lock_ex($fh);
    #my $fh;
    #open $fh, "+<", "$table_name.bin";

    seek $fh, $$row{row_start_position}, 0;
    print $fh pack("i", 1);

    #close($fh) or die $!;
    return 1;
}


sub PrintRow($$;@)
{  
    my($fh, $row) = @_;

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




try {

    my $command = $ARGV[0];
    my $count = $ARGV[1];

    my $start = time();


    if($command eq "CreateTable")
    {
        CreateTable("test6", "id int, id2 int, id3 int, id4 int, id5 int, name text, name2 text, name3 text");     
    }

    if($command eq "Delete")
    {
        Delete("test5", "id=7"); 
    }
    #Delete("test5", "id=19998");   
    #Delete("test5", "id=19997"); 

    if($command eq "Select")
    {

        my $rows = Select("test5", "id=8", \&PrintRow);

    }
    

    # for(my $i = 0; $i < @{ $$rows{table_info} }; $i++)
    # {
    #     for(my $k = 0; $k < @{ $$rows{table_info}[$i]{row} }; $k++)
    #     {
    #         print color "green";
    #         print "$$rows{table_info}[$i]{row}[$k]{col_name}: ";
    #         print color "reset";
    #         print $$rows{table_info}[$i]{row}[$k]{content};
    #         print "\n";
    #     }

    #     print color "red";
    #     print  "----------------------------------------------\n";
    #     print color "reset"; 
    # }

    
    #Update("test6", "id=19991", "name3=Tzezo123123122");
    
    my $one = "kO1zi6OZa7kF0JXVVzeaA5f1t9Zl5lJmtZCWo52erCASScLgtYDKZZjlqcDxkJqYJa7jiXsld4lqLMnMpObpsioKY9Un0rOvwvoQW5Ia0jLMw3zgEWxH7tQBH7AROJ9rcnQsuM3UvDRclDko3avs6yfA7zGortzhRigKga2kLsTUECnCe4zj8y0NmPuwm9805MkJQw9bHtG3pIyxN7sQ0UKJvHfLky7Zmneu4cGu2hgt1YrI5bpcoOhOUOd8eoDyL1KFBfrPqMXMOgAMtYOAAFJYz8EZHaCf3UTzDzWkEV7sDmOxtnxZDLreCEQObf4ZfFGAW4vThBj3uyw7BPGYHZINXP5OCOcNmfDSV79kkBKggHawnpqt8xrB3hVi82kjyOEaKt0NJfUtSv3Xox7k3z8wU5M4Ba9UqqKZfYuiXeudRGc8gqU96eFVKNNinZInJ2Ve4wgsOzhPOpQHHubnGoQMS99DAI5pPL4mJafoV1tVRCdJdyaaY2uMdM12K98HbqSu9zBPsrmlnjkI5AbqVKbvn9xxoEvxn4MoiUL4sNti9T7xJuOuN4TkA9VriInc4Zc0JRWpTxjPrVwThgNkLmw99Y5xYvLWN1sVmrWeXEoaSCXY85Zot2IaLa9aVlzxNAelLev8hVuvWKj9wd9vuStAAA4OXDLqrtkJL4ugmPgutsjnRdygk2tpPMJXKTzh8q9Xe4l2IJP3E5NQ7UfLE76qyqWakdEHdiK37EEdY9dhbPo4pBZIPdLprdPIwXa0hK87AngcAQCN42LdqMofTOh29B92BKtWWfkN5E7Xoz3AajwVivwWEj59RWAzUjNUiXfbsidefINWQYJbiZdrlUJy6t69GkQyNHMcrQzjN69g37CV2dPB44fFIwsuQIf2lMvkOBW2C2pGrxqjzTev2ax2pUxnAGbJsBoW9niaVEpjlTQ1IZ51qGkUrSfefmWsEekN62HmM310hWk6kZiq0jgQycw8BW1BeMrgXlwqVguPw7uwSXLt8anU85GxQS4d";
    my $ten = "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";
    my $onehundred = "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";

    #InsertIntoTable(undef, "test5", "id=30002", "id2=5", "id3=100", "id4=8", "id5=5", "name=Test", "name2=TEst2", "name3=TEst343");

    if($command eq "Insert")
    {

        for(my $i = 1; $i < $count; $i++)
        {    
            my $z = $i + 3;

            InsertIntoTable(undef, "test6", "id=$i", "id2=$z", "id3=3", "id4=4", "id5=5", "name=$one", "name2=$ten", "name3=$onehundred");
            
            if($i % 10000 == 0)
            {
                print $i."\n";
            }
        }

    }

    ######UPDATE

    #flock($fh, LOCK_EX) or die "Cloud not lock file!";

    if($command eq "Update")
    {

        my $z = 0;
        for(my $i = 1; $i < 10; $i++)
        {    
            Update("test5", "id=$i", "id2=2", "id3=3", "id4=4", "id5=5", "name=$ten", "name2=$one", "name3=${onehundred}Tzezo1");
            
            if($i % 10 == 0)
            {
                print $i."\n";
            }

            # if($i == 59999)
            # {
            #     $i = 1;
            #     $z++;
            # }

            # if($z > 1)
            # {
            #     last;
            # }
        }

    }
    #CreateIndex("test6", "id");

    #print SearchIndex("test5", "id", 345);
    #print "\n";

    my $end = time();
    printf("%.5f\n", $end - $start);

} catch {
    print $_;
};
