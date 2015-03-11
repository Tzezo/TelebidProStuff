<form method="POST" action="">
	n: <input type="text" name="n" value="<?=$_POST['n']?>" /><br />
	a: <input type="text" name="a" value="<?=$_POST['a']?>" /><br />
	b: <input type="text" name="b" value="<?=$_POST['b']?>" /><br />
	c: <input type="text" name="c" value="<?=$_POST['c']?>" /><br />
	<input type="submit" name="submit" /> 
</form>

<?php 
	set_time_limit(0);
	if(isset($_POST['submit'])){
		$n = $_POST['n'];
		$a = $_POST['a'];
		$b = $_POST['b'];
		$c = $_POST['c'];

		$max = 100000;

		if(($n > 0 && $a > 0 && $b > 0 && $c > 0) ){

		}else{
			echo "Invalid input!";
			exit;
		}

		if( ($n >= $max || $a >= $max || $b >= $max || $c >= $max) || ($n < 0 || $a <0 || $b < 0 || $c < 0) ){
			echo "Invalid input!";
			exit;
		}


		$points = 0;

		$big = $a;
		$small = $b;
		if($b > $a){
			$big = $b;
			$small = $a;
		}

		$i = 0;
		$td = null;
		$z = 0;
		$arr = array();
		while($i < $n){
			$i = $i+$big;
			if($i > $n){
				break;
			}
			$k = 0;
			$p = 0;
			$k = $z*$small;
			while($k < $n){
				$k = $k + $small;
				
				if($k > $n){
					break;
				}

				$dif = $i - $k;
				if($dif < 0){
					$dif = -$dif;
				}
				if($dif == $c){
					$points = $points + $c;

					if($k > $i){
						$arr[$i] = $k;
					}else{
						$arr[$k] = $i;
					}
					
					$p++;
				}
				if($p >= 2){
					break;
				}
				
			}
			$z++;
		}

		$res = $n - $points;
		echo $res;
		echo "<br /><br /><table style='width: 800px; height: 10px;' cellspacing='0'> <tr>";
		for($i = 0; $i < $n; $i++){
			$td = "<td style='background: #000'></td>";
			if($arr[$i] > 0){
				$td = "<td style='background: red'></td>";
			}
			echo $td;
		}
		echo "</tr></table>";
	}
?>
