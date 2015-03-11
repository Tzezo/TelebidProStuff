use strict;
use warnings;
 
my $maxn = 1004;
my $maxm = 10004;
my $maxp = 30000;
 
my $n = 10;
my $m = 17;
 
my @data;
 
$data[16][0] = 4;
$data[16][1] = 5;
$data[16][2] = 6;
$data[15][0] = 1;
$data[15][1] = 10;
$data[15][2] = 1;
$data[14][0] = 2;
$data[14][1] = 10;
$data[14][2] = 13;
$data[13][0] = 7;
$data[13][1] = 8;
$data[13][2] = 16;
$data[12][0] = 3;
$data[12][1] = 6;
$data[12][2] = 19;
$data[11][0] = 4; 
$data[11][1] = 2;
$data[11][2] = 15;
$data[10][0] = 3;
$data[10][1] = 8;
$data[10][2] = 28;
$data[9][0] = 1;
$data[9][1] = 2;
$data[9][2] = 3;
$data[8][0] = 1;
$data[8][1] = 2;
$data[8][2] = 5;
$data[7][0] = 1;
$data[7][1] = 3;
$data[7][2] = 8;
$data[6][0] = 2;
$data[6][1] = 4;
$data[6][2] = 16;
$data[5][0] = 3;
$data[5][1] = 5;
$data[5][2] = 8;
$data[4][0] = 3;
$data[4][1] = 6;
$data[4][2] = 19;
$data[3][0] = 5;
$data[3][1] = 6;
$data[3][2] = 72;
$data[2][0] = 7;
$data[2][1] = 8;
$data[2][2] = 9;
$data[1][0] = 1;
$data[1][1] = 9;
$data[1][2] = 6;
$data[0][0] = 4;
$data[0][1] = 7;
$data[0][2] = 5;
 
@data = sort { $a->[2] <=> $b->[2] } @data;
 
my @parent;
 
sub getRel
{
	my ($node) = @_;
	if($parent[$node] == $node){
		return $node;
	}
	return $parent[$node] = getComp($parent[$node]);
}
 
sub solv
{
	my $lower = 1;
	my $upper = $maxp;
 
	for(my $i = 0; $i < $m; $i++){
		my $numComps = $n;
		for(my $c = 1; $c <= $n; $c++){
			$parent[$c] = $c;
		}
		for(my $c = $i; $c < $m; $c++){
			my $comp1 = getRel($data[$c][0]);
			my $comp2 = getRel($data[$c][1]);
			if($comp1 != $comp2){
				$parent[$comp1] = $comp2;
				if(--$numComps == 1){
					if($data[$c][2] - $data[$i][2] < $upper - $lower){
						$lower = $data[$i][2];
						$upper = $data[$c][2];
					}
					last;
				}
			}
		}
		if($numComps > 1){
			last;
		}
	}
	print $lower." ".$upper."\n";
} 
 
solv();
