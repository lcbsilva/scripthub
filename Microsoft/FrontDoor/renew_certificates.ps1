# Azure Front Door: revalidacao automatica de PendingRevalidation

# - Processa um por um
# - Regenera validation token
# - Atualiza somente TXT _dnsauth
# - Valida Azure DNS
# - Valida DNS publico
# - Nao toca em Approved
# - Pula DNS fora da subscription/RG autorizados
    
 
$ErrorActionPreference = "Continue"
 
$SubscriptionId = "YOUR_SUBSCRIPTION_ID"
$FrontDoorRG    = "RESOURCE_GROUP_FRONTDOOR"
$Profile        = "FRONTDOOR_PROFILE_NAME"
$AllowedDnsRG   = "DNS_RESOURCE_GROUP_ALLOWED"
 
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$LogFile   = "./AFD-PROD-$Timestamp.csv"
 

# VALIDAR SUBSCRIPTION
    
 
az account set --subscription $SubscriptionId
 
if ($LASTEXITCODE -ne 0) {
    throw "Falha ao selecionar subscription."
}
 
$CurrentSubscription = az account show --query id -o tsv
 
if ($CurrentSubscription -ne $SubscriptionId) {
    throw "SUBSCRIPTION INCORRETA. CANCELADO."
}
 
    
# BUSCAR PENDENTES NOVAMENTE
    
 
$Domains = @(
    az afd custom-domain list `
        --resource-group $FrontDoorRG `
        --profile-name $Profile `
        -o json |
    ConvertFrom-Json |
    Where-Object {
        $_.domainValidationState -eq "PendingRevalidation"
    }
)
 
Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " FD - PRODUCAO" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Total PendingRevalidation: $($Domains.Count)" -ForegroundColor Yellow
Write-Host ""
 
$Domains |
    Select-Object name, hostName |
    Format-Table -AutoSize
 
if ($Domains.Count -eq 0) {
    Write-Host "Nada para processar." -ForegroundColor Green
    return
}
 
Write-Host ""
Write-Host "O script vai alterar somente _dnsauth dos dominios elegiveis." -ForegroundColor Yellow
Write-Host "Panamby/outros DNS fora da subscription serao ignorados." -ForegroundColor Yellow
Write-Host ""
 
$Confirm = Read-Host "Digite EXECUTAR para continuar"
 
if ($Confirm -ne "EXECUTAR") {
    Write-Host "Cancelado." -ForegroundColor Yellow
    return
}
 
$Results = @()
$Index = 0
 
    
# PROCESSAR
    
 
foreach ($Domain in $Domains) {
 
    $Index++
 
    $ResourceName = $Domain.name
    $HostName     = $Domain.hostName
 
    $DnsZone     = $null
    $DnsRG       = $null
    $OldToken    = $null
    $NewToken    = $null
    $OldDnsToken = $null
    $Expiration  = $null
 
    Write-Host ""
    Write-Host "========================================================" -ForegroundColor DarkGray
    Write-Host "[$Index/$($Domains.Count)] $HostName" -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor DarkGray
 
    try {
 
          
        # CONSULTA ATUAL
          
 
        $BeforeJson = az afd custom-domain show `
            --resource-group $FrontDoorRG `
            --profile-name $Profile `
            --custom-domain-name $ResourceName `
            -o json
 
        if ($LASTEXITCODE -ne 0) {
            throw "Erro consultando Custom Domain."
        }
 
        $Before = $BeforeJson | ConvertFrom-Json
 
          
        # TRAVAS
          
 
        if ($Before.domainValidationState -ne "PendingRevalidation") {
            throw "SKIP: estado atual = $($Before.domainValidationState)"
        }
 
        if ($Before.tlsSettings.certificateType -ne "ManagedCertificate") {
            throw "SKIP: certificado nao e ManagedCertificate."
        }
 
        $DnsZoneId = $Before.azureDnsZone.id
 
        if (-not $DnsZoneId) {
            throw "SKIP: Azure DNS Zone nao vinculada."
        }
 
        if (
            $DnsZoneId -notmatch
            "/subscriptions/([^/]+)/resourceGroups/([^/]+)/providers/Microsoft.Network/dnsZones/(.+)$"
        ) {
            throw "SKIP: DNS Zone ID inesperado."
        }
 
        $DnsSubscription = $Matches[1]
        $DnsRG           = $Matches[2]
        $DnsZone         = $Matches[3]
 
        Write-Host "DNS Zone : $DnsZone"
        Write-Host "DNS RG   : $DnsRG"
 
          
        # BLOQUEAR OUTRA SUBSCRIPTION
          
 
        if ($DnsSubscription.ToLower() -ne $SubscriptionId.ToLower()) {
            throw "SKIP: DNS esta em outra subscription."
        }
 
        if ($DnsRG.ToLower() -ne $AllowedDnsRG.ToLower()) {
            throw "SKIP: DNS esta fora do RG-DNS-Brasil."
        }
 
        if ($DnsZone.ToLower() -ne $HostName.ToLower()) {
            throw "SKIP: hostname diferente do apex da DNS Zone."
        }
 
          
        # TOKEN ATUAL FRONT DOOR
          
 
        $OldToken = $Before.validationProperties.validationToken
 
        if (-not $OldToken) {
            throw "SKIP: token atual do Front Door vazio."
        }
 
        Write-Host "Token FD atual : $OldToken" -ForegroundColor DarkGray
 
          
        # TXT ATUAL
          
 
        $TxtJson = az network dns record-set txt show `
            --resource-group $DnsRG `
            --zone-name $DnsZone `
            --name "_dnsauth" `
            -o json 2>$null
 
        if ($LASTEXITCODE -ne 0 -or -not $TxtJson) {
            throw "SKIP: _dnsauth nao encontrado."
        }
 
        $Txt = $TxtJson | ConvertFrom-Json
 
        $Values = @(
            $Txt.TXTRecords |
            ForEach-Object {
                if ($_.value) {
                    $_.value -join ""
                }
            }
        )
 
        if ($Values.Count -ne 1) {
            throw "SKIP: _dnsauth possui $($Values.Count) valores."
        }
 
        $OldDnsToken = $Values[0]
 
        Write-Host "TXT atual      : $OldDnsToken"
 
        # Trava igual ao piloto que funcionou
        if ($OldDnsToken -ne $OldToken) {
            throw "SKIP: TXT atual diferente do token atual do Front Door."
        }
 
          
        # REGENERAR
          
 
        Write-Host "Regenerando token..." -ForegroundColor Yellow
 
        az afd custom-domain regenerate-validation-token `
            --resource-group $FrontDoorRG `
            --profile-name $Profile `
            --custom-domain-name $ResourceName `
            -o none
 
        if ($LASTEXITCODE -ne 0) {
            throw "Falha no regenerate-validation-token."
        }
 
          
        # ESPERAR TOKEN NOVO
          
 
        for ($Attempt = 1; $Attempt -le 24; $Attempt++) {
 
            Start-Sleep -Seconds 5
 
            $AfterJson = az afd custom-domain show `
                --resource-group $FrontDoorRG `
                --profile-name $Profile `
                --custom-domain-name $ResourceName `
                -o json
 
            if ($LASTEXITCODE -ne 0) {
                continue
            }
 
            $After = $AfterJson | ConvertFrom-Json
 
            $Candidate = $After.validationProperties.validationToken
 
            if ($Candidate -and $Candidate -ne $OldToken) {
 
                $NewToken   = $Candidate
                $Expiration = $After.validationProperties.expirationDate
                break
            }
 
            Write-Host "Aguardando novo token... $Attempt/24" -ForegroundColor DarkGray
        }
 
        if (-not $NewToken) {
            throw "Novo token nao apareceu. DNS nao alterado."
        }
 
        Write-Host "Novo token     : $NewToken" -ForegroundColor Green
        Write-Host "Expira         : $Expiration"
 
          
        # TROCAR SOMENTE O TXT
          
 
        Write-Host "Atualizando _dnsauth..." -ForegroundColor Yellow
 
        az network dns record-set txt remove-record `
            --resource-group $DnsRG `
            --zone-name $DnsZone `
            --record-set-name "_dnsauth" `
            --value $OldDnsToken `
            --keep-empty-record-set `
            -o none
 
        if ($LASTEXITCODE -ne 0) {
            throw "Falha removendo token antigo."
        }
 
        az network dns record-set txt add-record `
            --resource-group $DnsRG `
            --zone-name $DnsZone `
            --record-set-name "_dnsauth" `
            --value $NewToken `
            -o none
 
        if ($LASTEXITCODE -ne 0) {
 
            Write-Host "Falha no novo token. Tentando rollback..." -ForegroundColor Red
 
            az network dns record-set txt add-record `
                --resource-group $DnsRG `
                --zone-name $DnsZone `
                --record-set-name "_dnsauth" `
                --value $OldDnsToken `
                -o none
 
            throw "Falha adicionando novo token. Rollback executado/tentado."
        }
 
          
        # VALIDAR AZURE DNS
          
 
        $CheckJson = az network dns record-set txt show `
            --resource-group $DnsRG `
            --zone-name $DnsZone `
            --name "_dnsauth" `
            -o json
 
        if ($LASTEXITCODE -ne 0) {
            throw "Falha validando Azure DNS."
        }
 
        $Check = $CheckJson | ConvertFrom-Json
 
        $CurrentValues = @(
            $Check.TXTRecords |
            ForEach-Object {
                if ($_.value) {
                    $_.value -join ""
                }
            }
        )
 
        if ($CurrentValues.Count -ne 1) {
            throw "Azure DNS possui quantidade inesperada de valores."
        }
 
        if ($CurrentValues[0] -ne $NewToken) {
            throw "Azure DNS nao possui o token novo esperado."
        }
 
        Write-Host "Azure DNS      : OK" -ForegroundColor Green
 
        
        # VALIDAR DNS PUBLICO
          
 
        $PublicOk = $false
 
        for ($DnsAttempt = 1; $DnsAttempt -le 18; $DnsAttempt++) {
 
            $DigResult = dig +short TXT "_dnsauth.$HostName"
 
            if ($DigResult -match [regex]::Escape($NewToken)) {
 
                $PublicOk = $true
                break
            }
 
            Write-Host "Aguardando DNS publico... $DnsAttempt/18" -ForegroundColor DarkGray
 
            Start-Sleep -Seconds 10
        }
 
        if (-not $PublicOk) {
            throw "Azure DNS OK, mas token ainda nao apareceu no DNS publico."
        }
 
        Write-Host "DNS publico    : OK" -ForegroundColor Green
 
          
        # SUCESSO
          
 
        $Results += [PSCustomObject]@{
            Domain       = $HostName
            ResourceName = $ResourceName
            DNSZone      = $DnsZone
            OldToken     = $OldDnsToken
            NewToken     = $NewToken
            Expiration   = $Expiration
            Result       = "OK"
        }
 
        Write-Host ""
        Write-Host "SUCESSO: $HostName" -ForegroundColor Green
 
        Start-Sleep -Seconds 3
    }
 
    catch {
 
        $Message = $_.Exception.Message
 
        if ($Message.StartsWith("SKIP:")) {
 
            Write-Host $Message -ForegroundColor Yellow
            $Result = $Message
 
        } else {
 
            Write-Host "ERRO: $Message" -ForegroundColor Red
            $Result = "ERRO: $Message"
        }
 
        $Results += [PSCustomObject]@{
            Domain       = $HostName
            ResourceName = $ResourceName
            DNSZone      = $DnsZone
            OldToken     = $OldDnsToken
            NewToken     = $NewToken
            Expiration   = $Expiration
            Result       = $Result
        }
 
        continue
    }
}
 
    
# RELATORIO
    
 
Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " RESULTADO FINAL" -ForegroundColor Cyan
Write-Host "========================================================"
Write-Host ""
 
$Results |
    Format-Table Domain, Result -AutoSize
 
$Results |
    Export-Csv `
        -Path $LogFile `
        -NoTypeInformation `
        -Encoding UTF8
 
$OkCount    = @($Results | Where-Object { $_.Result -eq "OK" }).Count
$SkipCount  = @($Results | Where-Object { $_.Result -like "SKIP:*" }).Count
$ErrorCount = @($Results | Where-Object { $_.Result -like "ERRO:*" }).Count
 
Write-Host ""
Write-Host "OK    : $OkCount" -ForegroundColor Green
Write-Host "SKIP  : $SkipCount" -ForegroundColor Yellow
Write-Host "ERRO  : $ErrorCount" -ForegroundColor Red
Write-Host ""
Write-Host "Log: $LogFile" -ForegroundColor Cyan