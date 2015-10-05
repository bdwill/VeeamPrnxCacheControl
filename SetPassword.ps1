$File = "c:\veeamprnx\fvp_enc_pass.txt"
$inputPsswd=Read-Host -AsSecureString "Enter Password"
[Byte[]] $key = (1..16)
$Password = $inputPsswd | ConvertTo-SecureString -AsPlainText -Force
$Password | ConvertFrom-SecureString -key $key | Out-File $File