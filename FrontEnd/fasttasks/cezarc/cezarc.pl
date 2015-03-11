use strict;
use warnings;
use Data::Dumper;
 
my %map = (
    'a' => 'a',
    'b' => 'b',
    'c' => 'c',
    'd' => 'd',
    'e' => 'e',
    'f' => 'f',
    'g' => 'g',
    'h' => 'h',
    'i' => 'i',
    'j' => 'j',
    'k' => 'k',
    'l' => 'l',
    'm' => 'm',
    'n' => 'n',
    'o' => 'o',
    'p' => 'p',
    'q' => 'q',
    'r' => 'r',
    's' => 's',
    't' => 't',
    'u' => 'u',
    'v' => 'v',
    'w' => 'w',
    'x' => 'x',
    'y' => 'y',
    'z' => 'z',
    );
 
 
my $in = <STDIN>;
my @words;
for(my $i = 0; $i < $in+0; $i++){
	chomp (my $val = <STDIN>);
    push @words, $val;
}
 
my %mapCopy = %map;
my $success = 0;
 
foreach my $key (keys %map){
	foreach my $k (keys %map){
		my @currWords = @words;
		if($key ne $k){
			my $mp = $map{$key};
			$map{$key} = $map{$k};
			$map{$k} = $mp;
			for(my $i = 0; $i <= $#words; $i++){
				for (my $j = 0; $j < length($currWords[$i]); $j++){
					my $w = substr($words[$i], $j, 1);
					substr($currWords[$i],$j,1) = $map{$w};
				}
			}
 
			my $isSorted = 0;
			for(my $z = 0; $z < $#currWords; $z++){
				if($currWords[$z] gt $currWords[$z+1]){
					$isSorted = 1;
					last;
				}
			}
 
			if($isSorted == 0){
				$success = 1;
	            last;
        	}
		}
	}
	if($success)
    {
        last;
    }
}
 
if($success){
	print "Yes\n";
	my @solution;
	while(my($key, $val) = each %map){
		push(@solution, $val);
	}
	@solution = sort @solution;
	for(my $i = 0; $i <= $#solution; $i++){
		print $map{$solution[$i]};
	}
}else{
	print "No\n";
}
print "\n\n";
