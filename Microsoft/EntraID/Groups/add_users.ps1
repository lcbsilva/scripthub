
# Script para adicionar usuários a grupos no Microsoft Entra ID (Azure AD) usando Microsoft Graph PowerShell SDK

Connect-MgGraph -Scopes "User.Read.All", "Group.ReadWrite.All"

# Usuários que receberão os grupos
$usuarios = @(
    "usuario1@empresa.com",
    "usuario2@empresa.com",
    "usuario3@empresa.com"
)

# Grupos que todos os usuários receberão
$grupos = @(
    "GRP-Grupo01",
    "GRP-Grupo02",
    "GRP-Grupo03",
    "GRP-Grupo04",
    "GRP-Grupo05",
    "GRP-Grupo06",
    "GRP-Grupo07",
    "GRP-Grupo08",
    "GRP-Grupo09",
    "GRP-Grupo10",
    "GRP-Grupo11",
    "GRP-Grupo12",
    "GRP-Grupo13",
    "GRP-Grupo14",
    "GRP-Grupo15",
    "GRP-Grupo16",
    "GRP-Grupo17",
    "GRP-Grupo18",
    "GRP-Grupo19",
    "GRP-Grupo20",
    "GRP-Grupo21",
    "GRP-Grupo22",
    "GRP-Grupo23",
    "GRP-Grupo24",
    "GRP-Grupo25",
    "GRP-Grupo26",
    "GRP-Grupo27",
    "GRP-Grupo28",
    "GRP-Grupo29",
    "GRP-Grupo30"
)

foreach ($usuarioUPN in $usuarios) {

    Write-Host "`n=====================================" -ForegroundColor Cyan
    Write-Host "Usuário: $usuarioUPN" -ForegroundColor Cyan
    Write-Host "=====================================" -ForegroundColor Cyan

    try {
        $usuario = Get-MgUser -UserId $usuarioUPN -ErrorAction Stop
    }
    catch {
        Write-Host "Usuário não encontrado: $usuarioUPN" -ForegroundColor Red
        continue
    }

    foreach ($nomeGrupo in $grupos) {

        try {
            $grupo = Get-MgGroup `
                -Filter "displayName eq '$nomeGrupo'" `
                -ConsistencyLevel eventual `
                -ErrorAction Stop

            if (-not $grupo) {
                Write-Host "$nomeGrupo -> GRUPO NÃO ENCONTRADO" -ForegroundColor Red
                continue
            }

            if ($grupo.Count -gt 1) {
                Write-Host "$nomeGrupo -> MAIS DE UM GRUPO ENCONTRADO" -ForegroundColor Red
                continue
            }

            # Verifica se já é membro
            $membro = Get-MgGroupMember `
                -GroupId $grupo.Id `
                -All |
                Where-Object { $_.Id -eq $usuario.Id }

            if ($membro) {
                Write-Host "$nomeGrupo -> já é membro" -ForegroundColor Yellow
                continue
            }

            # Adiciona
            New-MgGroupMemberByRef `
                -GroupId $grupo.Id `
                -OdataId "https://graph.microsoft.com/v1.0/directoryObjects/$($usuario.Id)"

            Write-Host "$nomeGrupo -> ADICIONADO" -ForegroundColor Green
        }
        catch {
            Write-Host "$nomeGrupo -> ERRO: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}