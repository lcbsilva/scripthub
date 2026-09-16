<#
.SYNOPSIS
Audita usuários com licença Basic no Azure DevOps e identifica usuários potencialmente inativos.

.DESCRIPTION
Consulta usuários com licença Basic, verifica atividade recente em commits, builds e Boards e gera um relatório CSV com uma sugestão de ação para cada usuário.

.NOTES
O PAT deve ser informado no campo correspondente antes da execução. O script considera atividade nos últimos 30 dias.
#>

# Conecta à conta Azure utilizada para a execução.
Connect-AzAccount

# Obtém um Personal Access Token (PAT) do Azure DevOps com as permissões necessárias.
# Informe o nome das organizações, o PAT e os respectivos escopos conforme a política da organização.
$organizations = @("org1", "org2")  # Substitua pelos nomes das organizações.
$pat = "YOUR_PAT_HERE"
$authHeader = @{
    Authorization = ("Basic {0}" -f [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat")))
}

# Define o período utilizado para considerar um usuário como ativo.
$cutoff = (Get-Date).AddDays(-30)

function Invoke-AzDo {
    param($Uri)

    try {
        return Invoke-RestMethod -Uri $Uri -Headers $authHeader -ErrorAction Stop
    } catch {
        return $null
    }
}

$report = @()

foreach ($org in $organizations) {
    Write-Host "`nChecando organização: $org" -ForegroundColor Cyan

    # Obtém os usuários com licença Basic.
    $uriUsers = "https://vsaex.dev.azure.com/$org/_apis/userentitlements?top=1000&api-version=7.1-preview.1"
    $resUsers = Invoke-AzDo $uriUsers

    if (-not $resUsers) { Write-Warning "Falha ao obter usuários na organização $org"; continue }

    $basicUsers = $resUsers.value | Where-Object { $_.accessLevel.licenseDisplayName -eq "Basic" }

    foreach ($u in $basicUsers) {
        $email = $u.user.mailAddress
        $name = $u.user.displayName
        Write-Host "Usuário: $name"
        $active = $false

        # 1. Verifica atividade em commits.
        $uriRepos = "https://dev.azure.com/$org/_apis/projects?api-version=7.1"
        $projects = Invoke-AzDo $uriRepos

        foreach ($p in $projects.value) {
            $uriGit = "https://dev.azure.com/$org/$($p.name)/_apis/git/repositories?api-version=7.1"
            $repos = Invoke-AzDo $uriGit

            foreach ($r in $repos.value) {
                $uriCommits = "https://dev.azure.com/$org/$($p.name)/_apis/git/repositories/$($r.id)/commits?searchCriteria.author=$email&$top=1&api-version=7.1"
                $comm = Invoke-AzDo $uriCommits

                if ($comm.value -and [datetime]$comm.value[0].author.date -ge $cutoff) { $active = $true }
                if ($active) { break }
            }
            if ($active) { break }
        }

        # 2. Verifica atividade em builds.
        if (-not $active) {
            foreach ($p in $projects.value) {
                $uriBuilds = "https://dev.azure.com/$org/$($p.name)/_apis/build/builds?requestedFor=$email&$top=1&api-version=7.1"
                $b = Invoke-AzDo $uriBuilds

                if ($b.value -and [datetime]$b.value[0].queueTime -ge $cutoff) {
                    $active = $true; break
                }
            }
        }

        # 3. Verifica atividade em Boards (alterações de work items).
        if (-not $active) {
            foreach ($p in $projects.value) {
                $uriWork = "https://dev.azure.com/$org/$($p.name)/_apis/wit/activitylogs?user=$email&$top=1&startDateTime=$($cutoff.ToString("o"))&api-version=7.1"
                $w = Invoke-AzDo $uriWork

                if ($w.value) {
                    $active = $true; break
                }
            }
        }

        # Define a sugestão de ação com base na atividade encontrada.
        $action = if ($active) { "Keep Basic" } else { "Change it to Stakeholder" }

        $report += [PSCustomObject]@{
            Organization = $org
            Name = $name
            Email = $email
            Licence = "Basic"
            ActiveLast30d = $active
            ActionSugestion = $action
        }
    }
}

# Exporta o resultado para CSV.
$out = Join-Path (Get-Location).Path "Audit_Basic_Licence.csv"
$report | Sort-Object Organization, Name | ConvertTo-Csv -NoTypeInformation -Delimiter ';' | Out-File -FilePath $out -Encoding UTF8

Write-Host "`nRelatório gerado: $out" -ForegroundColor Green