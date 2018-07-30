#!/usr/local/bin/php
<?php
$str = getenv("STRING");
echo base64_encode($str);
exit(0);
?>
