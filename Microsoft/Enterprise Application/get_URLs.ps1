#powershell como admin

Install-Module -Name AzureAD -Repository PSGallery -Force #instala modulo AzureAD

$domain = "domain" # substitua pelo dominio do qual deseja obter as urls dos apps

# retorna todos os Enterprise Application e as URL's associadas a eles
$applications = Get-AzureADServicePrincipal
# run then and show it's URLs 
foreach ($app in $applications) {
   # checks if the app got an Homepage, ReplyUrls or IdentifierUris
   $appUrls = @($app.Homepage, $app.ReplyUrls, $app.IdentifierUris)
   # shows all the Enterprise Applications and it's associate URLs
   Write-Host "Application: $($app.DisplayName)"
   foreach ($url in $appUrls) {
       if ($url) {
           Write-Host "URL: $url"
       }
   }
   Write-Host "---------------------------------------"
}