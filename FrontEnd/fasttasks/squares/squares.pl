use strict;
use warnings;
 
sub uniq {
    my %seen;
    grep !$seen{$_}++, @_;
}
 
sub GetSymbols(@)
{
    my @arr;
    for my $ref (@_)
    {
        for my $inner (@$ref)
        {
            if($inner ne "0")
            {
                $arr[@arr] = $inner;
            }
        }
    }
    my @uniq = uniq(@arr);    
    return @uniq;
}
 
sub PrintMatrix(@)
{
    print "\n";
    for my $ref (@_)
    {
        for my $inner (@$ref)
        {
            print $inner." ";
        }
        print "\n";
    }
    print "\n";
}
 
sub NextRow($$$)
{
    my $row = shift;
    my $col = shift;
    my $length = shift;
   
    $col++;
    if($col > $length-1){
        return $row+1;
    }
    return $row;
}
 
sub NextCol($$)
{
    my $col = shift;
    my $length = shift;
    
    $col++;
    
    if($col > $length - 1)
    {
        return 0;
    }
    return $col;
}
 
sub CheckRow($$$$)
{
    my $row = shift;
    my $symbol = shift;
    my $inArray = shift;
    my @matrix = @{$inArray};
    my $length = shift;
    
    for(my $i = 0; $i < $length; $i++)
    {
        if($matrix[$row][$i] eq $symbol){
            return 1;
        }
    }
    return 0;
}
 
sub CheckCol($$$$)
{
    my $col = shift;
    my $symbol = shift;
    my $inArray = shift;
    my @matrix = @{$inArray};
    my $length = shift;
 
    for(my $i = 0; $i < $length; $i++){
        if(scalar $matrix[$i][$col] eq scalar $symbol){
            return 1;
        }
    }
    
    return 0;
}
 
sub CheckSquare($$$$$)
{
    my $row = shift;
    my $col = shift;
    my $symbol = shift;
    my $n = shift;
    my $inArray = shift;
    my @matrix = @{$inArray};
 
    my $startRow = int($row / $n) * $n;
    my $startCol = int($col / $n) * $n;
 
    for(my $i = $startRow; $i < $startRow+$n; $i++){
        for(my $j = $startCol; $j < $startCol+$n; $j++){
            if($matrix[$i][$j] eq $symbol){
                return 1;
            }   
        }
    }
    return 0;
}
 
sub Solver($$$$$$)
{  
    my $inArray = shift;
    my @matrix = @{$inArray};
    $inArray = shift;
    my @symbols = @{$inArray};
    my $n = shift;
    my $length = shift;
    my $row = shift;
    my $col = shift;
 
    if($row == $length && $col == 0){
        print "\n\nSOLVED\n";
        PrintMatrix(@matrix);
        exit;
    }elsif(!$matrix[$row][$col]){
        while (my($key, $val) = each @symbols){
            if(CheckRow($row, $val, \@matrix, $length) == 1 || CheckCol($col, $val, \@matrix, $length) == 1 || CheckSquare($row, $col, $val, $n, \@matrix) == 1){
                next;
            }
            $matrix[$row][$col] = $val;
            Solver(\@matrix, \@symbols, $n, $length, NextRow($row, $col, $length), NextCol($col, $length));
            $matrix[$row][$col] = "0";
        }
    }else{
        Solver(\@matrix, \@symbols, $n, $length, NextRow($row, $col, $length), NextCol($col, $length));
    }
}
 
my $n = <STDIN>;
my $length = $n ** 2;
 
my @matrix;
for(my $i = 0; $i < $length; $i++)
{
    my $line = <STDIN>;
    my @arr = split(" ", $line);
    for(my $k = 0; $k < $length; $k++)
    {
        $matrix[$i][$k] = $arr[$k];
    }
}
 
 
my @symbols = GetSymbols(@matrix);
 
Solver(\@matrix, \@symbols, $n, $length, 0, 0);
