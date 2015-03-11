<form method="POST" action="">
<input type="text" name="n" value="<?=$_POST['n']?>"/><br />
<textarea name="square"><?=$_POST['square']?></textarea><br />
<input type="submit" name="submit" />
</form>
 
<?php
	if(isset($_POST['submit'])){
		$n = $_POST['n'];
		$length = pow($n, 2);
		$square = $_POST['square'];
		$map = str_replace("<br />", " ", nl2br($square));
		$arr = explode(" ", $map);
		$map = map($arr, $length);
		$symbols = getSymbols($arr);
		solver($map, $symbols, $n, $length, 0, 0);
	}
 
	function solver($map, $symbols, $n, $length, $row, $col){
		$mapLength = count($map);
		foreach($symbols as $sy){
			if($sy != "0" AND strlen($sy) > 0){
				if($row == $length){
					echo "<br />";
					foreach($map as $mp){
						foreach($mp as $m){
							echo $m." ";
						}
						echo "<br />";
					}
					echo "<br /><br />";
					exit;

				}elseif($map[$row][$col] == "0"){
					if(checkRow($row, $sy, $map, $length) || checkCol($col, $sy, $map, $length) || checkSquare($row, $col, $sy, $n, $map)){
						continue;
					}
					$map[$row][$col] = $sy;



					solver($map, $symbols, $n, $length ,nextRow($row, $col, $length), nextCol($col, $length));
					$map[$row][$col] = "0";
				}else{
					solver($map, $symbols, $n, $length ,nextRow($row, $col, $length), nextCol($col, $length));
				}
			}
		}
	}
 
	function getSymbols($arr){
		$trimmed_array=array_map('trim',$arr);
		$ar = array_unique($trimmed_array);
		return $ar;
	}

	function checkRow($row, $symbol, $map, $length){
		for($i = 0; $i < $length; $i++){
			if($map[$row][$i] == $symbol){
				return true;
			}
		}

		return false;
	}

	function checkCol($col, $symbol, $map, $length){
		for($i = 0; $i < $length; $i++){
			if($map[$i][$col] == $symbol){
				return true;
			}
		}

		return false;
	}

	function checkSquare($row, $col, $sy, $n, $map){
		$startRow = (int)($row / $n) * $n;
		$startCol = (int)($col / $n) * $n;
		for($i = $startRow; $i < $startRow + $n; $i++){
			for($j = $startCol; $j < $startCol+$n; $j++){
				if($map[$i][$j] == $sy){
					return true;
				}
			}
		}

		return false;		
	}

	function nextCol($col, $length){
		$col++;
		if($col > $length-1){
			return 0;
		}
		return $col;
	}

	function nextRow($row, $col, $length){
		$col++;
		if($col > $length-1){
			return $row+1;
		}
		return $row;
	}
 
	function map($arr, $lenth){
		$map = array();
		$i = 0;
		$m = 0;
		foreach($arr as $a){

				$map[$m][$i] = trim($a);
				if($i >= $lenth-1){
					$m++;
					$i = -1;
					if($m >= $lenth){
						break;
					}
				} 
				$i++;
			
		}
		return $map;
	}
?>
