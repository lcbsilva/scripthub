# auditoria de grupos do SharePoint Online: somente leitura, não modifica o ambiente
# audita todos os grupos e membros de todas as coleções de sites e subsites do tenant

$TenantName = "TENANT_NAME"
$ClientId   = "CLIENT_ID" # crie um Enterprise Application no Entra ID e configure as permissões Microsoft Graph: "Group.ReadWrite.All", "User.ReadWrite.All" e SharePoint "AllSites.FullControl", "TermStore.ReadWrite.All" e "User.ReadWrite.All"

$AdminUrl = "URL_ADMIN_SHAREPOINT"
$Data     = Get-Date -Format "yyyyMMdd-HHmm"

$CsvMembros = ".\Auditoria-SharePoint-Grupos-Membros-$Data.csv"
$CsvErros   = ".\Auditoria-SharePoint-Erros-$Data.csv"

$Resultado = [System.Collections.Generic.List[object]]::new()
$Erros     = [System.Collections.Generic.List[object]]::new()

Import-Module PnP.PowerShell

# Conexão somente para consulta
$AdminConnection = Connect-PnPOnline `
    -Url $AdminUrl `
    -Interactive `
    -ClientId $ClientId `
    -ReturnConnection

# Consulta todas as coleções de sites
$Sites = Get-PnPTenantSite -Connection $AdminConnection

foreach ($Site in $Sites) {

    Write-Host "Auditando coleção: $($Site.Url)" -ForegroundColor Cyan

    try {
        $RootConnection = Connect-PnPOnline `
            -Url $Site.Url `
            -Interactive `
            -ClientId $ClientId `
            -ReturnConnection

        $RootWeb = Get-PnPWeb `
            -Includes Title,Url `
            -Connection $RootConnection

        # Consulta todos os subsites recursivamente
        $Subsites = @(
            Get-PnPSubWeb `
                -Recurse `
                -Includes Title,Url `
                -Connection $RootConnection
        )

        $Webs = @($RootWeb) + $Subsites

        foreach ($Web in $Webs) {

            Write-Host "  Site/Subsite: $($Web.Url)" -ForegroundColor Yellow

            try {
                if ($Web.Url -eq $Site.Url) {
                    $WebConnection = $RootConnection
                }
                else {
                    $WebConnection = Connect-PnPOnline `
                        -Url $Web.Url `
                        -Interactive `
                        -ClientId $ClientId `
                        -ReturnConnection
                }

                # Consulta os grupos do SharePoint
                $Groups = @(Get-PnPGroup -Connection $WebConnection)

                foreach ($Group in $Groups) {

                    try {
                        # Consulta os membros do grupo
                        $Members = @(
                            Get-PnPGroupMember `
                                -Group $Group.Id `
                                -Connection $WebConnection `
                                -ErrorAction Stop
                        )

                        if ($Members.Count -eq 0) {
                            $Resultado.Add([PSCustomObject]@{
                                ColecaoDeSites = $Site.Url
                                SiteOuSubsite   = $Web.Url
                                TituloSite      = $Web.Title
                                IDGrupo         = $Group.Id
                                Grupo           = $Group.Title
                                Membro          = ""
                                Email           = ""
                                Login           = ""
                                Tipo            = ""
                                GrupoVazio      = "Sim"
                            })
                        }
                        else {
                            foreach ($Member in $Members) {
                                $Resultado.Add([PSCustomObject]@{
                                    ColecaoDeSites = $Site.Url
                                    SiteOuSubsite   = $Web.Url
                                    TituloSite      = $Web.Title
                                    IDGrupo         = $Group.Id
                                    Grupo           = $Group.Title
                                    Membro          = $Member.Title
                                    Email           = $Member.Email
                                    Login           = $Member.LoginName
                                    Tipo            = $Member.PrincipalType
                                    GrupoVazio      = "Não"
                                })
                            }
                        }
                    }
                    catch {
                        $Erros.Add([PSCustomObject]@{
                            Site  = $Web.Url
                            Grupo = $Group.Title
                            Etapa = "Consulta dos membros"
                            Erro  = $_.Exception.Message
                        })
                    }
                }
            }
            catch {
                $Erros.Add([PSCustomObject]@{
                    Site  = $Web.Url
                    Grupo = ""
                    Etapa = "Consulta do site/subsite"
                    Erro  = $_.Exception.Message
                })
            }
        }
    }
    catch {
        $Erros.Add([PSCustomObject]@{
            Site  = $Site.Url
            Grupo = ""
            Etapa = "Conexão com a coleção"
            Erro  = $_.Exception.Message
        })
    }
}

# Grava apenas arquivos locais
$Resultado |
    Sort-Object ColecaoDeSites, SiteOuSubsite, Grupo, Membro |
    Export-Csv `
        -Path $CsvMembros `
        -Delimiter ";" `
        -Encoding utf8BOM `
        -NoTypeInformation

$Erros |
    Export-Csv `
        -Path $CsvErros `
        -Delimiter ";" `
        -Encoding utf8BOM `
        -NoTypeInformation

Write-Host ""
Write-Host "Auditoria finalizada." -ForegroundColor Green
Write-Host "Relatório: $CsvMembros"
Write-Host "Erros: $CsvErros"
