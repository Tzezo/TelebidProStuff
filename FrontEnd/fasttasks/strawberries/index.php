<form method="POST" action="">
K: <input type="text" value="<?=$_POST['k']?>" name="k" /><br />
L: <input type="text" value="<?=$_POST['l']?>" name="l" /><br />
R: <input type="text" value="<?=$_POST['r']?>" name="r" /><br />
<textarea name="strawberries"><?=$_POST['strawberries']?></textarea><br />
<input type="submit" name="submit" />
</form>
 
<?php 
	if(isset($_POST['submit'])){
		$kk = $_POST['k'];
		$l = $_POST['l'];
		$r = $_POST['r'];
		$strawberries = $_POST['strawberries'];
		$map = map($kk, $l);
 		$map = array_reverse($map, true);
		$strawberriesPosstions = explode("\r\n", $strawberries);
		foreach($strawberriesPosstions as $sp){
			$pos = explode(" ", $sp);
			$map[$pos[0] - 1][$pos[1] - 1] = 1;
		}
 
		$day = 1;
		$d = 2;
		while(true){
			foreach($map as $key=>$val){
				foreach($val as $k=>$v){
					if($v == $day){
						if($k-1 >= 0){
							$map[$key][$k-1] = $d;
						}
						if($k+1 <= $l-1){
							$map[$key][$k+1] = $d;
						}
						if($key-1 >= 0){
							$map[$key-1][$k] = $d;
						}
						if($key+1 <= $kk-1){
							$map[$key+1][$k] = $d;
						}
					}
				}
			}
			$day++;
			$d++;
			if($day > $r){
				break;
			}
		}
 
		//echo "<table border='1' style='border-color: blue'>";
		$count = 0;
		foreach($map as $key=>$val){
			//echo "<tr>";
				foreach($val as $k=>$v){
					if($v == 0){
						$count++;
					}
					$color = $v>0 ? "black" : "white";
					//echo "<td style='background: ".$color."'>".$v."</td>";
				}
			//echo "</tr>";
		}
		//echo "</table>";
	}
 
	echo $count;
	function map($row, $col){
		$map = array();
		for($i = 0; $i <= $row-1; $i++){
			for($r = 0; $r <= $col-1; $r++){
				$map[$i][$r] = 0;
			}
		}
		return $map;
	}
 
?>
